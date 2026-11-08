package com.toneflix.aproid

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.toneflix.aproid.ui.AproidTheme
import com.toneflix.aproid.ui.HomeScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }

        // Opening the app is enough to connect; there is no separate Start button any more.
        LinkService.start(this)

        val me = DeviceStore.identity(this)

        setContent {
            AproidTheme { HomeScreen(phoneName = me.deviceName) }
        }
    }
}
