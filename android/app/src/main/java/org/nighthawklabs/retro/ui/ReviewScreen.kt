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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.Day
import org.nighthawklabs.retro.data.Entry
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular

/**
 * Review: how it is actually going. A widening lens — the week, then the patterns, then the days themselves.
 *
 * This is the surface where a productivity app usually turns into a report card. It does not here: every reading is
 * stated as a fact about days that happened, and a day that went badly is drawn exactly like a day that did not
 * happen, because neither is a failure to be corrected.
 */
@Composable
fun ReviewScreen(
    entries: List<Entry>,
    day: Day,
    onRecord: (String) -> Unit,
    onSave: (Entry) -> Unit,
) {
    val tok = Retro.tok
    var editing by remember { mutableStateOf<Entry?>(null) }

    editing?.let { open ->
        EntryEditor(
            entry = open,
            onBack = { editing = null },
            onSave = { updated -> onSave(updated); editing = null },
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
        Text(
            "Review",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = tok.ink,
            modifier = Modifier.padding(top = 48.dp, bottom = 4.dp),
        )

        Panel {
            SectionHeading("This week", "${day.week.count { it.kept >= 1.0 }} of 7 days")
            WeekStrip(days = day.week, today = day.week.lastOrNull()?.id ?: "")
        }

        Panel {
            SectionHeading("When it holds", null)
            val shapes = byWeekday(entries)
            Row(
                modifier = Modifier.fillMaxWidth().height(84.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                shapes.forEach { pair ->
                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height((64 * pair.share).dp.coerceAtLeast(6.dp))
                                .clip(RoundedCornerShape(5.dp))
                                .background(if (pair.share > 0) tok.sage.copy(alpha = 0.45f + 0.55f * pair.share.toFloat()) else tok.sand),
                        )
                        Text(pair.letter, fontSize = 11.sp, color = tok.stone, modifier = Modifier.padding(top = 6.dp))
                    }
                }
            }
            Text(reading(entries), fontSize = 12.sp, color = tok.stone)
        }

        Panel {
            SectionHeading("The days", "${entries.count { !it.cancelled }} recorded")
            Column {
                entries.forEachIndexed { index, entry ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { editing = entry }
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(modifier = Modifier.padding(end = 0.dp)) {
                            Text(entry.weekday, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = tok.ink)
                            Text(entry.dayLabel, style = Tabular.copy(fontSize = 11.sp), color = tok.stone)
                        }
                        if (entry.cancelled) {
                            Text("Void — kept, not counted", fontSize = 14.sp, color = tok.rust, modifier = Modifier.weight(1f))
                        } else {
                            Text(
                                entry.text.ifEmpty { "Nothing written." },
                                fontSize = 14.sp,
                                color = if (entry.text.isEmpty()) tok.stone else tok.ink,
                                maxLines = 2,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        entry.mood?.let { mood ->
                            Box(modifier = Modifier.size(width = 34.dp, height = 8.dp)) { MoodDots(mood) }
                        }
                    }
                    if (index < entries.lastIndex) {
                        Box(modifier = Modifier.padding(start = 58.dp).height(1.dp).fillMaxWidth().background(tok.rule))
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

private data class WeekShape(val letter: String, val share: Double)

/** Which days of the week actually work, read off the record rather than from an opinion about the record. */
private fun byWeekday(entries: List<Entry>): List<WeekShape> {
    val letters = listOf("M", "T", "W", "T", "F", "S", "S")
    // Calendar.MONDAY..SUNDAY, so the strip reads Monday-first like the rest of the app.
    val order = listOf(2, 3, 4, 5, 6, 7, 1)
    val recorded = entries.filter { !it.cancelled }
    return order.mapIndexed { index, weekday ->
        val onThisDay = recorded.filter {
            java.util.Calendar.getInstance().apply { time = it.date }.get(java.util.Calendar.DAY_OF_WEEK) == weekday
        }
        val share = if (onThisDay.isEmpty()) 0.0
        else onThisDay.count { (it.mood ?: 0) >= 3 }.toDouble() / onThisDay.size
        WeekShape(letters[index], share)
    }
}

private fun reading(entries: List<Entry>): String {
    val shapes = byWeekday(entries)
    val best = shapes.maxByOrNull { it.share } ?: return "Not enough recorded yet to see a shape."
    if (best.share <= 0.0) return "Not enough recorded yet to see a shape."
    val names = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    val index = shapes.indexOf(best)
    return "${names[index]} is the day this tends to hold. The record says so, not the plan."
}

/** The record for one day. Writing it should feel like closing a loop, not filling in a form. */
@Composable
private fun EntryEditor(entry: Entry, onBack: () -> Unit, onSave: (Entry) -> Unit) {
    val tok = Retro.tok
    var text by remember { mutableStateOf(entry.text) }
    var mood by remember { mutableStateOf(entry.mood) }
    var cancelled by remember { mutableStateOf(entry.cancelled) }

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
            Text("The record", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = tok.ink)
            Box(modifier = Modifier.weight(1f))
            Text(
                "Save",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = tok.clay,
                modifier = Modifier
                    .clickable { onSave(entry.copy(text = text, mood = mood, cancelled = cancelled)) }
                    .padding(8.dp),
            )
        }

        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column {
                Text(entry.date.let { java.text.SimpleDateFormat("EEEE", java.util.Locale.US).format(it) }, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = tok.clay)
                Text(
                    entry.date.let { java.text.SimpleDateFormat("d MMMM yyyy", java.util.Locale.US).format(it) },
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    color = tok.ink,
                )
            }

            TextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("What happened", color = tok.stone) },
                minLines = 6,
                shape = RoundedCornerShape(12.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = tok.sand,
                    unfocusedContainerColor = tok.sand,
                    focusedIndicatorColor = tok.clay,
                    unfocusedIndicatorColor = tok.rule,
                ),
            )

            Panel {
                SectionHeading("How it felt", mood?.let { "$it of 5" })
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    (1..5).forEach { step ->
                        Box(
                            modifier = Modifier
                                .size(30.dp)
                                .clip(CircleShape)
                                .background(if (step <= (mood ?: 0)) tok.clay else tok.sand)
                                .clickable { mood = if (mood == step) null else step },
                        )
                    }
                }
            }

            Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Mark this day void", fontSize = 16.sp, fontWeight = FontWeight.Medium, color = tok.ink)
                        Text("The day is kept and will not count. Nothing is deleted.", fontSize = 12.sp, color = tok.stone)
                    }
                    Switch(
                        checked = cancelled,
                        onCheckedChange = { cancelled = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = tok.rust),
                    )
                }
            }
        }
    }
}
