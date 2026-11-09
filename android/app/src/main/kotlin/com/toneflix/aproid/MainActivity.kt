package com.toneflix.aproid

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.toneflix.aproid.ui.AproidTheme
import com.toneflix.aproid.ui.HomeScreen
import com.toneflix.aproid.ui.SplashOverlay

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }

        // Opening the app is enough to connect; there is no separate Start button any more.
        LinkService.start(this)

        val me = DeviceStore.identity(this)

        setContent {
            AproidTheme {
                Box {
                    HomeScreen(phoneName = me.deviceName)
                    SplashOverlay()
                }
            }
        }
    }

    companion object {
        /** Brings the app to the front, or opens it, when a notification is tapped. */
        fun pendingIntent(context: Context): PendingIntent {
            val open = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)

            return PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
    }
}
