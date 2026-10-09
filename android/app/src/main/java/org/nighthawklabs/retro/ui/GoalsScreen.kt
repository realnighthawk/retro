package org.nighthawklabs.retro.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.Area
import org.nighthawklabs.retro.data.Cadence
import org.nighthawklabs.retro.data.Goal
import org.nighthawklabs.retro.ui.theme.HeroStyle
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular

/** Goals: the long game. Grouped by the part of life they belong to, because that is how a person remembers them. */
@Composable
fun GoalsScreen(
    goals: List<Goal>,
    onToggle: (Goal) -> Unit,
    onCadence: (Goal, Cadence) -> Unit,
    onNote: (Goal, String) -> Unit,
) {
    val tok = Retro.tok
    var open by remember { mutableStateOf<Goal?>(null) }

    val detail = open
    if (detail != null) {
        GoalDetailScreen(
            goal = goals.firstOrNull { it.id == detail.id } ?: detail,
            onBack = { open = null },
            onCadence = onCadence,
            onNote = onNote,
            onToggle = onToggle,
        )
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(tok.bone)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text("Goals", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = tok.ink, modifier = Modifier.padding(top = 48.dp, bottom = 4.dp))

        Panel(tint = tok.sage) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("${goals.count { it.done }}", style = HeroStyle.copy(fontSize = 38.sp), color = tok.ink)
                Text("/ ${goals.size} kept today", fontSize = 15.sp, color = tok.stone, modifier = Modifier.padding(bottom = 8.dp))
            }
            Text(
                "${goals.maxOfOrNull { it.streak } ?: 0} days is your longest run right now.",
                fontSize = 14.sp,
                color = tok.stone,
            )
        }

        Area.entries.forEach { area ->
            val inArea = goals.filter { it.area == area }
            if (inArea.isNotEmpty()) {
                Panel {
                    SectionHeading(area.title, "${inArea.count { it.done }} of ${inArea.size}")
                    Column {
                        inArea.forEachIndexed { index, goal ->
                            GoalRow(
                                goal = goal,
                                onToggle = { onToggle(goal) },
                                onOpen = { open = goal },
                            )
                            if (index < inArea.lastIndex) {
                                Box(
                                    modifier = Modifier
                                        .padding(start = 44.dp)
                                        .height(1.dp)
                                        .fillMaxWidth()
                                        .background(tok.rule)
                                )
                            }
                        }
                    }
                }
            }
        }

        Text(
            "Example content. The /retro engine is not connected yet.",
            fontSize = 12.sp,
            color = tok.stone,
            modifier = Modifier.padding(bottom = 40.dp),
        )
    }
}

/** One goal, in full: the whole run rather than the recent tail, what it is for, and how often it is meant to happen. */
@Composable
private fun GoalDetailScreen(
    goal: Goal,
    onBack: () -> Unit,
    onCadence: (Goal, Cadence) -> Unit,
    onNote: (Goal, String) -> Unit,
    onToggle: (Goal) -> Unit,
) {
    val tok = Retro.tok
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(tok.bone)
            .verticalScroll(rememberScrollState()),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 44.dp, start = 6.dp, end = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = tok.ink)
            }
            Text(goal.title, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = tok.ink, maxLines = 1)
        }

        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Panel(tint = if (goal.done) tok.sage else tok.clay) {
                Text(
                    goal.title,
                    fontSize = 24.sp,
                    lineHeight = 30.sp,
                    fontWeight = FontWeight.Bold,
                    color = tok.ink,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                    Stat("${goal.streak}", "days running")
                    Stat("${goal.keptRecently}", "of last 30")
                    Stat(goal.cadence.title, "cadence")
                }
            }

            Panel {
                SectionHeading("The run", "8 weeks")
                // Eight days to a row, oldest first. A gap is a gap: drawn recessed, never as a failure.
                LazyVerticalGrid(
                    columns = GridCells.Fixed(8),
                    modifier = Modifier.height(210.dp),
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    items(goal.history.takeLast(56)) { kept ->
                        Box(
                            modifier = Modifier
                                .height(26.dp)
                                .background(if (kept) tok.sage else tok.sand, RoundedCornerShape(3.dp))
                        )
                    }
                }
                Text(
                    "${goal.keptRecently} of the last 30 days. The grey squares are days that did not happen, which is different from days that went badly.",
                    fontSize = 12.sp,
                    color = tok.stone,
                )
            }

            Panel {
                SectionHeading("Why", null)
                TextField(
                    value = goal.note,
                    onValueChange = { onNote(goal, it) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Why this matters", color = tok.stone) },
                    shape = RoundedCornerShape(12.dp),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = tok.sand,
                        unfocusedContainerColor = tok.sand,
                        focusedIndicatorColor = tok.clay,
                        unfocusedIndicatorColor = tok.rule,
                    ),
                )
            }

            Panel {
                SectionHeading("How often", null)
                Column {
                    listOf(
                        Cadence.Daily,
                        Cadence.Weekdays,
                        Cadence.TimesPerWeek(3),
                        Cadence.TimesPerWeek(2),
                    ).forEach { candidate ->
                        val active = candidate.title == goal.cadence.title
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onCadence(goal, candidate) }
                                .padding(vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                candidate.title,
                                fontSize = 16.sp,
                                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                                color = if (active) tok.clay else tok.ink,
                            )
                            Box(modifier = Modifier.weight(1f))
                            if (active) Text("·", fontSize = 20.sp, color = tok.clay)
                        }
                    }
                }
            }

            Panel {
                DoneButton(onToggle = { onToggle(goal) }, done = goal.done, streak = goal.streak)
            }
        }
    }
}

@Composable
private fun DoneButton(onToggle: () -> Unit, done: Boolean, streak: Int) {
    val tok = Retro.tok
    androidx.compose.material3.Button(
        onClick = onToggle,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(15.dp),
        colors = androidx.compose.material3.ButtonDefaults.buttonColors(
            containerColor = tok.clay,
            contentColor = tok.paper,
        ),
    ) {
        Text(
            if (done) "Undo today" else "Done for today · $streak day run",
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(vertical = 8.dp),
        )
    }
}
