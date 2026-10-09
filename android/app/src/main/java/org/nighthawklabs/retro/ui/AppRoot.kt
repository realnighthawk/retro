package org.nighthawklabs.retro.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import org.nighthawklabs.retro.data.WardrobeEntryRequest
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.DevMode
import org.nighthawklabs.retro.auth.Auth
import org.nighthawklabs.retro.auth.AuthState
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.onboarding.ProvisionGate

/**
 * The whole app branches on one thing: who is signed in. A different user is a screen, never a reused one.
 */
@Composable
fun AppRoot(onOpenAccount: () -> Unit, entryRequest: WardrobeEntryRequest? = null, onEntryConsumed: () -> Unit = {}) {
    val tok = Retro.tok
    val state by Auth.state.collectAsState()
    val owner = (state as? AuthState.SignedIn)?.userId
    var previousOwner by remember { mutableStateOf(owner) }
    LaunchedEffect(owner) {
        if (previousOwner != null && owner != previousOwner) onEntryConsumed()
        previousOwner = owner
    }

    Box(modifier = Modifier.fillMaxSize().background(tok.bone)) {
        when (state) {
            AuthState.Loading -> Loading()
            AuthState.SignedOut -> Welcome()
            is AuthState.SignedIn -> {
                val userId = (state as AuthState.SignedIn).userId
                key(userId) { ProvisionGate(userId) { AppShell(userId = userId, onOpenAccount = onOpenAccount, entryRequest = entryRequest, onEntryConsumed = onEntryConsumed) } }
            }
        }
    }
}

@Composable
private fun Loading() {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = Retro.tok.clay)
    }
}

/** Sign-in. One quiet screen: the mark, what the app is for, and one action. */
@Composable
private fun Welcome() {
    val tok = Retro.tok
    val scope = rememberCoroutineScope()
    var problem by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(tok.heroTop, tok.heroBottom))),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 26.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            RetroMark(size = 78.dp)

            Text(
                "Retro",
                fontSize = 52.sp,
                lineHeight = 58.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-1.2).sp,
                color = tok.ink,
                modifier = Modifier.padding(top = 22.dp),
            )

            Text(
                "Your wardrobe, today's outfit, and a dependable history of what you wore.",
                fontSize = 16.sp,
                color = tok.stone,
                modifier = Modifier.padding(top = 10.dp),
            )

            problem?.let {
                Text(it, fontSize = 13.sp, color = tok.rust, modifier = Modifier.padding(top = 18.dp))
            }

            Button(
                onClick = {
                    scope.launch {
                        working = true
                        problem = Auth.signInWithGoogle()
                        working = false
                    }
                },
                enabled = !working,
                modifier = Modifier.fillMaxWidth().padding(top = 28.dp),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(15.dp),
                colors = ButtonDefaults.buttonColors(containerColor = tok.clay, contentColor = tok.paper),
            ) {
                Text("Continue with Google", fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(vertical = 8.dp))
            }

            Text(
                "Your records stay yours. Nothing is shared.",
                fontSize = 12.sp,
                color = tok.stone,
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
            )
        }
    }
}
