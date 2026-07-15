package com.gilmoretech.incoming_request_overlay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OfferPayloadTest {
    @Test
    fun `parses a valid ride and coerces payload values to strings`() {
        val offer = OfferPayload.fromMap(
            mapOf(
                "offerId" to "ride-1",
                "offerType" to "ride",
                "expiresAtMillis" to 9_999_999_999_999L,
                "title" to "New ride request",
                "pickup" to "Osu",
                "duration" to " 18 min ",
                "mapPreviewUrl" to " https://media.myshop.example/route/ride-1 ",
                "payload" to mapOf("rideId" to "ride-1", "attempt" to 2),
            ),
        )

        requireNotNull(offer)
        assertEquals("ride:ride-1", offer.identity)
        assertEquals("Osu", offer.pickup)
        assertEquals("18 min", offer.duration)
        assertEquals(
            "https://media.myshop.example/route/ride-1",
            offer.mapPreviewUrl,
        )
        assertEquals("2", offer.payload["attempt"])
        assertFalse(offer.isExpired(1L))
    }

    @Test
    fun `rejects unknown type or missing identity`() {
        assertNull(
            OfferPayload.fromMap(
                mapOf(
                    "offerId" to "request-1",
                    "offerType" to "delivery",
                    "expiresAtMillis" to 10L,
                    "title" to "Request",
                ),
            ),
        )
        assertNull(
            OfferPayload.fromMap(
                mapOf(
                    "offerType" to "ride",
                    "expiresAtMillis" to 10L,
                    "title" to "Request",
                ),
            ),
        )
    }

    @Test
    fun `expiry is anchored to the supplied absolute deadline`() {
        val offer = OfferPayload.fromMap(
            mapOf(
                "offerId" to "job-1",
                "offerType" to "job",
                "expiresAtMillis" to "5000",
                "title" to "New job request",
            ),
        )

        requireNotNull(offer)
        assertFalse(offer.isExpired(4_999L))
        assertTrue(offer.isExpired(5_000L))
    }
}
