package org.nighthawklabs.retro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.nighthawklabs.retro.net.Api
import org.nighthawklabs.retro.net.RetroApi
import org.nighthawklabs.retro.net.map
import org.nighthawklabs.retro.net.problem

/** The client's own logic: status classification and both error shapes. The engine's rules do not live here. */
class ApiTest {

    @Test
    fun `success decodes`() {
        val result = RetroApi.classify(200, """{"kept":3}""") { text ->
            Regex(""""kept":(\d+)""").find(text)!!.groupValues[1].toInt()
        }
        assertTrue(result is Api.Ok)
        assertEquals(3, (result as Api.Ok).value)
    }

    @Test
    fun `auth and provisioning are distinct`() {
        assertTrue(RetroApi.classify(401, "{}") { it } is Api.Unauthorized)
        assertTrue(RetroApi.classify(403, "{}") { it } is Api.Unauthorized)
        // A 404 is only "not provisioned" when the router says so; any other 404 is a real failure.
        assertTrue(RetroApi.classify(404, """{"error":"no_tenant"}""") { it } is Api.NotProvisioned)
        assertTrue(RetroApi.classify(404, """{"error":{"code":"not_found","message":"gone"}}""") { it } is Api.Failed)
    }

    @Test
    fun `transient and permanent failures separate`() {
        listOf(408, 429, 502, 503, 504).forEach { code ->
            assertTrue("$code should be retryable", RetroApi.classify(code, "{}") { it } is Api.Retry)
        }
        assertTrue(RetroApi.classify(500, "{}") { it } is Api.ServerError)
        assertTrue(RetroApi.classify(200, "not json") { error("boom") } is Api.Retry)
    }

    @Test
    fun `both error shapes are read`() {
        val engine = RetroApi.errorOf("""{"error":{"code":"conflict","message":"already there"}}""")
        assertEquals("conflict", engine.first)
        assertEquals("already there", engine.second)

        val router = RetroApi.errorOf("""{"error":"no route"}""")
        assertNull(router.first)
        assertEquals("no route", router.second)

        val nothing = RetroApi.errorOf("{}")
        assertNull(nothing.first)
        assertNull(nothing.second)
    }

    @Test
    fun `a failure keeps its message and a success has no problem line`() {
        val failed: Api<Int> = Api.Failed("conflict", "already there")
        assertEquals("already there", failed.problem)
        val ok: Api<Int> = Api.Ok(1)
        assertNull(ok.problem)
        val mapped = ok.map { it + 1 }
        assertEquals(2, (mapped as Api.Ok).value)
    }
}
