package com.toneflix.flyylink

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Log
import com.toneflix.flyylink.protocol.Call
import com.toneflix.flyylink.protocol.CallEvent
import com.toneflix.flyylink.protocol.Device
import com.toneflix.flyylink.protocol.NetworkPacket
import com.toneflix.flyylink.protocol.PacketType
import com.toneflix.flyylink.protocol.Plugin

/** Tells the Mac about calls, and answers, declines, hangs up, mutes or dials when the Mac asks. */
object CallPlugin : Plugin {
    private const val TAG = "FlyyLinkCalls"

    override val incoming = setOf(PacketType.CALL_REQUEST)

    private var context: Context? = null

    /** The last phone state and number, to tell a missed call from an answered one. */
    private var lastState = TelephonyManager.EXTRA_STATE_IDLE
    private var lastNumber: String? = null
    private var answered = false

    val permissions: Array<String> = buildList {
        add(Manifest.permission.READ_PHONE_STATE)
        add(Manifest.permission.READ_CALL_LOG)
        add(Manifest.permission.CALL_PHONE)
        add(Manifest.permission.ANSWER_PHONE_CALLS)
        add(Manifest.permission.READ_CONTACTS)
        add(Manifest.permission.READ_SMS)
        add(Manifest.permission.SEND_SMS)
    }.toTypedArray()

    fun hasPermissions(context: Context) = permissions.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    fun start(context: Context) {
        this.context = context.applicationContext
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return
        val request = Call.request(packet) ?: return
        val telecom = context.getSystemService(TelecomManager::class.java)

        runCatching {
            when (request.action) {
                Call.Action.ANSWER -> answer(context, telecom)
                Call.Action.DECLINE, Call.Action.HANG_UP -> hangUp(context, telecom)
                Call.Action.MUTE, Call.Action.UNMUTE -> mute(context, request.action == Call.Action.MUTE)
                Call.Action.DIAL -> request.number?.let { dial(context, telecom, it) }
            }
        }.onFailure { Log.w(TAG, "Call ${request.action} failed", it) }
    }

    @SuppressLint("MissingPermission")
    private fun answer(context: Context, telecom: TelecomManager) {
        if (!granted(context, Manifest.permission.ANSWER_PHONE_CALLS)) return

        telecom.acceptRingingCall()
    }

    @SuppressLint("MissingPermission")
    private fun hangUp(context: Context, telecom: TelecomManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || !granted(context, Manifest.permission.ANSWER_PHONE_CALLS)) return

        @Suppress("DEPRECATION")
        telecom.endCall()
    }

    /** Mutes the phone's microphone. Some phones only let the dialer do this, so it may have no effect. */
    private fun mute(context: Context, muted: Boolean) {
        context.getSystemService(AudioManager::class.java).isMicrophoneMute = muted
    }

    @SuppressLint("MissingPermission")
    private fun dial(context: Context, telecom: TelecomManager, number: String) {
        if (!granted(context, Manifest.permission.CALL_PHONE)) return

        telecom.placeCall(Uri.fromParts("tel", number, null), null)
    }

    private fun granted(context: Context, permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** Called by [PhoneStateReceiver] for every change in the phone's call state. */
    fun stateChanged(context: Context, state: String, number: String?) {
        // The broadcast comes twice: once without the number and once with it.
        if (number == null && state != TelephonyManager.EXTRA_STATE_IDLE) return
        if (state == lastState && number == lastNumber) return

        val event = when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                answered = false
                CallEvent.RINGING
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                answered = true
                CallEvent.TALKING
            }
            else -> if (lastState == TelephonyManager.EXTRA_STATE_RINGING && !answered) CallEvent.MISSED else null
        }
        val callNumber = number ?: lastNumber.orEmpty()
        lastState = state
        lastNumber = number ?: lastNumber

        if (event == null) {
            DeviceStore.sendToPaired(Call.ended(callNumber))
            return
        }

        val contact = Contacts.lookup(context, callNumber)
        val photo = if (event == CallEvent.RINGING) Contacts.photoBase64(context, callNumber) else null
        DeviceStore.sendToPaired(Call.event(event, callNumber, contact.name, photo))
        if (event == CallEvent.MISSED) DeviceStore.sendToPaired(Call.ended(callNumber))
    }
}

/** Android announces call state changes to apps that can read the phone state, even in the background. */
class PhoneStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        @Suppress("DEPRECATION")
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        CallPlugin.stateChanged(context, state, number)
    }
}
