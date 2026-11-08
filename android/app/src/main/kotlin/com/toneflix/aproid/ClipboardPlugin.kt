package com.toneflix.aproid

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.toneflix.aproid.protocol.Clipboard
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.Plugin

/**
 * Puts text copied on the Mac on the phone's clipboard. Android only lets an app read the
 * clipboard while it is in front, so sending the other way goes through [ClipboardActivity].
 */
object ClipboardPlugin : Plugin {
    override val incoming = setOf(PacketType.CLIPBOARD, PacketType.CLIPBOARD_CONNECT)

    private var context: Context? = null
    private val main = Handler(Looper.getMainLooper())

    fun start(context: Context) {
        this.context = context.applicationContext
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return
        val content = Clipboard.content(packet) ?: return

        main.post {
            val clipboard = context.getSystemService(ClipboardManager::class.java)
            clipboard.setPrimaryClip(ClipData.newPlainText(device.name, content))
        }
    }

    /** Sends the phone's clipboard text to every paired Mac. Call while an activity has focus. */
    fun send(context: Context): Boolean {
        val clip = context.getSystemService(ClipboardManager::class.java).primaryClip ?: return false
        val text = clip.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
        if (text.isNullOrEmpty()) return false

        DeviceStore.sendToPaired(Clipboard.packet(text))

        return true
    }
}
