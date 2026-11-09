package com.toneflix.aproid

import android.content.Context
import org.json.JSONObject

/** Files partly received from a Mac, kept on disk so they can still resume after the app restarts. */
class PartialDownloads(private val context: Context) {
    data class Entry(
        val target: DownloadTarget,
        val deviceId: String,
        val deviceName: String,
        val title: String,
        val total: Long,
        val expires: Long,
    )

    private val prefs = context.getSharedPreferences("partial_downloads", Context.MODE_PRIVATE)

    fun all(): Map<String, Entry> = prefs.all.mapNotNull { (id, value) ->
        val json = (value as? String)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return@mapNotNull null
        val target = DownloadTarget.saved(context, json.getJSONObject("target")) ?: return@mapNotNull null

        id to Entry(
            target,
            json.getString("deviceId"),
            json.getString("deviceName"),
            json.getString("title"),
            json.getLong("total"),
            json.getLong("expires"),
        )
    }.toMap()

    operator fun get(id: String): Entry? = all()[id]

    fun put(id: String, entry: Entry) {
        val json = JSONObject()
            .put("target", entry.target.toJson())
            .put("deviceId", entry.deviceId)
            .put("deviceName", entry.deviceName)
            .put("title", entry.title)
            .put("total", entry.total)
            .put("expires", entry.expires)

        prefs.edit().putString(id, json.toString()).apply()
    }

    fun remove(id: String) = prefs.edit().remove(id).apply()

    /** Forgets the files that waited too long and deletes what arrived of them. */
    fun removeExpired(now: Long = System.currentTimeMillis()) {
        all().filterValues { it.expires <= now }.forEach { (id, entry) ->
            entry.target.discard()
            remove(id)
        }
    }

    companion object {
        /** How long a partial file waits for the Mac to come back. */
        const val KEEP_MS = 24 * 60 * 60 * 1000L
    }
}
