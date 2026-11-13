package com.toneflix.flyylink.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.toneflix.flyylink.protocol.DeviceType

/** A drawn laptop: dark lid with a light screen, on a wider base. */
@Composable
fun LaptopArt(width: Dp, modifier: Modifier = Modifier, content: @Composable () -> Unit = {}) {
    val colors = FlyyLink.colors

    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(width, width * 0.63f)
                .background(colors.deviceBody, RoundedCornerShape(width * 0.06f))
                .padding(width * 0.028f),
        ) {
            Box(Modifier.fillMaxSize().background(colors.deviceScreen, RoundedCornerShape(width * 0.035f))) { content() }
        }
        Box(
            Modifier
                .size(width * 1.17f, width * 0.055f)
                .background(colors.deviceBase, RoundedCornerShape(bottomStart = width * 0.05f, bottomEnd = width * 0.05f)),
        )
    }
}

/** A drawn phone: dark body with a light screen, in the same style as [LaptopArt]. */
@Composable
fun PhoneArt(height: Dp, modifier: Modifier = Modifier) {
    val colors = FlyyLink.colors

    Box(
        modifier
            .size(height * 0.5f, height)
            .background(colors.deviceBody, RoundedCornerShape(height * 0.1f))
            .padding(height * 0.035f),
    ) {
        Box(Modifier.fillMaxSize().background(colors.deviceScreen, RoundedCornerShape(height * 0.075f)))
    }
}

/** A phone or a laptop, drawn about [width] wide, to stand for any device. */
@Composable
fun DeviceArt(type: DeviceType, width: Dp, modifier: Modifier = Modifier) {
    if (type.isPhone) PhoneArt(width * 0.75f, modifier) else LaptopArt(width, modifier)
}

/** The pairing code as big separate characters, split in two halves. */
@Composable
fun CodeDigits(code: String, modifier: Modifier = Modifier) {
    val characters = code.filterNot { it.isWhitespace() }
    val half = (characters.length + 1) / 2

    Row(
        modifier.semantics { contentDescription = "Verification code $code" },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        characters.forEachIndexed { index, character ->
            if (index == half) Spacer(Modifier.width(6.dp))
            Box(
                Modifier
                    .size(34.dp, 50.dp)
                    .background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    character.toString(),
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 24.sp,
                )
            }
        }
    }
}
