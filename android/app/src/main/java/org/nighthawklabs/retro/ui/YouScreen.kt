package org.nighthawklabs.retro.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.Entry
import org.nighthawklabs.retro.data.Garment
import org.nighthawklabs.retro.data.Goal
import org.nighthawklabs.retro.ui.theme.Retro

/** You: the system itself, and the only place the app talks about the app. */
@Composable
fun YouScreen(
    goals: List<Goal>,
    wardrobe: List<Garment>,
    entries: List<Entry>,
    onOpenAccount: () -> Unit,
) {
    val tok = Retro.tok
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(tok.bone)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(
            "You",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = tok.ink,
            modifier = Modifier.padding(top = 48.dp, bottom = 4.dp),
        )

        Panel(tint = tok.clay) {
            SectionHeading("What Retro knows", null)
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Stat("${goals.size}", "goals")
                Stat("${wardrobe.size}", "pieces")
                Stat("${entries.count { !it.cancelled }}", "days recorded")
            }
            Text("All of it on this device. The /retro engine is not connected yet.", fontSize = 12.sp, color = tok.stone)
        }

        Panel {
            SectionHeading("How it reads your days", null)
            Reading("A missed day is drawn flat", "Never red. The app is not allowed to be disappointed in you.")
            Reading("A void day is kept, not deleted", "Some days should not count. They still exist in the record.")
            Reading("Numbers are readings, not scores", "A streak describes what happened. It is not something to protect.")
            Reading("One thing gets the weight", "Everything else on Today is deliberately quieter than the one thing.")
        }

        Panel(modifier = Modifier.clickable(onClickLabel = "Open account", onClick = onOpenAccount)) {
            SectionHeading("Account", null)
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Your account", fontSize = 16.sp, color = tok.ink)
            }
        }

        Column(modifier = Modifier.padding(bottom = 40.dp)) {
            Text("Example content. The /retro engine is not connected yet.", fontSize = 12.sp, color = tok.stone)
        }
    }
}

@Composable
private fun Reading(title: String, detail: String) {
    val tok = Retro.tok
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = tok.ink)
        Text(detail, fontSize = 12.sp, color = tok.stone)
    }
}
