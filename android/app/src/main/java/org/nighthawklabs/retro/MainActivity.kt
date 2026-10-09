package org.nighthawklabs.retro

import android.os.Bundle
import android.content.Intent
import org.nighthawklabs.retro.data.WardrobeEntryRequest
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.auth.Auth
import org.nighthawklabs.retro.auth.AuthState
import org.nighthawklabs.retro.ui.AppRoot
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.RetroTheme

class MainActivity : ComponentActivity() {
    private var entryRequest by mutableStateOf<WardrobeEntryRequest?>(null)
    private fun consumeEntry() {
        entryRequest = null
        intent.action = Intent.ACTION_MAIN
        intent.removeExtra("wardrobe_query")
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        WardrobeEntryRequest.parse(intent.action, intent.getStringExtra("wardrobe_query"))?.let { entryRequest = it }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        entryRequest = WardrobeEntryRequest.parse(intent.action, intent.getStringExtra("wardrobe_query"))
        DevMode.configure(
            engine = intent.getStringExtra("dev_engine"),
            hour = intent.getStringExtra("dev_hour")?.toIntOrNull(),
            surface = intent.getStringExtra("dev_tab"),
        )
        enableEdgeToEdge()
        setContent {
            RetroTheme {
                var showAccount by remember { mutableStateOf(false) }
                AppRoot(onOpenAccount = { showAccount = true }, entryRequest = entryRequest, onEntryConsumed = ::consumeEntry)
                if (showAccount) {
                    AccountSheet(onDismiss = { showAccount = false })
                }
            }
        }
    }
}

/** Account: a sheet for a self-contained task, with the platform's own dismissal. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountSheet(onDismiss: () -> Unit) {
    val tok = Retro.tok
    val sheetState = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()
    val state by Auth.state.collectAsState()
    val email = (state as? AuthState.SignedIn)?.email

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = tok.paper) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("Signed in", fontSize = 13.sp, color = tok.stone)
            Text(email ?: "Your account", fontSize = 16.sp, color = tok.ink)
            TextButton(
                onClick = {
                    scope.launch {
                        Auth.signOut()
                        sheetState.hide()
                        onDismiss()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Sign out", color = tok.rust, fontSize = 16.sp)
            }
        }
    }
}
