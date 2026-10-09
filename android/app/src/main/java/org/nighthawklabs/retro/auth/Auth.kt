package org.nighthawklabs.retro.auth

import android.content.Context
import android.util.Log
import com.clerk.api.Clerk
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.session.GetTokenOptions
import com.clerk.api.sso.OAuthProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.BuildConfig
import org.nighthawklabs.retro.DevMode
import org.nighthawklabs.retro.data.WardrobeReadCache
import kotlinx.coroutines.withContext

private const val TAG = "Auth"

sealed interface AuthState {
    data object Loading : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val userId: String, val email: String?) : AuthState
}

/**
 * Identity for the whole app: Clerk, the same instance the router verifies. There is no guest mode — the days live on
 * the server, so a signed-out app has nothing to show.
 */
object Auth {
    private var applicationContext: Context? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    /** Clerk could not finish starting (offline first launch): show sign-in rather than a blank screen. */
    private val loadTimedOut = MutableStateFlow(false)

    val state: StateFlow<AuthState> by lazy {
        combine(Clerk.isInitialized, Clerk.userFlow, loadTimedOut) { ready, user, timedOut ->
            when {
                DevMode.engineUrl != null -> AuthState.SignedIn(DevMode.USER, "dev@local")
                user != null -> AuthState.SignedIn(user.id, user.primaryEmailAddress?.emailAddress)
                ready || timedOut -> AuthState.SignedOut
                else -> AuthState.Loading
            }
        }.stateIn(scope, SharingStarted.Eagerly, AuthState.Loading)
    }

    /** Call once from Application.onCreate. Clerk initialises in the background. */
    fun init(context: Context) {
        applicationContext = context.applicationContext
        Clerk.initialize(context.applicationContext, BuildConfig.CLERK_PUBLISHABLE_KEY)
        scope.launch { delay(8_000); loadTimedOut.value = true }
    }

    /** Opens Google sign-in. Returns an error message to show, or null on success. */
    suspend fun signInWithGoogle(): String? {
        if (DevMode.engineUrl != null) return null
        return when (val r = Clerk.auth.signInWithOAuth(OAuthProvider.GOOGLE)) {
            is ClerkResult.Success -> null
            is ClerkResult.Failure -> {
                Log.w(TAG, "Google sign-in failed: ${r.error} ${r.throwable}")
                "Couldn't sign in with Google. Check your connection and try again."
            }
        }
    }

    suspend fun signOut() {
        if (DevMode.engineUrl != null) return
        val owner = (state.value as? AuthState.SignedIn)?.userId
        Clerk.auth.signOut()
        if (owner != null) withContext(Dispatchers.IO) {
            applicationContext?.let { WardrobeReadCache(it.cacheDir, owner, "").clear() }
        }
    }

    /** A session token for the router, or null when signed out or offline. [skipCache] forces a fresh one. */
    suspend fun token(skipCache: Boolean = false): String? {
        if (DevMode.engineUrl != null) return "dev"
        return when (val r = Clerk.auth.getToken(GetTokenOptions(skipCache = skipCache))) {
            is ClerkResult.Success -> r.value
            is ClerkResult.Failure -> {
                Log.w(TAG, "getToken failed: ${r.error} ${r.throwable}")
                null
            }
        }
    }
}
