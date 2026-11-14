package com.toneflix.flyylink.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** The Toneflix brand colors: the cyan of the logo and the gold of its backgrounds. */
object Toneflix {
    val cyan = Color(0xFF00AFFF)
    val cyanLight = Color(0xFF00EAFF)
    val gold = Color(0xFFF6C101)
    val goldDeep = Color(0xFFBB8C01)

    val goldGradient = Brush.linearGradient(listOf(gold, goldDeep))
    val goldGlow = Brush.radialGradient(listOf(gold, goldDeep))
}

/** Colors Material doesn't have a slot for. */
@Immutable
data class FlyyLinkColors(
    val hero: Brush,
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
    primary = Color(0xFF0086C9),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD9F3FF),
    onPrimaryContainer = Color(0xFF004C70),
    secondary = Color(0xFF8A6700),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFFFEBA8),
    onSecondaryContainer = Color(0xFF2A1E00),
    background = Color(0xFFFFFBF2),
    onBackground = Color(0xFF1B1A16),
    surface = Color.White,
    onSurface = Color(0xFF1B1A16),
    surfaceVariant = Color(0xFFF1ECE0),
    onSurfaceVariant = Color(0xFF5E5A50),
    surfaceContainerLow = Color(0xFFF8F4EA),
    outline = Color(0xFFCFC8B8),
    outlineVariant = Color(0xFFE2DCCD),
)

private val Dark = darkColorScheme(
    primary = Color(0xFF3CC8FF),
    onPrimary = Color(0xFF002A3D),
    primaryContainer = Color(0xFF003B55),
    onPrimaryContainer = Color(0xFFC4EDFF),
    secondary = Color(0xFFF6C101),
    onSecondary = Color(0xFF2A1E00),
    secondaryContainer = Color(0xFF4A3800),
    onSecondaryContainer = Color(0xFFFFE08A),
    background = Color(0xFF13120F),
    onBackground = Color(0xFFF3F0E8),
    surface = Color(0xFF1E1C18),
    onSurface = Color(0xFFF3F0E8),
    surfaceVariant = Color(0xFF2E2B24),
    onSurfaceVariant = Color(0xFFB1AB9C),
    surfaceContainerLow = Color(0xFF26231E),
    outline = Color(0xFF4D493F),
    outlineVariant = Color(0xFF3B3830),
)

private val LightExtra = FlyyLinkColors(
    hero = Toneflix.goldGradient,
    onHero = Color(0xFF2A1E00),
    ok = Color(0xFF0B7A4B),
    deviceBody = Color(0xFF0B1428),
    deviceScreen = Color(0xFFD9F3FF),
    deviceBase = Color(0xFF26355A),
    setup = Color(0xFFE3F6FF),
    setupChip = Color(0xFFC2EBFF),
    onSetup = Color(0xFF00466A),
    onSetupVariant = Color(0xFF2A6585),
)

private val DarkExtra = FlyyLinkColors(
    hero = Toneflix.goldGradient,
    onHero = Color(0xFF2A1E00),
    ok = Color(0xFF0B7A4B),
    deviceBody = Color(0xFF0B1428),
    deviceScreen = Color(0xFFC4EDFF),
    deviceBase = Color(0xFF3A4B75),
    setup = Color(0xFF0F2C3B),
    setupChip = Color(0xFF164259),
    onSetup = Color(0xFFC4EDFF),
    onSetupVariant = Color(0xFF93C9E3),
)

val LocalFlyyLinkColors = staticCompositionLocalOf { LightExtra }

object FlyyLink {
    val colors: FlyyLinkColors
        @Composable get() = LocalFlyyLinkColors.current
}

@Composable
fun FlyyLinkTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalFlyyLinkColors provides if (dark) DarkExtra else LightExtra) {
        MaterialTheme(
            colorScheme = if (dark) Dark else Light,
            shapes = Shapes(
                small = RoundedCornerShape(14.dp),
                medium = RoundedCornerShape(22.dp),
                large = RoundedCornerShape(28.dp),
            ),
        ) {
            CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onBackground, content = content)
        }
    }
}
