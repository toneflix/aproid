package com.toneflix.aproid.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Colors Material doesn't have a slot for. */
@Immutable
data class AproidColors(
    val hero: Color,
    val onHero: Color,
    val ok: Color,
    val deviceBody: Color,
    val deviceScreen: Color,
    val deviceBase: Color,
    val setup: Color,
    val setupChip: Color,
    val onSetup: Color,
    val onSetupVariant: Color,
)

private val Light = lightColorScheme(
    primary = Color(0xFF3346E0),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFECEEFF),
    onPrimaryContainer = Color(0xFF2233B8),
    background = Color(0xFFF7F7FB),
    onBackground = Color(0xFF16161A),
    surface = Color.White,
    onSurface = Color(0xFF16161A),
    surfaceVariant = Color(0xFFEAEAF0),
    onSurfaceVariant = Color(0xFF5A5A64),
    surfaceContainerLow = Color(0xFFF4F4F8),
    outline = Color(0xFFC8C8D2),
    outlineVariant = Color(0xFFD4D4DC),
)

private val Dark = darkColorScheme(
    primary = Color(0xFF8D9BFF),
    onPrimary = Color(0xFF0E1340),
    primaryContainer = Color(0xFF283066),
    onPrimaryContainer = Color(0xFFDDE1FF),
    background = Color(0xFF121216),
    onBackground = Color(0xFFF4F4F6),
    surface = Color(0xFF1E1E23),
    onSurface = Color(0xFFF4F4F6),
    surfaceVariant = Color(0xFF2C2C33),
    onSurfaceVariant = Color(0xFFA3A3AD),
    surfaceContainerLow = Color(0xFF26262C),
    outline = Color(0xFF4A4A54),
    outlineVariant = Color(0xFF3A3A42),
)

private val LightExtra = AproidColors(
    hero = Color(0xFF3346E0),
    onHero = Color.White,
    ok = Color(0xFF7CF0BE),
    deviceBody = Color(0xFF0E1340),
    deviceScreen = Color(0xFFECEEFF),
    deviceBase = Color(0xFFC9CFFF),
    setup = Color(0xFFFFF4E5),
    setupChip = Color(0xFFFFE2B8),
    onSetup = Color(0xFF5C3A00),
    onSetupVariant = Color(0xFF7A5200),
)

private val DarkExtra = AproidColors(
    hero = Color(0xFF2B3BC7),
    onHero = Color.White,
    ok = Color(0xFF7CF0BE),
    deviceBody = Color(0xFF0B0F33),
    deviceScreen = Color(0xFFC9CFFF),
    deviceBase = Color(0xFF8D9BFF),
    setup = Color(0xFF3A2A10),
    setupChip = Color(0xFF5C4115),
    onSetup = Color(0xFFFFE2B8),
    onSetupVariant = Color(0xFFE8C48C),
)

val LocalAproidColors = staticCompositionLocalOf { LightExtra }

object Aproid {
    val colors: AproidColors
        @Composable get() = LocalAproidColors.current
}

@Composable
fun AproidTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()

    androidx.compose.runtime.CompositionLocalProvider(LocalAproidColors provides if (dark) DarkExtra else LightExtra) {
        MaterialTheme(
            colorScheme = if (dark) Dark else Light,
            shapes = Shapes(
                small = RoundedCornerShape(14.dp),
                medium = RoundedCornerShape(22.dp),
                large = RoundedCornerShape(28.dp),
            ),
            content = content,
        )
    }
}
