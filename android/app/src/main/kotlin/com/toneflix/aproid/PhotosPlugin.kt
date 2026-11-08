package com.toneflix.aproid

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.PhonePhoto
import com.toneflix.aproid.protocol.Photos
import com.toneflix.aproid.protocol.Plugin
import java.util.concurrent.Executors

/** Lets the Mac browse the phone's gallery, newest first, and download photos and videos in full. */
object PhotosPlugin : Plugin {
    override val incoming = setOf(PacketType.PHOTOS_REQUEST, PacketType.PHOTOS_DOWNLOAD)

    private const val THUMBNAIL_SIZE = 240

    private var context: Context? = null

    /** Thumbnails take a moment each, so pages are built off the link's thread. */
    private val worker = Executors.newSingleThreadExecutor()

    private val gallery: Uri = MediaStore.Files.getContentUri("external")

    val permissions: Array<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    fun hasPermission(context: Context) =
        permissions.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    fun start(context: Context) {
        this.context = context.applicationContext
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return
        if (!hasPermission(context)) return

        Photos.request(packet)?.let { request ->
            worker.execute { DeviceStore.send(device, page(context, request)) }
        }

        Photos.downloadId(packet)?.let { id ->
            worker.execute { download(context, device, id) }
        }
    }

    /** One page of photos older than [Photos.Request.before], with small thumbnails. */
    private fun page(context: Context, request: Photos.Request): NetworkPacket {
        val columns = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.DATE_ADDED,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.WIDTH,
            MediaStore.Files.FileColumns.HEIGHT,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
        )

        // Paging uses the date it was added, which every item has; the Mac sends the last date it got.
        val media = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?, ?)"
        val selection = if (request.before != null) "$media AND ${MediaStore.Files.FileColumns.DATE_ADDED} < ?" else media
        val args = buildList {
            add(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString())
            add(MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString())
            request.before?.let { add((it / 1000).toString()) }
        }.toTypedArray()
        val order = "${MediaStore.Files.FileColumns.DATE_ADDED} DESC, ${MediaStore.Files.FileColumns._ID} DESC"

        val photos = mutableListOf<PhonePhoto>()
        var more = false

        context.contentResolver.query(gallery, columns, selection, args, order)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (photos.size == request.count) {
                    more = true
                    break
                }

                val id = cursor.getLong(0)
                val isVideo = cursor.getInt(7) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                photos += PhonePhoto(
                    id = id,
                    name = cursor.getString(1) ?: "photo-$id",
                    date = cursor.getLong(2) * 1000,
                    mimeType = cursor.getString(3) ?: if (isVideo) "video/mp4" else "image/jpeg",
                    width = cursor.getInt(4),
                    height = cursor.getInt(5),
                    size = cursor.getLong(6),
                    thumbnail = thumbnail(context, id, isVideo),
                )
            }
        }

        return Photos.pagePacket(photos, more)
    }

    private fun itemUri(id: Long, isVideo: Boolean): Uri = ContentUris.withAppendedId(
        if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
        id,
    )

    private fun thumbnail(context: Context, id: Long, isVideo: Boolean): String? = runCatching {
        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.loadThumbnail(itemUri(id, isVideo), Size(THUMBNAIL_SIZE, THUMBNAIL_SIZE), null)
        } else if (isVideo) {
            @Suppress("DEPRECATION")
            MediaStore.Video.Thumbnails.getThumbnail(context.contentResolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Thumbnails.getThumbnail(context.contentResolver, id, MediaStore.Images.Thumbnails.MINI_KIND, null)
        }

        bitmap?.let { Contacts.encode(it, THUMBNAIL_SIZE) }
    }.getOrNull()

    /** Sends the full photo or video as a normal shared file, so it lands in the Mac's Downloads. */
    private fun download(context: Context, device: Device, id: Long) {
        val isVideo = context.contentResolver.query(
            ContentUris.withAppendedId(gallery, id),
            arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return
            cursor.getInt(0) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
        } ?: return

        val items = ShareSender.describe(context, listOf(itemUri(id, isVideo)))
        if (items.isNotEmpty()) ShareSender.sendFiles(context, device.id, items)
    }
}
