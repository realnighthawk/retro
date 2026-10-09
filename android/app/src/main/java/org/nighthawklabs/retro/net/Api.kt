package org.nighthawklabs.retro.net

import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.serializer
import org.nighthawklabs.retro.BuildConfig
import org.nighthawklabs.retro.DevMode
import org.nighthawklabs.retro.onboarding.OnboardingAccepted
import org.nighthawklabs.retro.onboarding.OnboardingProgress
import org.nighthawklabs.retro.onboarding.OnboardingRequest

/** JSON for the wire: explicit snake_case in the models, never a naming strategy. */
val ApiJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/** The outcome of one engine call. These are the cases the UI branches on, so nothing downstream reads a status code. */
sealed interface Api<out T> {
    data class Ok<T>(val value: T) : Api<T>
    data object Unauthorized : Api<Nothing>
    /** The router has no instance for this user yet. */
    data object NotProvisioned : Api<Nothing>
    /** Couldn't reach the engine, or it is busy or restarting (offline, 408, 429, 502-504). Safe to resend. */
    data class Retry(val message: String) : Api<Nothing>
    /** The engine answered 500: probably transient, possibly a bug that will repeat. Resend a few times, then give up. */
    data class ServerError(val message: String) : Api<Nothing>
    /** The engine understood and said no; [code] is its machine-readable reason. */
    data class Failed(val code: String?, val message: String) : Api<Nothing>
}

/** A short, human line for a failed call; null when it succeeded. */
val Api<*>.problem: String?
    get() = when (this) {
        is Api.Ok -> null
        Api.Unauthorized -> "Session expired. Sign in again."
        Api.NotProvisioned -> "Your Retro service isn't set up yet."
        is Api.Retry -> "Couldn't reach Retro: $message"
        is Api.ServerError -> "Retro had a problem ($message). Try again in a moment."
        is Api.Failed -> message
    }

fun <T, U> Api<T>.map(f: (T) -> U): Api<U> = when (this) {
    is Api.Ok -> Api.Ok(f(value))
    Api.Unauthorized -> Api.Unauthorized
    Api.NotProvisioned -> Api.NotProvisioned
    is Api.Retry -> this
    is Api.ServerError -> this
    is Api.Failed -> this
}

/** This result re-typed, when it isn't a success; null for a success. */
@Suppress("UNCHECKED_CAST")
fun <U> Api<*>.failure(): Api<U>? = if (this is Api.Ok) null else this as Api<U>

/** An authenticated HTTP request. Returns null when the network failed before any response. */
fun interface Transport {
    suspend fun request(method: String, url: String, token: String, body: String?, timeoutMs: Int): Pair<Int, String>?
}

fun interface BinaryTransport {
    suspend fun requestBytes(method: String, url: String, token: String, body: ByteArray?): Pair<Int, ByteArray>?
}

/** What the stores talk to; tests swap in a fake. */
interface EngineApi {
    suspend fun <I, O> call(op: String, input: I, inSer: KSerializer<I>, outSer: KSerializer<O>): Api<O>
}

suspend inline fun <reified I, reified O> EngineApi.call(op: String, input: I): Api<O> =
    call(op, input, serializer<I>(), serializer<O>())

/** Every operation is `POST <router>/retro/api/v1/operations/<name>` with a JSON object body. */
class RetroApi(internal val baseUrl: String, private val transport: Transport = UrlTransport, private val binary: BinaryTransport = PhotoTransport) {
    suspend fun photoRequest(method: String, path: String, token: String, body: ByteArray? = null): Api<ByteArray> {
        val (status, data) = binary.requestBytes(method, baseUrl.trimEnd('/') + path, token, body) ?: return Api.Retry("network error")
        return if (status in 200..299) Api.Ok(data) else classify(status, data.toString(Charsets.UTF_8)) { ByteArray(0) }
    }
    suspend fun <I, O> call(op: String, input: I, inSer: KSerializer<I>, outSer: KSerializer<O>, token: String): Api<O> {
        val body = runCatching { ApiJson.encodeToString(inSer, input) }.getOrElse { return Api.Failed(null, "Bad request") }
        return request("POST", "/operations/$op", body, token) { ApiJson.decodeFromString(outSer, it) }
    }

    suspend fun <O> request(method: String, path: String, body: String?, token: String, parse: (String) -> O): Api<O> {
        val response = transport.request(method, baseUrl.trimEnd('/') + path, token, body, 30_000)
            ?: return Api.Retry("network error")
        val (code, text) = response
        return classify(code, text, parse)
    }

    companion object {
        fun <T> classify(code: Int, text: String, parse: (String) -> T): Api<T> = when {
            code in 200..299 -> runCatching { Api.Ok(parse(text)) }.getOrElse { Api.Retry("unreadable response") }
            code == 401 || code == 403 -> Api.Unauthorized
            code == 404 && text.contains("no_tenant") -> Api.NotProvisioned
            code == 408 || code == 429 || code in 502..504 -> Api.Retry("server returned $code")
            code >= 500 -> Api.ServerError("server returned $code")
            else -> {
                val (c, m) = errorOf(text)
                Api.Failed(c, m ?: "The server returned $code.")
            }
        }

        // Engine errors are {"error":{"code","message"}}; the router's are {"error":"..."}.
        fun errorOf(text: String): Pair<String?, String?> = runCatching {
            when (val e = ApiJson.parseToJsonElement(text).jsonObject["error"]) {
                is JsonObject -> e["code"]?.jsonPrimitive?.contentOrNull to e["message"]?.jsonPrimitive?.contentOrNull
                is JsonPrimitive -> null to e.contentOrNull
                else -> null to null
            }
        }.getOrDefault(null to null)
    }
}

/**
 * The engine for ONE user: fetches the Clerk token, and retries once with a fresh one on 401.
 *
 * It is bound to the user it was created for. The auth state is shared, so a request still running for user A after
 * the phone switched to user B would otherwise pick up B's token and write A's days into B's account. Every call
 * checks that the signed-in user is still [owner], and fails as unauthorized (sending nothing) when it isn't.
 */
class Engine(
    private val api: RetroApi,
    val owner: String,
    private val currentUser: () -> String?,
    private val router: RetroApi = RetroApi(BuildConfig.ROUTER_BASE_URL),
    private val token: suspend (skipCache: Boolean) -> String?,
) : EngineApi {
    val cacheScope: String get() = api.baseUrl
    val isCurrentOwner: Boolean get() = currentUser() == owner

    suspend fun uploadPhoto(id: String, bytes: ByteArray): Api<org.nighthawklabs.retro.data.WardrobeMediaResult> {
        val path = org.nighthawklabs.retro.data.WardrobeMediaPath.path(id) ?: return Api.Failed("invalid_input", "Invalid photo identity.")
        return authenticated { token ->
            when (val response = api.photoRequest("PUT", path, token, bytes)) {
                is Api.Ok -> runCatching { Api.Ok(ApiJson.decodeFromString<org.nighthawklabs.retro.data.WardrobeMediaResult>(response.value.toString(Charsets.UTF_8))) }.getOrElse { Api.Retry("unreadable response") }
                else -> response.failure()!!
            }
        }
    }

    suspend fun photo(id: String, variant: String): Api<ByteArray> {
        val path = org.nighthawklabs.retro.data.WardrobeMediaPath.path(id, variant) ?: return Api.Failed("invalid_input", "Invalid photo identity.")
        return authenticated { api.photoRequest("GET", path, it) }
    }
    override suspend fun <I, O> call(op: String, input: I, inSer: KSerializer<I>, outSer: KSerializer<O>): Api<O> {
        return authenticated { api.call(op, input, inSer, outSer, it) }
    }

    suspend fun onboardingStatus(): Api<OnboardingProgress> {
        val status: Api<OnboardingProgress> = authenticated {
            router.request("GET", "/onboard", null, it) { text -> ApiJson.decodeFromString<OnboardingProgress>(text) }
        }
        if (status is Api.Failed && status.message == "no onboarding request found") {
            // Temporal history can expire; an existing workspace must never be provisioned again because of that.
            val health: Api<Boolean> = authenticated { router.request("GET", "/gateway/healthz", null, it) { true } }
            return when (health) {
                is Api.Ok -> Api.Ok(OnboardingProgress("completed"))
                Api.NotProvisioned -> status
                else -> health.failure()!!
            }
        }
        return status
    }

    suspend fun startOnboarding(request: OnboardingRequest): Api<OnboardingAccepted> = authenticated {
        router.request("POST", "/onboard", ApiJson.encodeToString(serializer(), request), it) { text -> ApiJson.decodeFromString<OnboardingAccepted>(text) }
    }

    private suspend fun <O> authenticated(send: suspend (String) -> Api<O>): Api<O> {
        if (currentUser() != owner) return Api.Unauthorized
        val t = token(false) ?: return Api.Unauthorized
        if (currentUser() != owner) return Api.Unauthorized
        val r = send(t)
        if (currentUser() != owner) return Api.Unauthorized
        if (r is Api.Unauthorized && currentUser() == owner) {
            token(true)?.let { fresh ->
                if (currentUser() == owner) {
                    val refreshed = send(fresh)
                    return if (currentUser() == owner) refreshed else Api.Unauthorized
                }
            }
        }
        return r
    }

    companion object {
        fun live(owner: String, currentUser: () -> String?): Engine = Engine(
            RetroApi((DevMode.engineUrl ?: (BuildConfig.ROUTER_BASE_URL.trimEnd('/') + "/retro")) + "/api/v1"),
            owner,
            currentUser,
        ) { skipCache -> org.nighthawklabs.retro.auth.Auth.token(skipCache) }
    }
}
