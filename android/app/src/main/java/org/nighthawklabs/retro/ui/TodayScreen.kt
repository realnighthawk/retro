package org.nighthawklabs.retro.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.AgendaItem
import org.nighthawklabs.retro.data.Day
import org.nighthawklabs.retro.data.Garment
import org.nighthawklabs.retro.data.Goal
import org.nighthawklabs.retro.ui.theme.HeroStyle
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular
import androidx.compose.foundation.shape.RoundedCornerShape

/**
 * Today: what the day is, and the one thing in it.
 *
 * The screen's job is to remove a decision. A person cannot hold four priorities at once, so the app picks the one that
 * matters most this morning and gives it the weight — everything else is available but deliberately quieter.
 */
@Composable
fun TodayScreen(
    day: Day,
    daysGoals: List<Goal>,
    wardrobe: List<Garment>,
    onToggleFocus: () -> Unit,
    onToggleAgenda: (String) -> Unit,
    onOpenWardrobe: () -> Unit,
    onOpenReview: () -> Unit,
) {
    val tok = Retro.tok
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .background(tok.bone),
    ) {
        Hero(day)

        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            day.focus?.let { focus -> FocusPanel(focus, onToggleFocus) }

            Panel {
                SectionHeading("The day", "${day.agenda.count { it.done }} of ${day.agenda.size}")
                Column {
                    day.agenda.forEachIndexed { index, item ->
                        AgendaRow(item) { onToggleAgenda(item.id) }
                        if (index < day.agenda.lastIndex) {
                            Box(
                                modifier = Modifier
                                    .padding(start = 60.dp)
                                    .height(1.dp)
                                    .fillMaxWidth()
                                    .background(tok.rule)
                            )
                        }
                    }
                }
            }

            Panel(modifier = Modifier.clickable(onClickLabel = "Open the wardrobe", onClick = onOpenWardrobe)) {
                SectionHeading("Wearing", day.outfit.summary)
                val worn = day.outfit.garmentIDs.mapNotNull { id -> wardrobe.firstOrNull { it.id == id } }
                if (worn.isEmpty()) {
                    Text(
                        "Nothing picked yet. The wardrobe will suggest something.",
                        fontSize = 14.sp,
                        color = tok.stone,
                    )
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        worn.forEach { garment ->
                            GarmentTile(garment, modifier = Modifier.weight(1f))
                        }
                    }
                }
                Text("Picked at ${day.outfit.pickedAt}", style = Tabular.copy(fontSize = 12.sp), color = tok.stone)
            }

            Panel(modifier = Modifier.clickable(onClickLabel = "Open the record", onClick = onOpenReview)) {
                SectionHeading("Record", null)
                Text(
                    day.record.ifEmpty { "Nothing written yet." },
                    fontSize = 15.sp,
                    color = if (day.record.isEmpty()) tok.stone else tok.ink,
                )
            }

            Text("Example content. The /retro engine is not connected yet.", fontSize = 12.sp, color = tok.stone)
        }
    }
}

@Composable
private fun Hero(day: Day) {
    val tok = Retro.tok
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(tok.heroTop, tok.heroBottom)))
            .statusBarsPadding()
            .padding(top = 24.dp, bottom = 22.dp, start = 18.dp, end = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(day.weekdayLabel, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = tok.clay)
            Text(day.dateLabel, fontSize = 34.sp, fontWeight = FontWeight.Bold, color = tok.ink)
        }

        DayArc(
            progress = day.progress,
            nowLabel = day.nowLabel,
            startLabel = "06:00",
            endLabel = "23:00",
            modifier = Modifier.fillMaxWidth(),
        )

        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("${day.kept}", style = HeroStyle, color = tok.ink)
            Text("/ ${day.total} kept", fontSize = 15.sp, color = tok.stone, modifier = Modifier.padding(bottom = 8.dp))
        }
    }
}

/** The one thing, given the weight. This is the panel the screen exists for. */
@Composable
private fun FocusPanel(goal: Goal, onToggle: () -> Unit) {
    val tok = Retro.tok
    Panel(tint = tok.clay) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("The one thing", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = tok.clay)
            Box(modifier = Modifier.weight(1f))
            Text(goal.cadence.title, fontSize = 12.sp, color = tok.stone)
        }

        Text(
            goal.title,
            fontSize = 26.sp,
            lineHeight = 32.sp,
            fontWeight = FontWeight.Bold,
            color = if (goal.done) tok.stone else tok.ink,
            textDecoration = if (goal.done) TextDecoration.LineThrough else null,
        )

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                "${goal.streak} days running",
                style = Tabular.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium),
                color = if (goal.done) tok.sage else tok.stone,
            )
            HistoryRow(goal.history, days = 12)
        }

        Button(
            onClick = onToggle,
            modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
            shape = RoundedCornerShape(15.dp),
            colors = ButtonDefaults.buttonColors(containerColor = tok.clay, contentColor = tok.paper),
        ) {
            Text(
                if (goal.done) "Undo" else "Done for today",
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun AgendaRow(item: AgendaItem, onToggle: () -> Unit) {
    val tok = Retro.tok
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(item.time, style = Tabular.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium), color = tok.stone)
        Box(
            modifier = Modifier
                .size(7.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(item.kind.colour)
        )
        Text(
            item.title,
            fontSize = 15.sp,
            color = if (item.done) tok.stone else tok.ink,
            textDecoration = if (item.done) TextDecoration.LineThrough else null,
        )
    }
}

/** The dot beside an agenda item: focus is the colour you act in, a fixed commitment is neutral, personal is the garden. */
val AgendaItem.Kind.colour: androidx.compose.ui.graphics.Color
    @Composable get() = when (this) {
        AgendaItem.Kind.Focus -> Retro.tok.clay
        AgendaItem.Kind.Fixed -> Retro.tok.stone
        AgendaItem.Kind.Personal -> Retro.tok.sage
    }
