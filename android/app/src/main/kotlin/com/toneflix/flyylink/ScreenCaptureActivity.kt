package com.toneflix.flyylink

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle

/**
 * An invisible screen that shows Android's "start recording?" prompt and hands the answer to the service.
 * When the Mac wants sound too, it first asks for the audio permission; mirroring goes ahead either way.
 */
class ScreenCaptureActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ScreenPlugin.clearAsk(this)

        if (ScreenService.isRunning || ScreenPlugin.pending == null) {
            finish()
            return
        }

        if (savedInstanceState != null) return

        val wantsSound = ScreenPlugin.pending?.audio == true && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        if (wantsSound && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_AUDIO)
        } else {
            askToRecord()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_AUDIO) askToRecord()
    }

    private fun askToRecord() {
        val projections = getSystemService(MediaProjectionManager::class.java)
        startActivityForResult(projections.createScreenCaptureIntent(), REQUEST_CAPTURE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val pending = ScreenPlugin.pending
        if (requestCode == REQUEST_CAPTURE && resultCode == RESULT_OK && data != null && pending != null) {
            ScreenService.start(this, resultCode, data)
        }
        finish()
    }

    private companion object {
        const val REQUEST_CAPTURE = 1
        const val REQUEST_AUDIO = 2
    }
}
