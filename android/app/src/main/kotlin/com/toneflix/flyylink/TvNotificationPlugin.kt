package com.toneflix.flyylink

import android.content.Context
import com.toneflix.flyylink.protocol.Device
import com.toneflix.flyylink.protocol.NetworkPacket
import com.toneflix.flyylink.protocol.PacketType
import com.toneflix.flyylink.protocol.PhoneNotification
import com.toneflix.flyylink.protocol.Plugin

/** Pops up a phone's new notifications on the TV, unless the user turned that off. */
object TvNotificationPlugin : Plugin {
    override val incoming = setOf(PacketType.NOTIFICATION)

    private var popup: TvPopup? = null

    fun start(context: Context) {
        TvSettings.restore(context)
        popup = TvPopup.of(context)
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val note = PhoneNotification.fromPacket(packet) ?: return
        if (note.silent || !TvSettings.popups.value) return
        if (note.title.isBlank() && note.text.isBlank()) return

        popup?.show("${note.appName} · ${device.name}", note.title, note.text)
    }
}
