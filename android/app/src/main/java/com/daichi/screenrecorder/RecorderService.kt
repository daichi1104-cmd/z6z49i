package com.daichi.screenrecorder

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.hardware.display.DisplayManager
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min

/** 録画・録音中ずっと動き続けるサービス。通知の「停止」ボタンからも止められる。 */
class RecorderService : Service() {

    data class Result(val uri: Uri?, val isVideo: Boolean, val message: String)

    companion object {
        const val ACTION_START = "com.daichi.screenrecorder.START"
        const val ACTION_STOP = "com.daichi.screenrecorder.STOP"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA = "data"
        const val EXTRA_VIDEO = "video"
        const val EXTRA_LANDSCAPE = "landscape"
        const val EXTRA_HIGH_QUALITY = "highQuality"

        private const val TAG = "RecorderService"
        private const val CHANNEL_RECORDING = "recording"
        private const val CHANNEL_DONE = "done"
        private const val NOTIFICATION_RECORDING = 1
        private const val NOTIFICATION_DONE = 2

        /** 録画・録音中か（画面の表示用） */
        @Volatile var isRecording = false
            private set

        /** 録画・録音しているのが映像か */
        @Volatile var recordingVideo = true
            private set

        /** 録画・録音を始めた時刻（経過時間の表示用） */
        @Volatile var startedAt = 0L
            private set

        /** 最後の録画・録音の結果 */
        @Volatile var lastResult: Result? = null
            private set

        /** 状態が変わったときにメインスレッドで呼ばれる */
        var listener: (() -> Unit)? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var engine: CaptureEngine? = null
    private var pfd: ParcelFileDescriptor? = null
    private var outputUri: Uri? = null
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> start(intent)
            ACTION_STOP -> stopRecording()
        }
        return START_NOT_STICKY
    }

    private fun start(intent: Intent) {
        if (isRecording || stopping) return
        val video = intent.getBooleanExtra(EXTRA_VIDEO, true)
        createChannels()
        // Android 14 以降は、MediaProjection を取る前にフォアグラウンドにする必要がある
        startForeground(
            NOTIFICATION_RECORDING, recordingNotification(video),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
        )

        try {
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
            val data: Intent = (if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
            } else {
                @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
            }) ?: throw IllegalStateException("画面共有の許可がありません")

            val mpm = getSystemService(MediaProjectionManager::class.java)!!
            val proj = mpm.getMediaProjection(resultCode, data)
                ?: throw IllegalStateException("画面共有を開始できませんでした")
            projection = proj
            // ユーザーがシステムの画面から共有を止めたときも保存して終わる
            proj.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    handler.post { stopRecording() }
                }
            }, handler)

            val (w, h, dpi) = videoSize(
                intent.getBooleanExtra(EXTRA_LANDSCAPE, true),
                intent.getBooleanExtra(EXTRA_HIGH_QUALITY, true),
            )
            val bitrate = if (intent.getBooleanExtra(EXTRA_HIGH_QUALITY, true)) 8_000_000 else 4_000_000

            val uri = createOutput(video)
            outputUri = uri
            val fd = contentResolver.openFileDescriptor(uri, "rw")
                ?: throw IOException("保存先のファイルを開けませんでした")
            pfd = fd

            val e = CaptureEngine(proj, video, w, h, dpi, bitrate, fd.fileDescriptor)
            e.start()
            engine = e
            recordingVideo = video
            startedAt = System.currentTimeMillis()
            isRecording = true
            Log.i(TAG, "started: video=$video size=${w}x$h")
            notifyListener()
        } catch (e: Exception) {
            Log.e(TAG, "start failed", e)
            cleanup(saved = false)
            lastResult = Result(null, video, "開始できませんでした：${e.message ?: e.javaClass.simpleName}")
            finish()
        }
    }

    private fun stopRecording() {
        if (stopping) return
        val e = engine
        if (e == null) {
            finish()
            return
        }
        stopping = true
        engine = null
        notifyListener()
        val video = recordingVideo
        // ファイルの書き終わりに少し時間がかかるので、別スレッドで止める
        thread(name = "stop-recording") {
            val ok = try { e.stop() } catch (ex: Exception) { Log.e(TAG, "stop failed", ex); false }
            val sound = e.hasSound
            handler.post {
                val uri = outputUri
                cleanup(saved = ok)
                val kind = if (video) "録画" else "録音"
                lastResult = when {
                    !ok -> Result(null, video, "${kind}が短すぎるか、保存に失敗しました")
                    !sound -> Result(uri, video,
                        "${kind}を保存しました。ただし音が入っていません。再生していたアプリが録音を許可していない可能性があります（Chrome で YouTube を開くと録音できる場合があります）")
                    else -> Result(uri, video, "${kind}を保存しました")
                }
                if (ok && uri != null) doneNotification(uri, video, lastResult!!.message)
                stopping = false
                finish()
            }
        }
    }

    private fun cleanup(saved: Boolean) {
        try { pfd?.close() } catch (_: Exception) {}
        pfd = null
        outputUri?.let { uri ->
            try {
                if (saved) {
                    contentResolver.update(uri, ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }, null, null)
                } else {
                    contentResolver.delete(uri, null, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "finalize failed", e)
            }
        }
        outputUri = null
        projection?.let { p ->
            projection = null
            try { p.stop() } catch (_: Exception) {}
        }
        isRecording = false
    }

    private fun finish() {
        isRecording = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        notifyListener()
    }

    private fun notifyListener() {
        handler.post { listener?.invoke() }
    }

    /** 画面の大きさから録画サイズを決める（幅, 高さ, dpi） */
    private fun videoSize(landscape: Boolean, high: Boolean): Triple<Int, Int, Int> {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        getSystemService(DisplayManager::class.java)!!.getDisplay(Display.DEFAULT_DISPLAY).getRealMetrics(metrics)
        val long = max(metrics.widthPixels, metrics.heightPixels)
        val short = min(metrics.widthPixels, metrics.heightPixels)
        val (srcW, srcH) = if (landscape) long to short else short to long
        val (w, h) = CaptureEngine.chooseVideoSize(srcW, srcH, if (high) 1920 else 1280)
        return Triple(w, h, metrics.densityDpi)
    }

    private fun createOutput(video: Boolean): Uri {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val values = ContentValues().apply {
            if (video) {
                put(MediaStore.MediaColumns.DISPLAY_NAME, "video_$stamp.mp4")
                put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/ScreenRecorder")
            } else {
                put(MediaStore.MediaColumns.DISPLAY_NAME, "audio_$stamp.m4a")
                put(MediaStore.MediaColumns.MIME_TYPE, "audio/mp4")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/ScreenRecorder")
            }
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = if (video) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        return contentResolver.insert(collection, values)
            ?: throw IOException("保存先のファイルを作れませんでした")
    }

    private fun createChannels() {
        val nm = getSystemService(NotificationManager::class.java)!!
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_RECORDING, "録画・録音中", NotificationManager.IMPORTANCE_LOW)
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_DONE, "保存の完了", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun recordingNotification(video: Boolean): Notification {
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, RecorderService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = Notification.Builder(this, CHANNEL_RECORDING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (video) "録画中" else "録音中")
            .setContentText("終わったら「停止」を押してください")
            .setOngoing(true)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setWhen(System.currentTimeMillis())
            .setContentIntent(openAppIntent())
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.drawable.ic_stop), "停止", stop,
                ).build()
            )
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun doneNotification(uri: Uri, video: Boolean, message: String) {
        val view = PendingIntent.getActivity(
            this, 2,
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, if (video) "video/mp4" else "audio/mp4")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = Notification.Builder(this, CHANNEL_DONE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (video) "録画を保存しました" else "録音を保存しました")
            .setContentText("タップして再生")
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setAutoCancel(true)
            .setContentIntent(view)
            .build()
        try {
            getSystemService(NotificationManager::class.java)!!.notify(NOTIFICATION_DONE, n)
        } catch (_: SecurityException) {
            // 通知が許可されていないときは出さない
        }
    }
}
