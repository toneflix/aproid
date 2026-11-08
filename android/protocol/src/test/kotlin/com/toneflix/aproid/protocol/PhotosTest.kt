package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PhotosTest {
    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    @Test fun pageRoundTrips() {
        val photos = listOf(
            PhonePhoto(12, "IMG_2041.jpg", 1_700_000_000_000, "image/jpeg", 4000, 3000, 2_400_000, "aGVsbG8="),
            PhonePhoto(13, "VID_0007.mp4", 1_700_000_100_000, "video/mp4"),
        )

        assertEquals(Photos.Page(photos, more = true), Photos.page(wire(Photos.pagePacket(photos, more = true))))
        assertEquals(true, photos[1].isVideo)
    }

    @Test fun requestsRoundTrip() {
        assertEquals(Photos.Request(1_700_000_000_000, 40), Photos.request(wire(Photos.request(1_700_000_000_000))))
        assertEquals(Photos.Request(null, 200), Photos.request(wire(Photos.request(count = 5000))))
        assertEquals(12L, Photos.downloadId(wire(Photos.download(12))))
        assertNull(Photos.downloadId(Photos.request()))
    }
}
