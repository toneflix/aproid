package com.toneflix.aproid.protocol

/**
 * Picks the device that single-device features (the main screen, messages, photos, call audio) are about
 * while several paired devices stay connected at once. Mirrors DeviceFocus.swift.
 */
class DeviceFocus(private val preferredId: String?) {
    /** The preferred device when it is among [devices], otherwise the first by name, then id. */
    fun <T> pick(devices: List<T>, id: (T) -> String, name: (T) -> String): T? {
        val preferred = devices.firstOrNull { id(it) == preferredId }
        if (preferred != null) return preferred

        return devices.minWithOrNull(compareBy<T>({ name(it) }, { id(it) }))
    }
}
