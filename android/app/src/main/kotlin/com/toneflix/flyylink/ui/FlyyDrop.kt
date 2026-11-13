package com.toneflix.flyylink.ui

import android.text.format.DateUtils
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.toneflix.flyylink.FlyyDropPlugin
import com.toneflix.flyylink.R
import com.toneflix.flyylink.protocol.DeviceType
import com.toneflix.flyylink.protocol.FlyyDrop
import kotlinx.coroutines.delay

/** Slides up when someone nearby wants to FlyyDrop, with what they are sending and Accept or Decline. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlyyDropSheet() {
    val asks by FlyyDropPlugin.asks.collectAsStateWithLifecycle()
    val ask = asks.firstOrNull() ?: return
    val context = LocalContext.current
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val offer = ask.offer

    ModalBottomSheet(
        onDismissRequest = { FlyyDropPlugin.decline(offer.id) },
        sheetState = state,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Radar(size = 168.dp) { DeviceArt(ask.deviceType, 64.dp) }

            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    stringResource(R.string.flyydrop_ask_title, ask.deviceName),
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.5).sp,
                    textAlign = TextAlign.Center,
                )
                if (!ask.isPaired) {
                    Text(
                        stringResource(R.string.status_not_paired),
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            OfferCard(offer, FlyyDropPlugin.summary(context, offer))

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = { FlyyDropPlugin.decline(offer.id) },
                    modifier = Modifier.weight(1f).height(56.dp),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                ) {
                    Text(stringResource(R.string.flyydrop_decline), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                }
                Button(
                    onClick = { FlyyDropPlugin.accept(offer.id) },
                    modifier = Modifier.weight(1f).height(56.dp),
                ) { Text(stringResource(R.string.flyydrop_accept), fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}

/** What the request holds: an icon, the first file or link, and how much there is. */
@Composable
private fun OfferCard(offer: FlyyDrop.Offer, summary: String) {
    val images = offer.items.isNotEmpty() && offer.items.all { it.name.substringAfterLast('.').lowercase() in setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif") }
    val icon = when {
        offer.items.isEmpty() -> R.drawable.lucide_link
        images -> R.drawable.lucide_image
        else -> R.drawable.lucide_file_text
    }
    val detail = when {
        offer.items.size > 1 -> offer.items.take(3).joinToString(", ") { it.safeName }
        offer.items.isEmpty() -> stringResource(R.string.share_text_summary)
        else -> null
    }

    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLow, RoundedCornerShape(20.dp))
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(48.dp).background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(14.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(painterResource(icon), contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
        Column(Modifier.weight(1f)) {
            Text(summary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

/** Rings that pulse out from [content], like a device being found nearby. */
@Composable
fun Radar(size: Dp, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val transition = rememberInfiniteTransition(label = "radar")
    val accent = MaterialTheme.colorScheme.primary

    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        repeat(3) { ring ->
            val progress by transition.animateFloat(
                initialValue = 0f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(tween(2400, delayMillis = ring * 800), RepeatMode.Restart),
                label = "ring$ring",
            )
            Box(
                Modifier
                    .size(size * 0.5f)
                    .scale(1f + progress)
                    .alpha(1f - progress)
                    .border(1.5.dp, accent.copy(alpha = 0.5f), CircleShape),
            )
        }
        Box(
            Modifier.size(size * 0.5f).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) { content() }
    }
}

/** The FlyyDrop card on the home screen: who may send this phone files without pairing. */
@Composable
fun FlyyDropCard() {
    val context = LocalContext.current
    val receiving by FlyyDropPlugin.receiving.collectAsStateWithLifecycle()
    val until by FlyyDropPlugin.receivingUntil.collectAsStateWithLifecycle()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(until) {
        while (until != null) {
            now = System.currentTimeMillis()
            delay(DateUtils.SECOND_IN_MILLIS * 15)
        }
    }

    val hint = when (receiving) {
        FlyyDrop.Receiving.OFF, FlyyDrop.Receiving.EVERYONE -> null
        FlyyDrop.Receiving.EVERYONE_FOR_10_MINUTES -> {
            val minutes = (((until ?: now) - now + 59_999) / 60_000).toInt().coerceAtLeast(1)
            pluralStringResource(R.plurals.flyydrop_minutes_left, minutes, minutes)
        }
    }

    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, MaterialTheme.shapes.medium)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(painterResource(R.drawable.lucide_radar), contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(20.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.flyydrop_receiving_title), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                hint?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }

        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(14.dp))
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            FlyyDrop.Receiving.entries.forEach { mode ->
                val label = when (mode) {
                    FlyyDrop.Receiving.OFF -> R.string.flyydrop_off
                    FlyyDrop.Receiving.EVERYONE_FOR_10_MINUTES -> R.string.flyydrop_ten_minutes
                    FlyyDrop.Receiving.EVERYONE -> R.string.flyydrop_everyone
                }
                val selected = mode == receiving
                val background by animateColorAsState(
                    if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh,
                    label = "segment",
                )
                val foreground by animateColorAsState(
                    if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    label = "segmentText",
                )

                Box(
                    Modifier
                        .weight(1f)
                        .height(38.dp)
                        .background(background, RoundedCornerShape(11.dp))
                        .clickable { FlyyDropPlugin.setReceiving(context, mode) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(stringResource(label), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = foreground, maxLines = 1)
                }
            }
        }
    }
}

/** A device's art in a soft circle, for lists of nearby devices. */
@Composable
fun DeviceBadge(type: DeviceType, modifier: Modifier = Modifier) {
    Box(
        modifier.size(48.dp).background(MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        DeviceArt(type, 30.dp)
    }
}
