package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingTest {
    private fun pair(pair: Boolean, ts: Long? = null) =
        NetworkPacket(PacketType.PAIR, NetworkPacket.body("pair" to pair, "timestamp" to ts))

    @Test fun weRequestAndPeerAccepts() {
        val sm = PairingStateMachine()
        val a = sm.requestPair(1000)
        assertTrue(a is PairAction.Send)
        assertEquals(1000L, (a as PairAction.Send).packet.long("timestamp"))
        assertEquals(PairState.REQUESTED, sm.state)
        assertEquals(PairAction.Paired, sm.onPacket(pair(true), 1005))
        assertEquals(PairState.PAIRED, sm.state)
    }

    @Test fun peerRequestsAndUserAccepts() {
        val sm = PairingStateMachine()
        assertEquals(PairAction.AskUser, sm.onPacket(pair(true, 1000), 1001))
        assertEquals(PairState.REQUESTED_BY_PEER, sm.state)
        val a = sm.accept() as PairAction.Send
        assertEquals(true, a.packet.bool("pair"))
        assertEquals(PairState.PAIRED, sm.state)
    }

    @Test fun refusesEveryRequestWhenNotAllowed() {
        val sm = PairingStateMachine(PairState.PAIRED, allowed = false)
        assertEquals(PairState.NOT_PAIRED, sm.state)
        assertEquals(PairAction.None, sm.requestPair(1000))

        val a = sm.onPacket(pair(true, 1000), 1001) as PairAction.Send
        assertEquals(false, a.packet.bool("pair"))
        assertEquals(PairState.NOT_PAIRED, sm.state)
    }

    @Test fun staleTimestampIsRefused() {
        val sm = PairingStateMachine()
        val a = sm.onPacket(pair(true, 0), 100_000) as PairAction.Send
        assertEquals(false, a.packet.bool("pair"))
        assertEquals(PairState.NOT_PAIRED, sm.state)
    }

    @Test fun requestTimesOut() {
        val sm = PairingStateMachine()
        sm.requestPair(0)
        assertEquals(PairAction.None, sm.tick(10))
        assertEquals(PairAction.Unpaired, sm.tick(31))
        assertEquals(PairState.NOT_PAIRED, sm.state)
    }

    @Test fun peerUnpairs() {
        val sm = PairingStateMachine(PairState.PAIRED)
        assertEquals(PairAction.Unpaired, sm.onPacket(pair(false), 0))
        assertEquals(PairState.NOT_PAIRED, sm.state)
    }
}
