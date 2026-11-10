package com.toneflix.aproid.protocol

import kotlin.math.abs

enum class PairState { NOT_PAIRED, REQUESTED, REQUESTED_BY_PEER, PAIRED }

/** What the caller should do after the state machine handles an event. */
sealed interface PairAction {
    data object None : PairAction
    data class Send(val packet: NetworkPacket) : PairAction
    /** Ask the user to accept or reject the peer's request. */
    data object AskUser : PairAction
    data object Paired : PairAction
    data object Unpaired : PairAction
}

/**
 * Pairing for one peer, following KDE Connect protocol v8: a "kdeconnect.pair" packet with
 * pair=true asks to pair (with a timestamp in seconds), pair=false rejects or unpairs.
 * Time is passed in so the logic can be tested without a clock. With [allowed] false, this side never
 * asks to pair and refuses every request.
 */
class PairingStateMachine(
    initial: PairState = PairState.NOT_PAIRED,
    private val timeoutSeconds: Long = 30,
    private val maxClockSkewSeconds: Long = 1800,
    private val allowed: Boolean = true,
) {
    var state: PairState = if (allowed) initial else PairState.NOT_PAIRED
        private set
    private var requestedAt: Long = 0

    /** Unix time in seconds of the last pair request. Both sides use it for the verification code. */
    var requestTimestamp: Long = 0
        private set

    fun requestPair(nowSeconds: Long): PairAction {
        if (!allowed) return PairAction.None
        if (state == PairState.PAIRED || state == PairState.REQUESTED) return PairAction.None
        if (state == PairState.REQUESTED_BY_PEER) return accept()
        state = PairState.REQUESTED
        requestedAt = nowSeconds
        requestTimestamp = nowSeconds
        return PairAction.Send(pairPacket(true, nowSeconds))
    }

    fun accept(): PairAction {
        if (state != PairState.REQUESTED_BY_PEER) return PairAction.None
        state = PairState.PAIRED
        return PairAction.Send(pairPacket(true, null))
    }

    fun reject(): PairAction {
        if (state != PairState.REQUESTED_BY_PEER) return PairAction.None
        state = PairState.NOT_PAIRED
        return PairAction.Send(pairPacket(false, null))
    }

    fun unpair(): PairAction {
        if (state == PairState.NOT_PAIRED) return PairAction.None
        state = PairState.NOT_PAIRED
        return PairAction.Send(pairPacket(false, null))
    }

    /** Call regularly. Drops a request that nobody answered. */
    fun tick(nowSeconds: Long): PairAction {
        if (state == PairState.REQUESTED && nowSeconds - requestedAt > timeoutSeconds) {
            state = PairState.NOT_PAIRED
            return PairAction.Unpaired
        }
        return PairAction.None
    }

    fun onPacket(packet: NetworkPacket, nowSeconds: Long): PairAction {
        if (packet.type != PacketType.PAIR) return PairAction.None
        val wantsPair = packet.bool("pair") ?: return PairAction.None
        if (!wantsPair) {
            val was = state
            state = PairState.NOT_PAIRED
            return if (was == PairState.NOT_PAIRED) PairAction.None else PairAction.Unpaired
        }
        return when (state) {
            PairState.REQUESTED -> {
                state = PairState.PAIRED
                PairAction.Paired
            }
            PairState.NOT_PAIRED -> {
                val ts = packet.long("timestamp")
                if (!allowed || ts == null || abs(nowSeconds - ts) > maxClockSkewSeconds) {
                    // Not allowed, or a missing or stale timestamp: refuse, as protocol v8 requires.
                    PairAction.Send(pairPacket(false, null))
                } else {
                    state = PairState.REQUESTED_BY_PEER
                    requestTimestamp = ts
                    PairAction.AskUser
                }
            }
            // Peer re-sent its request, or we are already paired (KDE Connect re-confirms).
            PairState.REQUESTED_BY_PEER -> PairAction.None
            PairState.PAIRED -> PairAction.Send(pairPacket(true, null))
        }
    }

    private fun pairPacket(pair: Boolean, timestamp: Long?) = NetworkPacket(
        type = PacketType.PAIR,
        body = NetworkPacket.body("pair" to pair, "timestamp" to timestamp),
    )
}
