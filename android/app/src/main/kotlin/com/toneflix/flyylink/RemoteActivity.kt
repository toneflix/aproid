package com.toneflix.flyylink

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.toneflix.flyylink.protocol.TvRemote
import com.toneflix.flyylink.ui.FlyyLinkTheme
import com.toneflix.flyylink.ui.RemoteScreen

/** The phone as a remote for a paired TV. The phone's volume buttons turn the TV's volume while it is open. */
class RemoteActivity : ComponentActivity() {
    private lateinit var deviceId: String

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        deviceId = intent.getStringExtra(EXTRA_DEVICE) ?: return finish()

        setContent {
            FlyyLinkTheme {
                RemoteScreen(deviceId, onPress = ::press, onClose = ::finish)
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> press(TvRemote.Key(TvRemote.VOLUME_UP))
            KeyEvent.KEYCODE_VOLUME_DOWN -> press(TvRemote.Key(TvRemote.VOLUME_DOWN))
            else -> return super.onKeyDown(keyCode, event)
        }

        return true
    }

    private fun press(press: TvRemote) {
        DeviceStore.find(deviceId)?.let { DeviceStore.send(it, press.toPacket()) }
    }

    companion object {
        private const val EXTRA_DEVICE = "device"

        fun intent(context: Context, deviceId: String): Intent =
            Intent(context, RemoteActivity::class.java).putExtra(EXTRA_DEVICE, deviceId)
    }
}
