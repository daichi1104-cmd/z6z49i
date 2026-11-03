package com.daichi.screenrecorder

import android.annotation.SuppressLint
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.projection.MediaProjection
import android.os.Bundle
import android.util.Log
import android.view.Surface
import java.io.FileDescriptor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min

/**
 * 画面の映像（MediaProjection → VirtualDisplay → H.264）と、
 * 他のアプリが再生している音（AudioPlaybackCapture → AAC）を MP4 / M4A に書き出す。
 */
class CaptureEngine(
    private val projection: MediaProjection,
    private val recordVideo: Boolean,
    private val width: Int,
    private val height: Int,
    private val dpi: Int,
    private val videoBitrate: Int,
    output: FileDescriptor,
) {
    private val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private val muxerLock = Object()
    private var muxerStarted = false
    private var tracksAdded = 0
    private val tracksExpected = if (recordVideo) 2 else 1
    private var videoTrack = -1
    private var audioTrack = -1

    @Volatile private var running = false

    private var videoCodec: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var audioCodec: MediaCodec? = null
    private var audioRecord: AudioRecord? = null
    private var videoThread: Thread? = null
    private var audioThread: Thread? = null

    /** 一度でも無音でない音が入ったか（アプリが録音を拒否していると、ずっと無音になる） */
    @Volatile var hasSound = false
        private set

    fun start() {
        try {
            if (recordVideo) setupVideo()
            setupAudio()
        } catch (e: Exception) {
            releaseAll()
            throw e
        }
        running = true
        videoCodec?.let { codec -> videoThread = thread(name = "video-encoder") { videoLoop(codec) } }
        audioThread = thread(name = "audio-encoder") { audioLoop() }
    }

    /** 停止してファイルを書き終える。正しく保存できたら true */
    fun stop(): Boolean {
        running = false
        try { audioRecord?.stop() } catch (_: Exception) {}
        videoThread?.join(5000)
        audioThread?.join(5000)
        var ok = false
        synchronized(muxerLock) {
            if (muxerStarted) {
                try {
                    muxer.stop()
                    ok = true
                } catch (e: Exception) {
                    Log.e(TAG, "muxer.stop failed", e)
                }
            }
        }
        releaseAll()
        return ok
    }

    private fun setupVideo() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, videoBitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // 画面が止まっていても一定間隔でフレームを出す
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 1_000_000L / FRAME_RATE)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        videoCodec = codec
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = codec.createInputSurface()
        inputSurface = surface
        codec.start()
        virtualDisplay = projection.createVirtualDisplay(
            "ScreenRecorder", width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null,
        )
    }

    @SuppressLint("MissingPermission") // RECORD_AUDIO は MainActivity で許可を取ってから開始する
    private fun setupAudio() {
        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val pcmFormat = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT,
        )
        audioRecord = AudioRecord.Builder()
            .setAudioFormat(pcmFormat)
            .setBufferSizeInBytes(max(minBuf * 4, 16 * 1024))
            .setAudioPlaybackCaptureConfig(config)
            .build()
        check(audioRecord?.state == AudioRecord.STATE_INITIALIZED) { "AudioRecord を初期化できませんでした" }

        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, CHANNELS).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BITRATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        audioCodec = codec
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
    }

    private fun videoLoop(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        try {
            while (running) drain(codec, info, isVideo = true, endOfStream = false)
            codec.signalEndOfInputStream()
            drain(codec, info, isVideo = true, endOfStream = true)
        } catch (e: Exception) {
            Log.e(TAG, "video encoder error", e)
        }
    }

    private fun audioLoop() {
        val codec = audioCodec ?: return
        val record = audioRecord ?: return
        val info = MediaCodec.BufferInfo()
        var lastPts = 0L
        try {
            record.startRecording()
            while (running) {
                val index = codec.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) {
                    val buf = codec.getInputBuffer(index) ?: continue
                    buf.clear()
                    val read = record.read(buf, buf.capacity())
                    if (read > 0) {
                        if (!hasSound) checkSound(buf, read)
                        // 読み終えた時刻から、その分の長さを引いた時刻を先頭の時刻にする（映像と同じ時計）
                        var pts = System.nanoTime() / 1000 - read.toLong() / BYTES_PER_FRAME * 1_000_000L / SAMPLE_RATE
                        if (pts <= lastPts) pts = lastPts + 1
                        lastPts = pts
                        codec.queueInputBuffer(index, 0, read, pts, 0)
                    } else {
                        codec.queueInputBuffer(index, 0, 0, lastPts + 1, 0)
                    }
                }
                drain(codec, info, isVideo = false, endOfStream = false)
            }
            // 終わりの合図を送って、残りを書き出す
            for (i in 0 until 100) {
                val index = codec.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) {
                    codec.queueInputBuffer(index, 0, 0, lastPts + 1, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                drain(codec, info, isVideo = false, endOfStream = false)
            }
            drain(codec, info, isVideo = false, endOfStream = true)
        } catch (e: Exception) {
            Log.e(TAG, "audio encoder error", e)
        }
    }

    private fun checkSound(buf: ByteBuffer, size: Int) {
        val shorts = buf.duplicate().apply { position(0); limit(size) }
            .order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        while (shorts.hasRemaining()) {
            val v = shorts.get().toInt()
            if (v > 8 || v < -8) {
                hasSound = true
                return
            }
        }
    }

    private fun drain(codec: MediaCodec, info: MediaCodec.BufferInfo, isVideo: Boolean, endOfStream: Boolean) {
        var waits = 0
        while (true) {
            val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++waits > 200) return
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> addTrack(codec.outputFormat, isVideo)
                index >= 0 -> {
                    val buf = codec.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && buf != null) {
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        writeSample(isVideo, buf, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    private fun addTrack(format: MediaFormat, isVideo: Boolean) {
        synchronized(muxerLock) {
            if (muxerStarted) return
            val track = muxer.addTrack(format)
            if (isVideo) videoTrack = track else audioTrack = track
            tracksAdded++
            if (tracksAdded == tracksExpected) {
                muxer.start()
                muxerStarted = true
                // 開始前に捨てた映像があるので、すぐにキーフレームを出してもらう
                videoCodec?.setParameters(Bundle().apply {
                    putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                })
            }
        }
    }

    private fun writeSample(isVideo: Boolean, buf: ByteBuffer, info: MediaCodec.BufferInfo) {
        synchronized(muxerLock) {
            if (!muxerStarted) return // 全部のトラックがそろうまでは捨てる
            muxer.writeSampleData(if (isVideo) videoTrack else audioTrack, buf, info)
        }
    }

    private fun releaseAll() {
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { videoCodec?.stop() } catch (_: Exception) {}
        try { videoCodec?.release() } catch (_: Exception) {}
        try { inputSurface?.release() } catch (_: Exception) {}
        try { audioCodec?.stop() } catch (_: Exception) {}
        try { audioCodec?.release() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        try { muxer.release() } catch (_: Exception) {}
        virtualDisplay = null; videoCodec = null; inputSurface = null
        audioCodec = null; audioRecord = null
    }

    companion object {
        private const val TAG = "CaptureEngine"
        private const val TIMEOUT_US = 10_000L
        private const val FRAME_RATE = 30
        private const val SAMPLE_RATE = 44_100
        private const val CHANNELS = 2
        private const val BYTES_PER_FRAME = 4 // 16bit × 2ch
        private const val AUDIO_BITRATE = 192_000

        /**
         * 画面の大きさ（srcW × srcH）を、長い辺が maxLong 以下でエンコーダが対応している大きさに縮める。
         */
        fun chooseVideoSize(srcW: Int, srcH: Int, maxLong: Int): Pair<Int, Int> {
            val caps = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .firstOrNull { info ->
                    info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) }
                }
                ?.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                ?.videoCapabilities
            var longSide = min(maxLong, max(srcW, srcH))
            while (longSide >= 320) {
                val scale = longSide.toDouble() / max(srcW, srcH)
                val w = align16(srcW * scale)
                val h = align16(srcH * scale)
                if (caps == null || caps.isSizeSupported(w, h)) return w to h
                longSide -= 160
            }
            return if (srcW >= srcH) 1280 to 720 else 720 to 1280
        }

        private fun align16(v: Double): Int = max(16, (v.toInt() / 16) * 16)
    }
}
