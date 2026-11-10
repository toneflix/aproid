package com.toneflix.aproid

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File
import java.io.OutputStream
import org.json.JSONObject

/** A file being written to the phone's Downloads folder. Call [publish] when complete or [discard] on failure. */
class DownloadTarget private constructor(
    private val context: Context,
    val uri: Uri?,
    private val file: File?,
    val mimeType: String,
) {
    /** With [append], adds to what is already there, to resume a stopped file. */
    fun open(append: Boolean = false): OutputStream =
        uri?.let { context.contentResolver.openOutputStream(it, if (append) "wa" else "w") }
            ?: java.io.FileOutputStream(file!!, append)

    /** The address another app opens the finished file with. Files from before Android 10 go through our FileProvider. */
    fun viewUri(): Uri? = uri ?: file?.let {
        runCatching { FileProvider.getUriForFile(context, "${context.packageName}.files", it) }.getOrNull()
    }

    fun publish() {
        val uri = uri ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return

        context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
    }

    fun discard() {
        uri?.let { context.contentResolver.delete(it, null, null) }
        file?.delete()
    }

    /** How many bytes are in the file so far, or null when it is gone. */
    fun length(): Long? = runCatching {
        if (uri != null) {
            context.contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize }
        } else {
            file?.takeIf { it.exists() }?.length()
        }
    }.getOrNull()

    /** What [saved] needs to find this file again after a restart. */
    fun toJson(): JSONObject = JSONObject()
        .put("uri", uri?.toString())
        .put("path", file?.path)
        .put("mimeType", mimeType)

    companion object {
        /** A file described by [toJson]. */
        fun saved(context: Context, json: JSONObject): DownloadTarget? {
            val uri = json.optString("uri").takeIf { it.isNotEmpty() }?.let(Uri::parse)
            val file = json.optString("path").takeIf { it.isNotEmpty() }?.let(::File)
            if (uri == null && file == null) return null

            return DownloadTarget(context, uri, file, json.optString("mimeType", "application/octet-stream"))
        }

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
