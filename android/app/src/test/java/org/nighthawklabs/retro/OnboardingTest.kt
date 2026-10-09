package org.nighthawklabs.retro

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import org.junit.Assert.*
import org.junit.Test
import org.nighthawklabs.retro.net.Api
import org.nighthawklabs.retro.net.ApiJson
import org.nighthawklabs.retro.net.Engine
import org.nighthawklabs.retro.net.RetroApi
import org.nighthawklabs.retro.net.Transport
import org.nighthawklabs.retro.onboarding.*

class OnboardingTest {
    @Test fun `offline initial check does not lock the account out`() = runBlocking {
        for (result in listOf(Api.Retry("offline"), Api.Unauthorized)) {
            val model = OnboardingModel({ result }, { error("an inconclusive check must never provision") })
            model.refresh(); model.start()
            assertEquals(OnboardingModel.Phase.Ready, model.phase)
        }
    }

    @Test fun `completed and running setup never submit`() = runBlocking {
        for (status in listOf("completed", "running", "pending", "awaiting_approval")) {
            var submitted = 0
            val model = OnboardingModel({ Api.Ok(OnboardingProgress(status)) }, {
                submitted++; Api.Ok(OnboardingAccepted("accepted"))
            })
            model.refresh(); model.start()
            assertEquals(0, submitted)
            assertEquals(if (status == "completed") OnboardingModel.Phase.Ready else OnboardingModel.Phase.Provisioning, model.phase)
        }
    }

    @Test fun `lost response and relaunch resume without reposting`() = runBlocking {
        var accepted = false
        var submitted = 0
        val model = OnboardingModel({
            if (accepted) Api.Ok(OnboardingProgress("running")) else Api.Failed(null, "no onboarding request found")
        }, { submitted++; accepted = true; Api.Retry("offline") })
        model.refresh(); model.start(); model.start()
        assertEquals(1, submitted)
        assertEquals(OnboardingModel.Phase.Provisioning, model.phase)
        val relaunched = OnboardingModel({ Api.Ok(OnboardingProgress("running")) }, { error("must only watch") })
        relaunched.refresh()
        assertEquals(OnboardingModel.Phase.Provisioning, relaunched.phase)
    }

    @Test fun `transient and unknown status never start setup`() = runBlocking {
        var result: Api<OnboardingProgress> = Api.Failed(null, "no onboarding request found")
        var submitted = 0
        val model = OnboardingModel({ result }, { submitted++; Api.Ok(OnboardingAccepted("accepted")) })
        model.refresh()
        result = Api.Retry("offline"); model.start()
        result = Api.Ok(OnboardingProgress("unexpected")); model.start()
        assertEquals(0, submitted)
        assertEquals(OnboardingModel.Phase.Unavailable, model.phase)
    }

    @Test fun `double tap submits once and failed setup can retry`() = runBlocking {
        var submitted = 0
        val reached = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val model = OnboardingModel({ Api.Ok(OnboardingProgress("failed")) }, {
            submitted++; reached.complete(Unit); release.await(); Api.Ok(OnboardingAccepted("accepted"))
        })
        model.refresh()
        val first = async { model.start() }
        reached.await(); model.start(); release.complete(Unit); first.await()
        assertEquals(1, submitted)
        assertEquals(OnboardingModel.Phase.Provisioning, model.phase)
    }

    @Test fun `request uses platform defaults and independent secure secrets`() {
        val request = OnboardingRequest.make()
        val secrets = listOf(request.postgresPassword, request.agentBrainDbPassword, request.agentBrainApiKey,
            request.agentBrainJwtSecret, request.mcpHubDbPassword)
        assertEquals(5, secrets.toSet().size)
        assertTrue(secrets.all { it.matches(Regex("[0-9a-f]{64}")) })
        val body = ApiJson.parseToJsonElement(ApiJson.encodeToString(request)).toString()
        assertTrue(body.contains("\"llm_tiers\":{}"))
        assertTrue(body.contains("\"postgres_password\""))
    }

    @Test fun `onboarding uses shared route refreshes token and isolates accounts`() = runBlocking {
        val sent = mutableListOf<Pair<String, String>>()
        val router = RetroApi("https://router.test", Transport { method, url, token, body, _ ->
            sent += method to url
            if (token == "stale") 401 to "{}" else if (body == null) 200 to """{"status":"completed","steps":[]}"""
            else 202 to """{"status":"accepted"}"""
        })
        var user = "A"
        val engine = Engine(RetroApi("https://engine.test"), "A", { user }, router) { fresh -> if (fresh) "fresh" else "stale" }
        assertTrue(engine.onboardingStatus() is Api.Ok)
        assertEquals(listOf("GET" to "https://router.test/onboard", "GET" to "https://router.test/onboard"), sent)
        user = "B"
        assertEquals(Api.Unauthorized, engine.startOnboarding(OnboardingRequest.make()))
        assertEquals(2, sent.size)
    }

    @Test fun `expired onboarding history checks existing workspace before creating again`() = runBlocking {
        var health = 200 to ""
        val sent = mutableListOf<String>()
        val router = RetroApi("https://router.test", Transport { _, url, _, _, _ ->
            sent += url
            if (url.endsWith("/onboard")) 404 to """{"error":"no onboarding request found"}""" else health
        })
        val engine = Engine(RetroApi("https://engine.test"), "A", { "A" }, router) { "token" }
        val existing = engine.onboardingStatus()
        assertEquals("completed", (existing as Api.Ok).value.status)
        assertEquals(listOf("https://router.test/onboard", "https://router.test/gateway/healthz"), sent)
        health = 404 to """{"error":"no_tenant"}"""
        assertTrue(engine.onboardingStatus() is Api.Failed)
        health = 502 to """{"error":"upstream unavailable"}"""
        assertTrue(engine.onboardingStatus() is Api.Retry)
    }
}
