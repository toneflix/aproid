package com.toneflix.aproid.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.toneflix.aproid.R
import kotlinx.coroutines.delay

/** Size of the mark on the system splash screen, so the hand-off to this one doesn't jump. */
private val MarkSize = 111.dp

/**
 * The Toneflix launch screen: the logo on a gold glow with the spaced wordmark beneath.
 * It picks up where the system splash leaves off, then fades into the app once per launch.
 */
@Composable
fun SplashOverlay() {
    var visible by rememberSaveable { mutableStateOf(true) }
    var wordmark by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        wordmark = true
        delay(900)
        visible = false
    }

    AnimatedVisibility(visible, enter = fadeIn(tween(0)), exit = fadeOut(tween(350))) {
        Box(Modifier.fillMaxSize().background(Toneflix.goldGlow), contentAlignment = Alignment.Center) {
            Image(painterResource(R.drawable.ic_aproid_logo), contentDescription = null, modifier = Modifier.size(MarkSize))

            AnimatedVisibility(wordmark, Modifier.offset(y = MarkSize / 2 + 34.dp), enter = fadeIn(tween(400))) {
                Text("APROID", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Medium, letterSpacing = 9.sp)
            }
        }
    }
}
