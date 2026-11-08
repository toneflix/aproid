package com.toneflix.aproid

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.database.Cursor
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.Plugin
import com.toneflix.aproid.protocol.Sms
import com.toneflix.aproid.protocol.SmsAddress
import com.toneflix.aproid.protocol.SmsAttachment
import com.toneflix.aproid.protocol.SmsMessage

/**
 * Lets the Mac read the phone's text conversations and send texts. MMS ids are sent negated,
 * since SMS and MMS number their messages separately.
 */
object SmsPlugin : Plugin {
    private const val TAG = "AproidSms"
    private const val MMS_FROM = 137
    private const val THUMBNAIL_SIZE = 320
    private const val SCAN_LIMIT = 5000

    override val incoming = setOf(PacketType.SMS_REQUEST, PacketType.SMS_REQUEST_CONVERSATIONS, PacketType.SMS_REQUEST_CONVERSATION)

    private var context: Context? = null
    private val worker = HandlerThread("aproid-sms").apply { start() }
    private val handler = Handler(worker.looper)

    /** The newest message date already sent to the Macs, so a change only sends what is new. */
    @Volatile private var newestSent = 0L

    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) = sendNew()
    }

    @Volatile private var observing = false

    /** Safe to call again, for example right after the user grants the permission. */
    @Synchronized fun start(context: Context) {
        this.context = context.applicationContext
        if (observing || !canRead(context)) return

        newestSent = System.currentTimeMillis()
        observing = runCatching {
            context.contentResolver.registerContentObserver(Uri.parse("content://mms-sms/"), true, observer)
        }.isSuccess
    }

    @Synchronized fun stop(context: Context) {
        runCatching { context.contentResolver.unregisterContentObserver(observer) }
        observing = false
    }

    fun canRead(context: Context) = context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return
        if (!canRead(context)) return

        handler.post {
            runCatching { handle(context, device, packet) }.onFailure { Log.w(TAG, "SMS request failed", it) }
        }
    }

    private fun handle(context: Context, device: Device, packet: NetworkPacket) {
        when (packet.type) {
            PacketType.SMS_REQUEST_CONVERSATIONS -> DeviceStore.send(device, Sms.messagesPacket(latestPerThread(context)))
            PacketType.SMS_REQUEST_CONVERSATION -> {
                val request = Sms.conversationRequest(packet) ?: return
                val messages = thread(context, request.threadId, request.before, request.count ?: 50)
                DeviceStore.send(device, Sms.messagesPacket(messages))
            }
            PacketType.SMS_REQUEST -> Sms.sendRequest(packet)?.let { send(context, it) }
        }
    }

    private fun send(context: Context, request: Sms.SendRequest) {
        if (context.checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) return

        val manager = smsManager(context, request.subscriptionId?.toInt())
        val parts = manager.divideMessage(request.body)
        // Android records texts sent by other apps itself, and the observer then shows them on the Mac.
        request.addresses.forEach { manager.sendMultipartTextMessage(it, null, parts, null, null) }
    }

    @Suppress("DEPRECATION")
    private fun smsManager(context: Context, subscriptionId: Int?): SmsManager {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(SmsManager::class.java)
            return if (subscriptionId != null) manager.createForSubscriptionId(subscriptionId) else manager
        }

        return if (subscriptionId != null) SmsManager.getSmsManagerForSubscriptionId(subscriptionId) else SmsManager.getDefault()
    }

    /** Sends messages that arrived or were sent since the last time. */
    private fun sendNew() {
        val context = context ?: return
        val since = newestSent
        val messages = runCatching { query(context, since = since) }.getOrDefault(emptyList())
        if (messages.isEmpty()) return

        newestSent = maxOf(since, messages.maxOf { it.date })
        DeviceStore.sendToPaired(Sms.messagesPacket(messages))
    }

    private fun latestPerThread(context: Context): List<SmsMessage> =
        query(context, limit = SCAN_LIMIT).groupBy { it.threadId }.map { (_, messages) -> messages.maxBy { it.date } }

    private fun thread(context: Context, threadId: Long, before: Long?, count: Int): List<SmsMessage> =
        query(context, threadId = threadId, before = before, limit = count).sortedByDescending { it.date }.take(count)

    /** Texts and MMS, newest first, matching all the given filters. */
    private fun query(context: Context, threadId: Long? = null, before: Long? = null, since: Long? = null, limit: Int = SCAN_LIMIT): List<SmsMessage> =
        (texts(context, threadId, before, since, limit) + mms(context, threadId, before, since, limit))
            .sortedByDescending { it.date }

    private fun texts(context: Context, threadId: Long?, before: Long?, since: Long?, limit: Int): List<SmsMessage> {
        val (selection, args) = filters(Telephony.Sms.THREAD_ID, Telephony.Sms.DATE, threadId, before, since, scale = 1)
        val projection = arrayOf(
            Telephony.Sms._ID, Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY,
            Telephony.Sms.DATE, Telephony.Sms.TYPE, Telephony.Sms.READ, Telephony.Sms.SUBSCRIPTION_ID,
        )

        return context.contentResolver.query(Telephony.Sms.CONTENT_URI, projection, selection, args, "${Telephony.Sms.DATE} DESC LIMIT $limit")
            ?.use { cursor ->
                cursor.rows().map {
                    val address = cursor.getString(2).orEmpty()
                    SmsMessage(
                        id = cursor.getLong(0),
                        threadId = cursor.getLong(1),
                        body = cursor.getString(3).orEmpty(),
                        addresses = listOf(SmsAddress(address, Contacts.name(context, address))),
                        date = cursor.getLong(4),
                        isIncoming = cursor.getInt(5) == Telephony.Sms.MESSAGE_TYPE_INBOX,
                        isRead = cursor.getInt(6) != 0,
                        subscriptionId = cursor.getInt(7).takeIf { it >= 0 },
                    )
                }.toList()
            }
            .orEmpty()
    }

    private fun mms(context: Context, threadId: Long?, before: Long?, since: Long?, limit: Int): List<SmsMessage> {
        // MMS dates are in seconds.
        val (selection, args) = filters(Telephony.Mms.THREAD_ID, Telephony.Mms.DATE, threadId, before, since, scale = 1000)
        val projection = arrayOf(Telephony.Mms._ID, Telephony.Mms.THREAD_ID, Telephony.Mms.DATE, Telephony.Mms.MESSAGE_BOX, Telephony.Mms.READ, Telephony.Mms.SUBSCRIPTION_ID)

        return context.contentResolver.query(Telephony.Mms.CONTENT_URI, projection, selection, args, "${Telephony.Mms.DATE} DESC LIMIT $limit")
            ?.use { cursor ->
                cursor.rows().map {
                    val id = cursor.getLong(0)
                    val (body, attachments) = parts(context, id)
                    SmsMessage(
                        id = -id,
                        threadId = cursor.getLong(1),
                        body = body,
                        addresses = mmsAddresses(context, id),
                        date = cursor.getLong(2) * 1000,
                        isIncoming = cursor.getInt(3) == Telephony.Mms.MESSAGE_BOX_INBOX,
                        isRead = cursor.getInt(4) != 0,
                        subscriptionId = cursor.getInt(5).takeIf { it >= 0 },
                        attachments = attachments,
                    )
                }.toList()
            }
            .orEmpty()
    }

    private fun filters(threadColumn: String, dateColumn: String, threadId: Long?, before: Long?, since: Long?, scale: Long): Pair<String?, Array<String>?> {
        val clauses = mutableListOf<String>()
        val args = mutableListOf<String>()

        threadId?.let { clauses += "$threadColumn = ?"; args += it.toString() }
        before?.let { clauses += "$dateColumn < ?"; args += (it / scale).toString() }
        since?.let { clauses += "$dateColumn > ?"; args += (it / scale).toString() }

        return if (clauses.isEmpty()) null to null else clauses.joinToString(" AND ") to args.toTypedArray()
    }

    /** The MMS text and its pictures, with small thumbnails. */
    private fun parts(context: Context, mmsId: Long): Pair<String, List<SmsAttachment>> {
        val text = StringBuilder()
        val attachments = mutableListOf<SmsAttachment>()

        context.contentResolver.query(Uri.parse("content://mms/part"), arrayOf("_id", "ct", "text"), "mid = ?", arrayOf(mmsId.toString()), null)
            ?.use { cursor ->
                cursor.rows().forEach {
                    val partId = cursor.getLong(0)
                    val type = cursor.getString(1).orEmpty()

                    when {
                        type == "text/plain" -> cursor.getString(2)?.let { text.append(it) }
                        type.startsWith("image/") -> attachments += SmsAttachment(partId, type, "part-$partId", thumbnail(context, partId))
                    }
                }
            }

        return text.toString() to attachments
    }

    private fun thumbnail(context: Context, partId: Long): String? = runCatching {
        context.contentResolver.openInputStream(Uri.parse("content://mms/part/$partId"))
            ?.use { BitmapFactory.decodeStream(it) }
            ?.let { Contacts.encode(it, THUMBNAIL_SIZE) }
    }.getOrNull()

    private fun mmsAddresses(context: Context, mmsId: Long): List<SmsAddress> {
        val own = setOf("insert-address-token", "")

        return context.contentResolver.query(Uri.parse("content://mms/$mmsId/addr"), arrayOf("address", "type"), null, null, null)
            ?.use { cursor ->
                cursor.rows().map { cursor.getString(0).orEmpty() to cursor.getInt(1) }.toList()
            }
            .orEmpty()
            .filter { (address, _) -> address !in own }
            .sortedByDescending { (_, type) -> type == MMS_FROM }
            .map { (address, _) -> SmsAddress(address, Contacts.name(context, address)) }
            .distinctBy { it.address }
    }

    private fun Cursor.rows(): Sequence<Cursor> = generateSequence { if (moveToNext()) this else null }
}
