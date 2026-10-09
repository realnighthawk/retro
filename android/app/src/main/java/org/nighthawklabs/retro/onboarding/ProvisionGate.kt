package org.nighthawklabs.retro.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.DevMode
import org.nighthawklabs.retro.auth.Auth
import org.nighthawklabs.retro.auth.AuthState
import org.nighthawklabs.retro.net.Engine
import org.nighthawklabs.retro.ui.RetroMark
import org.nighthawklabs.retro.ui.theme.Retro

@Composable
fun ProvisionGate(userId: String, content: @Composable () -> Unit) {
    if (DevMode.engineUrl != null) { content(); return }
    val model = remember(userId) {
        val engine = Engine.live(userId) { (Auth.state.value as? AuthState.SignedIn)?.userId }
        OnboardingModel(engine::onboardingStatus, engine::startOnboarding)
    }
    val scope = rememberCoroutineScope()
    LaunchedEffect(model) { model.refresh() }
    LaunchedEffect(model.phase) { if (model.phase == OnboardingModel.Phase.Provisioning) model.watch() }
    if (model.phase == OnboardingModel.Phase.Ready) { content(); return }
    val tok = Retro.tok
    val waiting = model.phase in listOf(OnboardingModel.Phase.Checking, OnboardingModel.Phase.Provisioning)
    Column(Modifier.fillMaxSize().background(tok.bone).padding(26.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically)) {
        RetroMark(size = 72.dp)
        Text(when (model.phase) {
            OnboardingModel.Phase.Checking -> "Checking your workspace"
            OnboardingModel.Phase.Provisioning -> "Setting up your workspace"
            else -> "Your space for Retro"
        },
            fontSize = 24.sp, fontWeight = FontWeight.Bold, color = tok.ink, textAlign = TextAlign.Center)
        if (waiting) {
            CircularProgressIndicator(color = tok.clay)
            if (model.phase == OnboardingModel.Phase.Provisioning) {
                Text("You can leave and come back. Setup will carry on.", color = tok.stone, textAlign = TextAlign.Center)
            }
        } else {
            Text("Create your private workspace, shared with your other Nighthawk apps.", color = tok.stone, textAlign = TextAlign.Center)
            Button(onClick = { scope.launch { if (model.phase == OnboardingModel.Phase.Unavailable) model.refresh() else model.start() } },
                enabled = !model.working, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = tok.clay, contentColor = tok.paper)) {
                Text(when (model.phase) {
                    OnboardingModel.Phase.Failed -> "Try setup again"
                    OnboardingModel.Phase.Unavailable -> "Check setup again"
                    else -> "Create my workspace"
                }, Modifier.padding(vertical = 8.dp))
            }
        }
        model.problem?.let { Text(it, color = tok.rust, textAlign = TextAlign.Center) }
        TextButton(onClick = { scope.launch { Auth.signOut() } }) { Text("Sign out", color = tok.stone) }
    }
}
