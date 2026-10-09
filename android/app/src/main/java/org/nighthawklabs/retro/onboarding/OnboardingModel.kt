package org.nighthawklabs.retro.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import org.nighthawklabs.retro.net.Api
import org.nighthawklabs.retro.net.problem
import java.security.SecureRandom

@Serializable
data class OnboardingProgress(val status: String, val error: String? = null)

@Serializable
data class OnboardingAccepted(val status: String)

@Serializable
data class OnboardingRequest(
    @SerialName("llm_tiers") val llmTiers: Map<String, String> = emptyMap(),
    @SerialName("postgres_password") val postgresPassword: String,
    @SerialName("agent_brain_db_password") val agentBrainDbPassword: String,
    @SerialName("agent_brain_api_key") val agentBrainApiKey: String,
    @SerialName("agent_brain_jwt_secret") val agentBrainJwtSecret: String,
    @SerialName("mcp_hub_db_password") val mcpHubDbPassword: String,
) {
    companion object {
        fun make(): OnboardingRequest {
            val random = SecureRandom()
            fun secret() = ByteArray(32).also(random::nextBytes).joinToString("") { "%02x".format(it) }
            return OnboardingRequest(postgresPassword = secret(), agentBrainDbPassword = secret(), agentBrainApiKey = secret(),
                agentBrainJwtSecret = secret(), mcpHubDbPassword = secret())
        }
    }
}

class OnboardingModel(
    private val status: suspend () -> Api<OnboardingProgress>,
    private val submit: suspend (OnboardingRequest) -> Api<OnboardingAccepted>,
) {
    enum class Phase { Checking, Setup, Provisioning, Ready, Failed, Unavailable }
    var phase by mutableStateOf(Phase.Checking)
        private set
    var working by mutableStateOf(false)
        private set
    var problem by mutableStateOf<String?>(null)
        private set

    suspend fun refresh() {
        if (working) return
        working = true
        try { readStatus() } finally { working = false }
    }

    suspend fun start() {
        if (working || phase !in listOf(Phase.Setup, Phase.Failed)) return
        working = true
        try {
            // The server is authoritative across relaunches and other clients; never replay completed or running setup.
            if (!readStatus() || phase !in listOf(Phase.Setup, Phase.Failed) || !currentCoroutineContext().isActive) return
            val request = runCatching { OnboardingRequest.make() }.getOrElse {
                problem = "Couldn't securely prepare setup. Try again."
                return
            }
            when (submit(request)) {
                is Api.Ok -> { phase = Phase.Provisioning; problem = null }
                // The response may have been lost after acceptance. Recheck before any later retry.
                else -> problem = "Couldn't confirm setup. Check your connection and try again."
            }
        } finally { working = false }
    }

    suspend fun watch() {
        while (phase == Phase.Provisioning && currentCoroutineContext().isActive) {
            refresh()
            if (phase != Phase.Provisioning) return
            delay(3_000)
        }
    }

    private suspend fun readStatus(): Boolean {
        val result = status()
        if (!currentCoroutineContext().isActive) return false
        when (result) {
            is Api.Ok -> {
                problem = null
                when (result.value.status) {
                    "completed" -> phase = Phase.Ready
                    "pending", "running", "awaiting_approval" -> phase = Phase.Provisioning
                    "failed" -> { phase = Phase.Failed; problem = "Setup didn't finish. You can try again." }
                    else -> { phase = Phase.Unavailable; problem = "Couldn't read setup progress."; return false }
                }
                return true
            }
            is Api.Failed -> if (result.message == "no onboarding request found") {
                phase = Phase.Setup
                problem = null
                return true
            }
            else -> Unit
        }
        problem = result.problem
        // Like the other clients, an offline check must not lock an existing account out of the app.
        if (phase == Phase.Checking) phase = Phase.Ready
        return false
    }
}
