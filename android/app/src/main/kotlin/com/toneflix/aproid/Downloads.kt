package com.toneflix.aproid

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.File
import java.io.OutputStream

/** A file being written to the phone's Downloads folder. Call [publish] when complete or [discard] on failure. */
class DownloadTarget private constructor(
    private val context: Context,
    val uri: Uri?,
    private val file: File?,
    val mimeType: String,
) {
    fun open(): OutputStream =
        uri?.let { context.contentResolver.openOutputStream(it) } ?: file!!.outputStream()

    fun publish() {
        val uri = uri ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return

        context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
    }

    fun discard() {
        uri?.let { context.contentResolver.delete(it, null, null) }
        file?.delete()
    }

    companion object {
        /** Creates an empty file named [name] in Downloads. Android renames it if the name is taken. */
        fun create(context: Context, name: String): DownloadTarget? {
            val extension = name.substringAfterLast('.', "").lowercase()
            val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null

                return DownloadTarget(context, uri, null, mimeType)
            }

            // Before Android 10 the shared folder needs a storage permission, so keep files in our own one.
            val folder = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: return null
            return DownloadTarget(context, null, unique(folder, name), mimeType)
        }

        private fun unique(folder: File, name: String): File {
            val base = name.substringBeforeLast('.')
            val extension = name.substringAfterLast('.', "").let { if (it.isEmpty()) "" else ".$it" }
            var file = File(folder, name)
            var copy = 1

            while (file.exists()) {
                copy += 1
                file = File(folder, "$base ($copy)$extension")
            }

            return file
        }
    }
}
