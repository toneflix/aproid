package com.toneflix.aproid

import androidx.annotation.DrawableRes
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.format.Formatter
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.toneflix.aproid.protocol.PairState
import com.toneflix.aproid.protocol.TransferProgress
import com.toneflix.aproid.ui.AproidTheme
import com.toneflix.aproid.ui.LaptopArt
import kotlinx.coroutines.delay

/** The share sheet target: sends files, links or text from any app to a paired Mac. */
class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val outgoing = outgoing(intent)
        if (outgoing == null) {
            finish()
            return
        }

        // Shared from another app while Aproid wasn't running: connect now.
        LinkService.start(this)

        setContent {
            AproidTheme { ShareSheet(outgoing, onClose = ::finish) }
        }
    }

    private fun outgoing(intent: Intent): Outgoing? {
        val uris = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(intent.stream())
            Intent.ACTION_SEND_MULTIPLE -> intent.streams()
            else -> return null
        }

        if (uris.isNotEmpty()) {
            val items = ShareSender.describe(this, uris)
            return if (items.isEmpty()) null else Outgoing.Files(items)
        }

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        return if (text.isNullOrEmpty()) null else Outgoing.Text(text)
    }

    @Suppress("DEPRECATION")
    private fun Intent.stream(): Uri? =
        if (Build.VERSION.SDK_INT >= 33) getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) else getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun Intent.streams(): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) else getParcelableArrayListExtra(Intent.EXTRA_STREAM))
            .orEmpty()

    companion object {
        /** Opens the sheet to send files picked inside Aproid. */
        fun sendFilesIntent(context: Context, uris: List<Uri>): Intent =
            Intent(context, ShareActivity::class.java)
                .setAction(Intent.ACTION_SEND_MULTIPLE)
                .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}

sealed interface Outgoing {
    data class Files(val items: List<ShareSender.Item>) : Outgoing {
        val totalSize: Long get() = items.sumOf { it.size }
        val allImages: Boolean get() = items.all { it.name.substringAfterLast('.').lowercase() in IMAGE_EXTENSIONS }
    }

    data class Text(val text: String) : Outgoing

    companion object {
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif")
    }
}

/** How far a send to one Mac has got. */
data class SendProgress(val reading: TransferProgress.Snapshot, val done: Boolean = false, val failed: Boolean = false) {
    val fraction: Float get() = reading.fraction.toFloat()

    companion object {
        fun finished(total: Long, failed: Boolean = false) =
            SendProgress(TransferProgress.Snapshot(total, total, null, null), done = true, failed = failed)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShareSheet(outgoing: Outgoing, onClose: () -> Unit) {
    val context = LocalContext.current
    val devices by DeviceStore.states.collectAsStateWithLifecycle()
    val macs = devices.filter { it.pairState == PairState.PAIRED }
    val progress = remember { mutableStateMapOf<String, SendProgress>() }
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val send = { mac: DeviceState ->
        if (mac.id !in progress) {
            when (outgoing) {
                is Outgoing.Files -> startSending(context, mac, outgoing, progress)
                is Outgoing.Text -> {
                    ShareSender.sendText(context, mac.id, outgoing.text)
                    progress[mac.id] = SendProgress.finished(1)
                }
            }
        }
    }

    // With one Mac there is nothing to choose, so start right away.
    LaunchedEffect(macs.size) {
        if (macs.size == 1 && progress.isEmpty()) send(macs.first())
    }

    // Close shortly after everything finished.
    val allDone = progress.isNotEmpty() && progress.values.all { it.done }
    LaunchedEffect(allDone) {
        if (!allDone) return@LaunchedEffect

        val failed = progress.values.any { it.failed }
        Toast.makeText(context, if (failed) R.string.share_send_failed_toast else R.string.share_sent_toast, Toast.LENGTH_SHORT).show()
        delay(900)
        onClose()
    }

    ModalBottomSheet(onDismissRequest = onClose, sheetState = state, containerColor = MaterialTheme.colorScheme.surface) {
        Column(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(start = 20.dp, end = 20.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Summary(outgoing)

            Text(stringResource(R.string.share_send_to), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)

            if (macs.isEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text(stringResource(R.string.share_looking), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            macs.forEach { mac -> MacRow(mac, progress[mac.id], outgoing) { send(mac) } }

            OutlinedButton(
                onClick = onClose,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
            ) {
                val label = if (progress.values.any { !it.done }) R.string.share_hide else R.string.cancel
                Text(stringResource(label), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

private fun startSending(context: Context, mac: DeviceState, files: Outgoing.Files, progress: MutableMap<String, SendProgress>) {
    val main = Handler(Looper.getMainLooper())

    progress[mac.id] = SendProgress(TransferProgress.Snapshot(0, files.totalSize, null, null))

    ShareSender.sendFiles(
        context,
        mac.id,
        files.items,
        onProgress = { reading -> main.post { progress[mac.id] = SendProgress(reading) } },
        onDone = { error -> main.post { progress[mac.id] = SendProgress.finished(files.totalSize, failed = error != null) } },
    )
}

@Composable
private fun Summary(outgoing: Outgoing) {
    val context = LocalContext.current
    val (icon, title, subtitle) = when (outgoing) {
        is Outgoing.Files -> Triple(
            if (outgoing.allImages) R.drawable.lucide_image else R.drawable.lucide_file_text,
            when {
                outgoing.items.size == 1 -> outgoing.items.first().name
                outgoing.allImages -> pluralStringResource(R.plurals.share_photos, outgoing.items.size, outgoing.items.size)
                else -> pluralStringResource(R.plurals.share_files, outgoing.items.size, outgoing.items.size)
            },
            Formatter.formatShortFileSize(context, outgoing.totalSize),
        )
        is Outgoing.Text -> Triple(R.drawable.lucide_link, outgoing.text.lineSequence().first(), stringResource(R.string.share_text_summary))
    }

    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(52.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(14.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(painterResource(icon), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun MacRow(mac: DeviceState, progress: SendProgress?, outgoing: Outgoing, onClick: () -> Unit) {
    val active = progress != null
    val shape = RoundedCornerShape(22.dp)

    Row(
        Modifier
            .fillMaxWidth()
            .background(if (active) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerLow, shape)
            .then(if (active) Modifier.border(2.dp, MaterialTheme.colorScheme.primary, shape) else Modifier)
            .clickable(enabled = !active, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LaptopArt(44.dp)

        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(mac.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                when {
                    progress == null -> Unit
                    progress.failed -> StatusIcon(R.drawable.lucide_circle_alert, MaterialTheme.colorScheme.error)
                    progress.done -> StatusIcon(R.drawable.lucide_circle_check, MaterialTheme.colorScheme.primary)
                    else -> Text("${(progress.fraction * 100).toInt()}%", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onPrimaryContainer)
                }
            }

            if (progress != null && !progress.done) {
                LinearProgressIndicator(
                    progress = { progress.fraction },
                    modifier = Modifier.fillMaxWidth().height(6.dp),
                    trackColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f),
                )
                if (outgoing is Outgoing.Files) Text(progressDetail(progress, outgoing), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else if (progress == null) {
                Text(stringResource(R.string.share_tap_to_send), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun StatusIcon(@DrawableRes icon: Int, tint: androidx.compose.ui.graphics.Color) {
    Icon(painterResource(icon), contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
}

/** "2 of 3 · 41 MB/s · about 1 second left" */
@Composable
private fun progressDetail(progress: SendProgress, files: Outgoing.Files): String {
    val context = LocalContext.current
    val parts = mutableListOf<String>()

    if (files.items.size > 1) {
        var total = 0L
        val current = files.items.indexOfFirst { total += it.size; progress.reading.done < total }.let { if (it < 0) files.items.size else it + 1 }
        parts += stringResource(R.string.share_n_of_m, current, files.items.size)
    }

    parts += TransferText.speedAndTimeLeft(context, progress.reading)

    return parts.joinToString(" · ").ifEmpty { stringResource(R.string.share_starting) }
}
