package com.toneflix.aproid

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.ContactsContract
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap

/** Looks up contact names and photos for phone numbers, remembering the answers. */
object Contacts {
    data class Contact(val name: String?, val photo: Uri?)

    private val cache = ConcurrentHashMap<String, Contact>()

    fun lookup(context: Context, number: String): Contact {
        if (number.isBlank()) return Contact(null, null)
        cache[number]?.let { return it }

        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            return Contact(null, null)
        }

        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
        val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME, ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI)
        val contact = runCatching {
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                Contact(cursor.getString(0), cursor.getString(1)?.let(Uri::parse))
            }
        }.getOrNull() ?: Contact(null, null)

        return contact.also { cache[number] = it }
    }

    fun name(context: Context, number: String): String? = lookup(context, number).name

    /** The contact's photo as a small base64 JPEG, for the Mac's call window. */
    fun photoBase64(context: Context, number: String): String? {
        val photo = lookup(context, number).photo ?: return null

        return runCatching {
            context.contentResolver.openInputStream(photo)?.use { BitmapFactory.decodeStream(it) }?.let(::encode)
        }.getOrNull()
    }

    fun encode(bitmap: Bitmap, size: Int = 160): String {
        val scale = minOf(1f, size.toFloat() / maxOf(bitmap.width, bitmap.height))
        val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt().coerceAtLeast(1), (bitmap.height * scale).toInt().coerceAtLeast(1), true) else bitmap
        val bytes = ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()

        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    fun clear() = cache.clear()
}
