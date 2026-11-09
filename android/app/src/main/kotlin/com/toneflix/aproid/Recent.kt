package com.toneflix.aproid

import android.net.Uri
import com.toneflix.aproid.protocol.TransferProgress
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.concurrent.atomic.AtomicLong

/** One line in the home screen's Recent list. */
data class RecentItem(
    val id: Long,
    val kind: Kind,
    val title: String,
    val detail: String,
    val time: Long = System.currentTimeMillis(),
    val uri: Uri? = null,
    val mimeType: String? = null,
    /** How far a file has got while it moves. */
    val progress: TransferProgress.Snapshot? = null,
) {
    enum class Kind { RECEIVING, RECEIVED, SENDING, SENT, LINK, TEXT, FAILED }

    val inProgress: Boolean get() = kind == Kind.RECEIVING || kind == Kind.SENDING
}

/** Files, links and texts that went between this phone and a Mac, newest first. */
object Recent {
    private const val LIMIT = 20

    private val nextId = AtomicLong()
    private val _items = MutableStateFlow<List<RecentItem>>(emptyList())
    val items: StateFlow<List<RecentItem>> = _items.asStateFlow()

    fun add(kind: RecentItem.Kind, title: String, detail: String): RecentItem =
        RecentItem(nextId.incrementAndGet(), kind, title, detail).also(::put)

    /** Adds the item, or replaces the one with the same id. */
    fun put(item: RecentItem) = _items.update { items ->
        val index = items.indexOfFirst { it.id == item.id }
        if (index >= 0) items.toMutableList().apply { set(index, item) } else (listOf(item) + items).take(LIMIT)
    }

    fun clear() = _items.update { items -> items.filter { it.inProgress } }
}
