package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeviceFocusTest {
    private data class Peer(val id: String, val name: String)

    private val devices = listOf(Peer("c", "Pixel"), Peer("a", "Galaxy"), Peer("b", "Pixel"))

    private fun pick(preferredId: String?, list: List<Peer> = devices) =
        DeviceFocus(preferredId).pick(list, { it.id }, { it.name })

    @Test fun preferredDeviceWins() {
        assertEquals(Peer("c", "Pixel"), pick("c"))
    }

    @Test fun fallsBackToFirstByName() {
        assertEquals(Peer("a", "Galaxy"), pick(null))
    }

    @Test fun missingPreferredFallsBack() {
        assertEquals(Peer("a", "Galaxy"), pick("gone"))
    }

    @Test fun sameNamesAreOrderedById() {
        assertEquals(Peer("b", "Pixel"), pick(null, listOf(Peer("c", "Pixel"), Peer("b", "Pixel"))))
    }

    private fun next(preferredId: String?, list: List<Peer> = devices) =
        DeviceFocus(preferredId).next(list, { it.id }, { it.name })

    @Test fun nextFollowsNameOrder() {
        assertEquals(Peer("b", "Pixel"), next("a"))
        assertEquals(Peer("c", "Pixel"), next("b"))
    }

    @Test fun nextWrapsToFirst() {
        assertEquals(Peer("a", "Galaxy"), next("c"))
    }

    @Test fun nextWithoutPreferredStartsAtFirst() {
        assertEquals(Peer("a", "Galaxy"), next("gone"))
        assertNull(next("a", emptyList()))
    }

    @Test fun noDevicesPicksNothing() {
        assertNull(pick("a", emptyList()))
    }
}
