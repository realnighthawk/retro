package org.nighthawklabs.retro.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.DevMode
import org.nighthawklabs.retro.data.Day
import org.nighthawklabs.retro.data.DemoData
import org.nighthawklabs.retro.data.Garment
import org.nighthawklabs.retro.data.Goal
import org.nighthawklabs.retro.ui.theme.Retro

/** The app's five surfaces, each with one job. The order is the order of a day. */
enum class DemoSurface(val title: String, val icon: ImageVector) {
    Today("Today", Icons.Filled.WbSunny),
    Goals("Goals", Icons.Filled.TrackChanges),
    Wardrobe("Wardrobe", Icons.Filled.Checkroom),
    Review("Review", Icons.Filled.Insights),
    You("You", Icons.Filled.Person);

    companion object {
        /** Where the shell opens: Today unless a DEBUG launch extra says otherwise. */
        fun startingOn(): DemoSurface {
            val name = DevMode.surface ?: return Today
            return entries.firstOrNull { it.name.equals(name, ignoreCase = true) } ?: Today
        }
    }
}

/** One goal, toggled. The streak and the history move with the tick, because they are the same fact. */
private fun List<Goal>.toggled(id: String): List<Goal> = map { goal ->
    if (goal.id != id) {
        goal
    } else {
        val nowDone = !goal.done
        goal.copy(
            done = nowDone,
            streak = if (nowDone) goal.streak + 1 else maxOf(0, goal.streak - 1),
            history = if (nowDone) goal.history + true else goal.history.dropLast(1),
        )
    }
}

/**
 * The signed-in shell. Owns the day, because every surface reads or writes it, and owns the one place a thought can be
 * captured from anywhere — the moment you have to navigate to record something, you have lost it.
 */
@Composable
fun ProductivityDemoShell(onOpenAccount: () -> Unit) {
    val tok = Retro.tok
    var surface by remember { mutableStateOf(DemoSurface.startingOn()) }
    var day by remember { mutableStateOf(DemoData.today(DevMode.demoHour)) }
    var goals by remember { mutableStateOf(DemoData.goals) }
    val wardrobe: List<Garment> = DemoData.wardrobe
    var entries by remember { mutableStateOf(DemoData.entries) }
    var capturing by remember { mutableStateOf(false) }

    fun toggleGoal(id: String) {
        goals = goals.toggled(id)
        day = day.copy(goals = goals)
    }

    Box(modifier = Modifier.fillMaxSize().background(tok.bone)) {
        when (surface) {
            DemoSurface.Today -> TodayScreen(
                day = day,
                daysGoals = goals,
                wardrobe = wardrobe,
                onToggleFocus = { day.focusGoalID?.let { toggleGoal(it) } },
                onToggleAgenda = { id ->
                    day = day.copy(agenda = day.agenda.map { if (it.id == id) it.copy(done = !it.done) else it })
                },
                onOpenWardrobe = { surface = DemoSurface.Wardrobe },
                onOpenReview = { surface = DemoSurface.Review },
            )

            DemoSurface.Goals -> GoalsScreen(
                goals = goals,
                onToggle = { goal -> toggleGoal(goal.id) },
                onCadence = { goal, cadence ->
                    goals = goals.map { if (it.id == goal.id) it.copy(cadence = cadence) else it }
                },
                onNote = { goal, note ->
                    goals = goals.map { if (it.id == goal.id) it.copy(note = note) else it }
                },
            )

            DemoSurface.Wardrobe -> WardrobeScreen(
                wardrobe = wardrobe,
                day = day,
                onWear = { ids -> day = day.copy(outfit = day.outfit.copy(garmentIDs = ids)) },
            )

            DemoSurface.Review -> ReviewScreen(
                entries = entries,
                day = day,
                onRecord = { day = day.copy(record = it) },
                onSave = { updated -> entries = entries.map { if (it.id == updated.id) updated else it } },
            )

            DemoSurface.You -> YouScreen(
                goals = goals,
                wardrobe = wardrobe,
                entries = entries,
                onOpenAccount = onOpenAccount,
            )
        }

        NavigationBar(
            containerColor = tok.paper,
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            DemoSurface.entries.forEach { candidate ->
                NavigationBarItem(
                    selected = surface == candidate,
                    onClick = { surface = candidate },
                    icon = { Icon(candidate.icon, contentDescription = null, modifier = Modifier.size(20.dp)) },
                    label = { Text(candidate.title, fontSize = 11.sp, fontWeight = FontWeight.Medium) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = tok.clay,
                        selectedTextColor = tok.clay,
                        indicatorColor = tok.wash(tok.clay),
                        unselectedIconColor = tok.stone,
                        unselectedTextColor = tok.stone,
                    ),
                )
            }
        }

        // One control, on every surface, for the thought you had while doing something else.
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 20.dp, bottom = 96.dp)
                .size(56.dp)
                .clip(CircleShape)
                .background(Brush.verticalGradient(listOf(tok.clay, tok.clay.copy(alpha = 0.86f))))
                .clickable(onClickLabel = "Capture") { capturing = true },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = tok.paper, modifier = Modifier.size(24.dp))
        }
    }

    if (capturing) {
        CaptureSheet(
            goals = goals,
            wardrobe = wardrobe,
            onTick = { id -> toggleGoal(id) },
            onNote = { text ->
                day = day.copy(record = if (day.record.isEmpty()) text else day.record + "\n" + text)
            },
            onWear = { ids -> day = day.copy(outfit = day.outfit.copy(garmentIDs = ids)) },
            onDismiss = { capturing = false },
        )
    }
}
