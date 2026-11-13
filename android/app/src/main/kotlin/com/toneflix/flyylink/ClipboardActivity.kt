package com.toneflix.flyylink

import android.app.Activity
import android.widget.Toast

/** An invisible screen that exists only to read the clipboard, which needs focus, and send it. */
class ClipboardActivity : Activity() {
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return

        val message = if (ClipboardPlugin.send(this)) R.string.clipboard_sent else R.string.clipboard_empty
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
    }
}
