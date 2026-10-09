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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.Garment
import org.nighthawklabs.retro.data.Goal
import org.nighthawklabs.retro.ui.theme.Retro

/**
 * Capture: the three things worth interrupting yourself for, at most two taps from any surface.
 *
 * Deliberately not a general-purpose composer. If recording something takes longer than the thought took, the app has
 * made the owner worse at their day, not better.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaptureSheet(
    goals: List<Goal>,
    wardrobe: List<Garment>,
    onTick: (String) -> Unit,
    onNote: (String) -> Unit,
    onWear: (List<String>) -> Unit,
    onDismiss: () -> Unit,
) {
    val tok = Retro.tok
    var mode by remember { mutableStateOf(Mode.Choose) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(),
        containerColor = tok.bone,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                when (mode) {
                    Mode.Choose -> "Capture"
                    Mode.Tick -> "Tick a goal"
                    Mode.Note -> "Note the day"
                    Mode.Wear -> "What I wore"
                },
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                color = tok.ink,
            )

            when (mode) {
                Mode.Choose -> {
                    Choice("Tick a goal") { mode = Mode.Tick }
                    Choice("Note the day") { mode = Mode.Note }
                    Choice("Log what I wore") { mode = Mode.Wear }
                }

                Mode.Tick -> goals.forEach { goal ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onTick(goal.id) }
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        TickBox(done = goal.done)
                        Text(
                            goal.title,
                            fontSize = 16.sp,
                            color = if (goal.done) tok.stone else tok.ink,
                            textDecoration = if (goal.done) TextDecoration.LineThrough else null,
                        )
                    }
                }

                Mode.Note -> NoteComposer { text -> onNote(text); onDismiss() }

                Mode.Wear -> {
                    var picked by remember { mutableStateOf(emptyList<String>()) }
                    Column(
                        modifier = Modifier.height(320.dp).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        wardrobe.forEach { garment ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        picked = if (picked.contains(garment.id)) picked - garment.id
                                        else {
                                            val others = wardrobe.filter { it.slot == garment.slot }.map { it.id }
                                            picked.filterNot { it in others } + garment.id
                                        }
                                    }
                                    .padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Box(modifier = Modifier.size(width = 28.dp, height = 28.dp)) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .background(garment.tone.color, RoundedCornerShape(7.dp))
                                    )
                                }
                                Text(garment.name, fontSize = 15.sp, color = tok.ink)
                                Box(modifier = Modifier.weight(1f))
                                if (picked.contains(garment.id)) {
                                    Text("·", fontSize = 20.sp, color = tok.clay)
                                }
                            }
                        }
                    }
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = picked.isNotEmpty()) { onWear(picked); onDismiss() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "Wear this",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (picked.isEmpty()) tok.stone else tok.clay,
                            modifier = Modifier.padding(vertical = 12.dp),
                        )
                    }
                }
            }
        }
    }
}

private enum class Mode { Choose, Tick, Note, Wear }

@Composable
private fun Choice(label: String, onClick: () -> Unit) {
    val tok = Retro.tok
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(tok.paper, RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(16.dp),
    ) {
        Text(label, fontSize = 16.sp, fontWeight = FontWeight.Medium, color = tok.ink)
    }
}

@Composable
private fun NoteComposer(onAdd: (String) -> Unit) {
    val tok = Retro.tok
    var note by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        TextField(
            value = note,
            onValueChange = { note = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("What happened today", color = tok.stone) },
            minLines = 5,
            shape = RoundedCornerShape(12.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = tok.sand,
                unfocusedContainerColor = tok.sand,
                focusedIndicatorColor = tok.clay,
                unfocusedIndicatorColor = tok.rule,
            ),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = note.isNotBlank()) { onAdd(note.trim()) },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "Add to today's record",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (note.isBlank()) tok.stone else tok.clay,
                modifier = Modifier.padding(vertical = 12.dp),
            )
        }
    }
}
