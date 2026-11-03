package com.daichi.screenrecorder

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {

    private lateinit var modeGroup: RadioGroup
    private lateinit var modeVideo: RadioButton
    private lateinit var videoOptions: View
    private lateinit var orientationGroup: RadioGroup
    private lateinit var orientationLandscape: RadioButton
    private lateinit var qualityGroup: RadioGroup
    private lateinit var qualityHigh: RadioButton
    private lateinit var openYoutube: CheckBox
    private lateinit var startButton: Button
    private lateinit var stopButton: Button
    private lateinit var statusText: TextView
    private lateinit var openLastButton: Button

    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            updateUi()
            if (RecorderService.isRecording) handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        modeGroup = requireViewById<RadioGroup>(R.id.modeGroup)
        modeVideo = requireViewById<RadioButton>(R.id.modeVideo)
        videoOptions = requireViewById<View>(R.id.videoOptions)
        orientationGroup = requireViewById<RadioGroup>(R.id.orientationGroup)
        orientationLandscape = requireViewById<RadioButton>(R.id.orientationLandscape)
        qualityGroup = requireViewById<RadioGroup>(R.id.qualityGroup)
        qualityHigh = requireViewById<RadioButton>(R.id.qualityHigh)
        openYoutube = requireViewById<CheckBox>(R.id.openYoutube)
        startButton = requireViewById<Button>(R.id.startButton)
        stopButton = requireViewById<Button>(R.id.stopButton)
        statusText = requireViewById<TextView>(R.id.statusText)
        openLastButton = requireViewById<Button>(R.id.openLastButton)

        modeGroup.setOnCheckedChangeListener { _, _ -> updateUi() }
        startButton.setOnClickListener { onStartClicked() }
        stopButton.setOnClickListener {
            startService(Intent(this, RecorderService::class.java).setAction(RecorderService.ACTION_STOP))
        }
        openLastButton.setOnClickListener { openLast() }
    }

    override fun onResume() {
        super.onResume()
        RecorderService.listener = {
            handler.removeCallbacks(ticker)
            ticker.run()
        }
        handler.removeCallbacks(ticker)
        ticker.run()
    }

    override fun onPause() {
        super.onPause()
        RecorderService.listener = null
        handler.removeCallbacks(ticker)
    }

    private fun onStartClicked() {
        val needed = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) needed += Manifest.permission.POST_NOTIFICATIONS
        val missing = needed.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) requestCapture() else requestPermissions(missing.toTypedArray(), REQ_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_PERMISSIONS) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            requestCapture()
        } else {
            statusText.text = "アプリの音を録音するには「マイク」の許可が必要です（マイクの音は録音しません）。設定アプリから許可してください。"
        }
    }

    private fun requestCapture() {
        val mpm = getSystemService(MediaProjectionManager::class.java)!!
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CAPTURE) return
        if (resultCode != RESULT_OK || data == null) {
            statusText.text = "キャンセルされました"
            return
        }
        val intent = Intent(this, RecorderService::class.java)
            .setAction(RecorderService.ACTION_START)
            .putExtra(RecorderService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(RecorderService.EXTRA_DATA, data)
            .putExtra(RecorderService.EXTRA_VIDEO, modeVideo.isChecked)
            .putExtra(RecorderService.EXTRA_LANDSCAPE, orientationLandscape.isChecked)
            .putExtra(RecorderService.EXTRA_HIGH_QUALITY, qualityHigh.isChecked)
        startForegroundService(intent)
        if (openYoutube.isChecked) handler.postDelayed({ openYouTube() }, 500)
    }

    private fun openYouTube() {
        val app = packageManager.getLaunchIntentForPackage(YOUTUBE_PACKAGE)
        try {
            startActivity(app ?: Intent(Intent.ACTION_VIEW, Uri.parse("https://m.youtube.com")))
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, "YouTube を開けませんでした", Toast.LENGTH_SHORT).show()
        }
    }

    private fun openLast() {
        val result = RecorderService.lastResult ?: return
        val uri = result.uri ?: return
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, if (result.isVideo) "video/mp4" else "audio/mp4")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, "再生できるアプリがありません", Toast.LENGTH_SHORT).show()
        }
    }

    private fun updateUi() {
        val recording = RecorderService.isRecording
        val video = modeVideo.isChecked

        videoOptions.visibility = if (video) View.VISIBLE else View.GONE
        startButton.text = if (video) "● 録画開始" else "● 録音開始"
        startButton.isEnabled = !recording
        stopButton.isEnabled = recording
        for (group in listOf(modeGroup, orientationGroup, qualityGroup)) {
            for (i in 0 until group.childCount) group.getChildAt(i).isEnabled = !recording
        }
        openYoutube.isEnabled = !recording

        val result = RecorderService.lastResult
        if (recording) {
            val sec = (System.currentTimeMillis() - RecorderService.startedAt) / 1000
            val kind = if (RecorderService.recordingVideo) "録画中" else "録音中"
            statusText.text = "● $kind　%d:%02d".format(sec / 60, sec % 60)
            openLastButton.visibility = View.GONE
        } else {
            statusText.text = result?.message ?: "待機中"
            openLastButton.visibility = if (result?.uri != null) View.VISIBLE else View.GONE
            openLastButton.text = if (result?.isVideo == false) "保存した録音を開く" else "保存した録画を開く"
        }
    }

    companion object {
        private const val REQ_PERMISSIONS = 1
        private const val REQ_CAPTURE = 2
        private const val YOUTUBE_PACKAGE = "com.google.android.youtube"
    }
}
