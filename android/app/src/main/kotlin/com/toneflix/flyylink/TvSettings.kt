package com.toneflix.flyylink

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** What the user chose on the TV, and the system settings the TV app sends them to. */
object TvSettings {
    private const val PREFS = "flyylink_tv"
    private const val KEY_POPUPS = "popups"

    private val _popups = MutableStateFlow(true)

    /** Whether phone notifications pop up on the TV. */
    val popups: StateFlow<Boolean> = _popups.asStateFlow()

    fun restore(context: Context) {
        _popups.value = prefs(context).getBoolean(KEY_POPUPS, true)
    }

    fun setPopups(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean(KEY_POPUPS, on).apply()
        _popups.value = on
    }

    /** Lets FlyyLink show pop-ups and open what arrives over other apps. */
    fun canShowOverApps(context: Context): Boolean = Settings.canDrawOverlays(context)

    fun overAppsIntent(context: Context): Intent =
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** True when the TV has a settings screen for [intent]; some TVs leave these out. */
    fun canOpen(context: Context, intent: Intent): Boolean = intent.resolveActivity(context.packageManager) != null

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
