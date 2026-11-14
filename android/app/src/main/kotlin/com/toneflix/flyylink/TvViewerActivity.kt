package com.toneflix.flyylink

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.KeyEvent
import android.widget.VideoView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.toneflix.flyylink.ui.FlyyLinkTheme
import com.toneflix.flyylink.ui.TvViewer

/** Shows a photo, or plays a video or song, full screen on the TV. The remote's center button pauses. */
class TvViewerActivity : ComponentActivity() {
    private var player: VideoView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val uri = intent.data ?: return finish()
        val kind = Kind.of(intent.type) ?: return openElsewhere(uri)
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val detail = intent.getStringExtra(EXTRA_DETAIL).orEmpty()

        setContent {
            FlyyLinkTheme(dark = true) {
                TvViewer(
                    kind = kind,
                    title = title,
                    detail = detail,
                    loadPicture = { loadPicture(uri) },
                    onPlayer = { view ->
                        player = view
                        view.setVideoURI(uri)
                        view.setOnPreparedListener { it.start() }
                        view.setOnErrorListener { _, _, _ ->
                            openElsewhere(uri)
                            true
                        }
                    },
                )
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val player = player ?: return super.onKeyDown(keyCode, event)

        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ->
                if (player.isPlaying) player.pause() else player.start()
            KeyEvent.KEYCODE_MEDIA_PLAY -> player.start()
            KeyEvent.KEYCODE_MEDIA_PAUSE -> player.pause()
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> player.seekTo(player.currentPosition + SEEK_MS)
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_MEDIA_REWIND -> player.seekTo((player.currentPosition - SEEK_MS).coerceAtLeast(0))
            else -> return super.onKeyDown(keyCode, event)
        }

        return true
    }

    override fun onStop() {
        player?.pause()
        super.onStop()
    }

    private fun loadPicture(uri: Uri): Bitmap? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { decoder, info, _ ->
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > MAX_PICTURE) decoder.setTargetSampleSize(longest / MAX_PICTURE + 1)
            }
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Media.getBitmap(contentResolver, uri)
        }
    }.getOrNull()

    /** Hands the file to another app when it won't play here. */
    private fun openElsewhere(uri: Uri) {
        startActivity(OpenFileActivity.intent(this, uri, intent.type))
        finish()
    }

    /** What the viewer shows a file as. */
    enum class Kind {
        PICTURE, VIDEO, MUSIC;

        companion object {
            fun of(mimeType: String?): Kind? = when {
                mimeType == null -> null
                mimeType.startsWith("image/") -> PICTURE
                mimeType.startsWith("video/") -> VIDEO
                mimeType.startsWith("audio/") -> MUSIC
                else -> null
            }
        }
    }

    companion object {
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_DETAIL = "detail"
        private const val SEEK_MS = 10_000
        private const val MAX_PICTURE = 3840

        fun intent(context: Context, uri: Uri, mimeType: String?, title: String, detail: String): Intent =
            Intent(context, TvViewerActivity::class.java)
                .setDataAndType(uri, mimeType)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_DETAIL, detail)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}
