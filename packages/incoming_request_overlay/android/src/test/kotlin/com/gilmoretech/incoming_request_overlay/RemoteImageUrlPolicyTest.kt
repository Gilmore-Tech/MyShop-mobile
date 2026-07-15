package com.gilmoretech.incoming_request_overlay

import java.net.URL
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteImageUrlPolicyTest {
    @Test
    fun `accepts ordinary HTTPS image URLs`() {
        assertNotNull(
            RemoteImageUrlPolicy.parse(
                " https://media.myshop.example/offers/route-1.png?token=signed ",
            ),
        )
    }

    @Test
    fun `rejects cleartext credentials and nonstandard ports`() {
        assertNull(RemoteImageUrlPolicy.parse("http://media.myshop.example/route.png"))
        assertNull(RemoteImageUrlPolicy.parse("https://user:secret@media.myshop.example/route.png"))
        assertNull(RemoteImageUrlPolicy.parse("https://media.myshop.example:8443/route.png"))
    }

    @Test
    fun `allows only same-host HTTPS redirects`() {
        val origin = URL("https://media.myshop.example/route/one")

        assertTrue(
            RemoteImageUrlPolicy.isAllowedRedirect(
                origin,
                URL("https://MEDIA.MYSHOP.EXAMPLE/route/two"),
            ),
        )
        assertFalse(
            RemoteImageUrlPolicy.isAllowedRedirect(
                origin,
                URL("https://objects.example/route/two"),
            ),
        )
        assertFalse(
            RemoteImageUrlPolicy.isAllowedRedirect(
                origin,
                URL("http://media.myshop.example/route/two"),
            ),
        )
    }
}
