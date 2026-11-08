package com.toneflix.aproid.ui

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.text.format.DateUtils
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BatteryChargingFull
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.toneflix.aproid.DeviceState
import com.toneflix.aproid.DeviceStore
import com.toneflix.aproid.ClipboardPlugin
import com.toneflix.aproid.LinkService
import com.toneflix.aproid.NotificationPlugin
import com.toneflix.aproid.R
import com.toneflix.aproid.Recent
import com.toneflix.aproid.RecentItem
import com.toneflix.aproid.ShareActivity
import com.toneflix.aproid.openIntent
import com.toneflix.aproid.protocol.PairState
import kotlin.concurrent.thread

/** Runs a device action off the main thread, since it writes to the network. */
fun withDevice(id: String, action: (com.toneflix.aproid.protocol.Device) -> Unit) {
    thread(isDaemon = true) { DeviceStore.find(id)?.let(action) }
}

@Composable
fun HomeScreen(phoneName: String) {
    val devices by DeviceStore.states.collectAsStateWithLifecycle()
    val recent by Recent.items.collectAsStateWithLifecycle()
    val mac = devices.firstOrNull { it.pairState == PairState.PAIRED }
    val others = devices.filter { it.id != mac?.id }

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp)
                .animateContentSize(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Header(mac)

            if (mac != null) {
                ConnectedHero(mac)
                QuickTiles(mac)
            } else {
                SearchingHero(hasNearby = others.isNotEmpty())
            }

            SetupCards()

            if (others.isNotEmpty()) Nearby(others)

            if (recent.isNotEmpty()) RecentSection(recent)

            Text(
                stringResource(R.string.home_this_phone, phoneName),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }

        PairSheet()
    }
}

@Composable
private fun Header(mac: DeviceState?) {
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }

    Row(Modifier.padding(top = 18.dp, start = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Aproid", fontSize = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.6).sp, modifier = Modifier.weight(1f))
        Box {
            IconButton(onClick = { menu = true }) {
                Icon(Icons.Outlined.Settings, contentDescription = stringResource(R.string.home_settings), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.home_notification_access)) },
                    onClick = {
                        menu = false
                        context.startActivity(NotificationPlugin.accessSettingsIntent())
                    },
                )
                if (mac != null) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.home_unpair, mac.name)) },
                        onClick = {
                            menu = false
                            withDevice(mac.id) { it.unpair() }
                        },
                    )
                }
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.home_stop)) },
                    onClick = {
                        menu = false
                        LinkService.stop(context)
                    },
                )
            }
        }
    }
}

@Composable
private fun ConnectedHero(mac: DeviceState) {
    val colors = Aproid.colors

    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.hero, MaterialTheme.shapes.large)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Pill {
                Box(Modifier.size(8.dp).background(colors.ok, CircleShape))
                Text(stringResource(R.string.home_connected), color = colors.onHero, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.home_wifi), color = colors.onHero.copy(alpha = 0.8f), fontSize = 13.sp)
        }

        LaptopArt(180.dp, Modifier.align(Alignment.CenterHorizontally).padding(vertical = 4.dp)) {
            // The Aproid menu, open on the Mac's screen.
            Box(Modifier.fillMaxSize().padding(8.dp), contentAlignment = Alignment.TopEnd) {
                Box(Modifier.size(54.dp, 22.dp).background(Color.White, RoundedCornerShape(6.dp)))
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(mac.name, color = colors.onHero, fontSize = 24.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp)
            Text(stringResource(R.string.home_flowing), color = colors.onHero.copy(alpha = 0.82f), fontSize = 14.sp)
        }
    }
}

@Composable
private fun Pill(content: @Composable () -> Unit) {
    Row(
        Modifier
            .background(Color.White.copy(alpha = 0.16f), CircleShape)
            .padding(start = 10.dp, end = 12.dp, top = 6.dp, bottom = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

@Composable
private fun SearchingHero(hasNearby: Boolean) {
    val pulse = rememberInfiniteTransition(label = "pulse")
    val wave by pulse.animateFloat(0f, 1f, infiniteRepeatable(tween(2000), RepeatMode.Restart), label = "wave")

    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, MaterialTheme.shapes.large)
            .padding(vertical = 30.dp, horizontal = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Box(Modifier.size(170.dp, 120.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size(110.dp)
                    .scale(1f + wave * 0.6f)
                    .alpha(1f - wave)
                    .background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
            )
            LaptopArt(120.dp)
        }
        Text(
            stringResource(if (hasNearby) R.string.home_pick_mac else R.string.home_looking),
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            stringResource(if (hasNearby) R.string.home_pick_mac_hint else R.string.home_looking_hint),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun QuickTiles(mac: DeviceState) {
    val context = LocalContext.current
    var linkDialog by remember { mutableStateOf(false) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        if (uris.isNotEmpty()) context.startActivity(ShareActivity.sendFilesIntent(context, uris))
    }

    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Tile(Icons.Outlined.UploadFile, stringResource(R.string.home_send_files), Modifier.weight(1f)) { pick.launch("*/*") }
        Tile(Icons.Outlined.ContentPaste, stringResource(R.string.home_clipboard), Modifier.weight(1f)) {
            val sent = ClipboardPlugin.send(context)
            val message = if (sent) R.string.clipboard_sent else R.string.clipboard_empty
            Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
        }
        Tile(Icons.Outlined.Link, stringResource(R.string.home_open_link), Modifier.weight(1f)) { linkDialog = true }
    }

    if (linkDialog) {
        LinkDialog(mac, initial = clipboardText(context), onDismiss = { linkDialog = false })
    }
}

@Composable
private fun Tile(icon: ImageVector, label: String, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier
            .background(MaterialTheme.colorScheme.surface, MaterialTheme.shapes.medium)
            .clickable(onClick = onClick)
            .padding(vertical = 16.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier.size(48.dp).background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(16.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** Amber cards for the permissions Aproid still needs. Each disappears once granted. */
@Composable
private fun SetupCards() {
    val context = LocalContext.current
    var notifications by remember { mutableStateOf(NotificationPlugin.hasAccess(context)) }
    var background by remember { mutableStateOf(LinkService.isUnrestricted(context)) }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        notifications = NotificationPlugin.hasAccess(context)
        background = LinkService.isUnrestricted(context)
    }

    AnimatedVisibility(!notifications) {
        SetupCard(
            Icons.Outlined.Notifications,
            stringResource(R.string.setup_notifications),
            stringResource(R.string.setup_notifications_hint),
        ) { context.startActivity(NotificationPlugin.accessSettingsIntent()) }
    }
    AnimatedVisibility(!background) {
        SetupCard(
            Icons.Outlined.BatteryChargingFull,
            stringResource(R.string.setup_background),
            stringResource(R.string.setup_background_hint),
        ) { context.startActivity(LinkService.unrestrictIntent(context)) }
    }
}

@Composable
private fun SetupCard(icon: ImageVector, title: String, hint: String, onAllow: () -> Unit) {
    val colors = Aproid.colors

    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.setup, MaterialTheme.shapes.medium)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(40.dp).background(colors.setupChip, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = colors.onSetup, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.onSetup, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(hint, color = colors.onSetupVariant, fontSize = 12.sp)
        }
        Button(
            onClick = onAllow,
            colors = ButtonDefaults.buttonColors(containerColor = colors.onSetup, contentColor = colors.setup),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
            modifier = Modifier.height(40.dp),
        ) { Text(stringResource(R.string.setup_allow), fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }
    }
}

@Composable
private fun Nearby(devices: List<DeviceState>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle(stringResource(R.string.home_nearby))

        devices.forEach { device ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface, MaterialTheme.shapes.medium)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LaptopArt(44.dp)
                Column(Modifier.weight(1f)) {
                    Text(device.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(nearbyStatus(device), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                when (device.pairState) {
                    PairState.NOT_PAIRED -> TextButton(onClick = { withDevice(device.id) { it.requestPair() } }) {
                        Text(stringResource(R.string.pair), fontWeight = FontWeight.SemiBold)
                    }
                    PairState.REQUESTED -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else -> Unit
                }
            }
            if (device.pairState == PairState.REQUESTED && device.code != null) {
                Column(
                    Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(stringResource(R.string.pair_check_mac), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    CodeDigits(device.code)
                }
            }
        }
    }
}

@Composable
private fun nearbyStatus(device: DeviceState): String = when (device.pairState) {
    PairState.NOT_PAIRED -> stringResource(R.string.status_not_paired)
    PairState.REQUESTED -> stringResource(R.string.status_waiting)
    PairState.REQUESTED_BY_PEER -> stringResource(R.string.status_wants_pair)
    PairState.PAIRED -> stringResource(R.string.status_paired)
}

@Composable
private fun RecentSection(items: List<RecentItem>) {
    val context = LocalContext.current

    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionTitle(stringResource(R.string.home_recent), Modifier.weight(1f))
            TextButton(onClick = { Recent.clear() }) { Text(stringResource(R.string.home_clear)) }
        }

        Surface(color = MaterialTheme.colorScheme.surface, shape = MaterialTheme.shapes.medium) {
            Column {
                items.take(6).forEachIndexed { index, item ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 74.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    RecentRow(item) {
                        item.openIntent()?.let { runCatching { context.startActivity(it) } }
                    }
                }
            }
        }
    }
}

@Composable
private fun RecentRow(item: RecentItem, onOpen: () -> Unit) {
    val failed = item.kind == RecentItem.Kind.FAILED

    Row(
        Modifier
            .fillMaxWidth()
            .clickable(enabled = item.uri != null, onClick = onOpen)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(44.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(14.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                recentIcon(item),
                contentDescription = null,
                tint = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        }
        Column(Modifier.weight(1f)) {
            Text(item.title, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(item.detail, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (item.inProgress) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        } else {
            Text(
                DateUtils.getRelativeTimeSpanString(item.time, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS, DateUtils.FORMAT_ABBREV_RELATIVE).toString(),
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun recentIcon(item: RecentItem): ImageVector = when {
    item.kind == RecentItem.Kind.FAILED -> Icons.Outlined.ErrorOutline
    item.kind == RecentItem.Kind.LINK -> Icons.Outlined.Link
    item.kind == RecentItem.Kind.TEXT -> Icons.Outlined.ContentPaste
    item.mimeType?.startsWith("image/") == true -> Icons.Outlined.Image
    else -> Icons.Outlined.Description
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier.padding(horizontal = 4.dp),
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

private fun clipboardText(context: Context): String {
    val clip = context.getSystemService(ClipboardManager::class.java).primaryClip ?: return ""
    val text = clip.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty().trim()

    return if (Uri.parse(text).scheme?.lowercase() in setOf("http", "https")) text else ""
}
