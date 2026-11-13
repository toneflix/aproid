package com.toneflix.flyylink.protocol

/**
 * Picks the device that single-device features (the main screen, messages, photos, call audio) are about
 * while several paired devices stay connected at once. Mirrors DeviceFocus.swift.
 */
class DeviceFocus(private val preferredId: String?) {
    /** The preferred device when it is among [devices], otherwise the first by name, then id. */
    fun <T> pick(devices: List<T>, id: (T) -> String, name: (T) -> String): T? {
        val preferred = devices.firstOrNull { id(it) == preferredId }
        if (preferred != null) return preferred

        return devices.minWithOrNull(order(id, name))
    }

    /** The device after the preferred one, by name then id, wrapping round to the first. */
    fun <T> next(devices: List<T>, id: (T) -> String, name: (T) -> String): T? {
        val ordered = devices.sortedWith(order(id, name))
        val index = ordered.indexOfFirst { id(it) == preferredId }

        return ordered.getOrNull((index + 1) % ordered.size.coerceAtLeast(1))
    }

    private fun <T> order(id: (T) -> String, name: (T) -> String) = compareBy<T>({ name(it) }, { id(it) })
}
