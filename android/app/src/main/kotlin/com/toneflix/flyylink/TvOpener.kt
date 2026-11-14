package com.toneflix.flyylink

import android.content.Context
import android.content.Intent

/** Opens what arrives on a TV right away, or pops up where to find it when Android won't allow that. */
class TvOpener(context: Context) {
    private val context = context.applicationContext
    private val popup = TvPopup.of(context)

    fun open(intent: Intent?, label: String, title: String) {
        val allowed = MainActivity.isVisible || TvSettings.canShowOverApps(context)

        if (intent == null || !allowed) {
            popup.show(label, title, context.getString(R.string.tv_open_flyylink))
            return
        }

        if (runCatching { context.startActivity(intent) }.isFailure) {
            popup.show(label, title, context.getString(R.string.tv_no_app))
        }
    }

    fun say(label: String, title: String, text: String) = popup.show(label, title, text)
}
