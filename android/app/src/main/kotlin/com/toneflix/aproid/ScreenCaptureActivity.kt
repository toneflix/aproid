package com.toneflix.aproid

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle

/** An invisible screen that shows Android's "start recording?" prompt and hands the answer to the service. */
class ScreenCaptureActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ScreenPlugin.clearAsk(this)

        if (ScreenService.isRunning || ScreenPlugin.pending == null) {
            finish()
            return
        }

        if (savedInstanceState == null) {
            val projections = getSystemService(MediaProjectionManager::class.java)
            startActivityForResult(projections.createScreenCaptureIntent(), REQUEST_CAPTURE)
        }
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
    }
}
