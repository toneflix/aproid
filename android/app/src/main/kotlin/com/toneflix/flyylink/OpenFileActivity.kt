package com.toneflix.flyylink

import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast

/**
 * Opens a received file in the app that handles it, for the Recent list and the "file received" notification.
 * When the file is gone, or no app opens its type, it says so and shows Downloads instead of doing nothing.
 */
class OpenFileActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        intent.data?.let { open(it, intent.type) }
        finish()
    }

    private fun open(uri: Uri, mimeType: String?) {
        if (!exists(uri)) {
            Toast.makeText(this, R.string.share_file_gone, Toast.LENGTH_SHORT).show()
            return
        }

        // An unknown type lets any app that opens files offer to, instead of none.
        val type = listOf(mimeType, contentResolver.getType(uri)).firstOrNull { it != null && it != UNKNOWN_TYPE } ?: "*/*"
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, type)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        try {
            startActivity(view)
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, R.string.share_no_app, Toast.LENGTH_LONG).show()
            runCatching { startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)) }
        }
    }

    private fun exists(uri: Uri): Boolean =
        runCatching { contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false }.getOrDefault(false)

    companion object {
        private const val UNKNOWN_TYPE = "application/octet-stream"

        fun intent(context: Context, uri: Uri, mimeType: String?): Intent =
            Intent(context, OpenFileActivity::class.java)
                .setDataAndType(uri, mimeType)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}
