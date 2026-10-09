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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
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
import org.nighthawklabs.retro.data.Garment
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular

/**
 * The wardrobe: what you own, and what you are wearing today.
 *
 * The top of the screen is the decision, not the inventory. A person opening this in the morning wants to be told
 * something, so the app proposes an outfit from the weather and what has not been worn lately, leaving the full rail
 * underneath for when they disagree.
 */
@Composable
fun WardrobeScreen(wardrobe: List<Garment>, day: Day, onWear: (List<String>) -> Unit) {
    val tok = Retro.tok
    var composing by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<Garment?>(null) }
    var slot by remember { mutableStateOf<Garment.Slot?>(null) }

    detail?.let { open ->
        GarmentDetailScreen(garment = open, onBack = { detail = null })
        return
    }

    if (composing) {
        OutfitComposer(wardrobe = wardrobe, day = day, onWear = onWear, onDismiss = { composing = false })
        return
    }

    val worn = day.outfit.garmentIDs.mapNotNull { id -> wardrobe.firstOrNull { it.id == id } }
    val visible = slot?.let { chosen -> wardrobe.filter { it.slot == chosen } } ?: wardrobe

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(tok.bone)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(
            "Wardrobe",
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = tok.ink,
            modifier = Modifier.padding(top = 48.dp, bottom = 4.dp),
        )

        Panel(tint = if (worn.isEmpty()) tok.clay else null) {
            SectionHeading("Today", day.outfit.summary)
            if (worn.isEmpty()) {
                Text("Nothing picked yet.", fontSize = 15.sp, color = tok.stone)
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    worn.forEach { garment -> GarmentTile(garment, modifier = Modifier.weight(1f)) }
                }
            }
            Button(
                onClick = { composing = true },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(15.dp),
                colors = ButtonDefaults.buttonColors(containerColor = tok.clay, contentColor = tok.paper),
            ) {
                Text(
                    if (worn.isEmpty()) "Pick something" else "Change it",
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            }
        }

        Panel {
            SectionHeading("The rail", "${wardrobe.size} pieces")

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SlotChip("All", slot == null) { slot = null }
                Garment.Slot.entries.forEach { candidate ->
                    SlotChip(candidate.title, slot == candidate) { slot = candidate }
                }
            }

            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 100.dp),
                modifier = Modifier.height(560.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                items(visible) { garment ->
                    Box(modifier = Modifier.clickable { detail = garment }) {
                        GarmentTile(
                            garment = garment,
                            selected = day.outfit.garmentIDs.contains(garment.id),
                        )
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

@Composable
private fun SlotChip(label: String, active: Boolean, onClick: () -> Unit) {
    val tok = Retro.tok
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(if (active) tok.clay else tok.sand)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
    ) {
        Text(
            label,
            fontSize = 14.sp,
            fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
            color = if (active) tok.paper else tok.ink,
        )
    }
}

/** One garment in full: how hard it works, and when it was last out. */
@Composable
private fun GarmentDetailScreen(garment: Garment, onBack: () -> Unit) {
    val tok = Retro.tok
    Column(
        modifier = Modifier.fillMaxSize().background(tok.bone).verticalScroll(rememberScrollState()),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 44.dp, start = 6.dp, end = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = tok.ink)
            }
            Text(garment.name, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = tok.ink)
        }

        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(modifier = Modifier.size(180.dp)) {
                    GarmentTile(garment)
                }
            }

            Panel {
                Text(garment.name, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = tok.ink)
                Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                    Stat("${garment.timesWorn}", "times worn")
                    Stat(lastWorn(garment), "last worn")
                    Stat(garment.warmth.title, "warmth")
                }
            }

            Panel {
                SectionHeading("Where it sits", null)
                Text(
                    "${garment.slot.title} · ${garment.tone.title}. It is one of ${garment.timesWorn} wears, which is ${verdict(garment)}.",
                    fontSize = 15.sp,
                    color = tok.stone,
                )
            }
        }
    }
}

private fun lastWorn(garment: Garment): String = when (val days = garment.lastWornDaysAgo) {
    null -> "never"
    0 -> "today"
    else -> "${days}d ago"
}

/** Described, never scored: a number of wears is a fact about a garment, not a grade for its owner. */
private fun verdict(garment: Garment): String = when {
    garment.timesWorn < 10 -> "still finding its place"
    garment.timesWorn < 40 -> "in the regular rotation"
    else -> "one of the ones you actually reach for"
}

/**
 * The outfit composer. It leads with a proposal rather than an empty grid, because deciding is the hard part and the
 * app is supposed to be doing that.
 */
@Composable
private fun OutfitComposer(
    wardrobe: List<Garment>,
    day: Day,
    onWear: (List<String>) -> Unit,
    onDismiss: () -> Unit,
) {
    val tok = Retro.tok
    var picked by remember { mutableStateOf(suggest(wardrobe)) }

    Column(
        modifier = Modifier.fillMaxSize().background(tok.bone).verticalScroll(rememberScrollState()),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 44.dp, start = 18.dp, end = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Wear today", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = tok.ink)
            Box(modifier = Modifier.weight(1f))
            Text(
                "Wear",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (picked.isEmpty()) tok.stone else tok.clay,
                modifier = Modifier
                    .clickable(enabled = picked.isNotEmpty()) { onWear(picked); onDismiss() }
                    .padding(8.dp),
            )
        }

        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Panel(tint = tok.clay) {
                Text("${day.outfit.summary} — suggested", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = tok.clay)
                Text(
                    "One piece from each layer, leaning on what you have not worn this week.",
                    fontSize = 14.sp,
                    color = tok.stone,
                )
            }

            Garment.Slot.entries.forEach { slot ->
                val items = wardrobe.filter { it.slot == slot }
                if (items.isNotEmpty()) {
                    Text(slot.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = tok.ink)
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 84.dp),
                        modifier = Modifier.height(240.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(items) { garment ->
                            Box(
                                modifier = Modifier.clickable {
                                    picked = if (picked.contains(garment.id)) {
                                        picked - garment.id
                                    } else {
                                        // One per slot: two hats is not an outfit.
                                        val others = wardrobe.filter { it.slot == garment.slot }.map { it.id }
                                        picked.filterNot { it in others } + garment.id
                                    }
                                },
                            ) {
                                GarmentTile(garment, selected = picked.contains(garment.id))
                            }
                        }
                    }
                }
            }

            OutlinedButton(
                onClick = { picked = suggest(wardrobe).shuffled() },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(15.dp),
            ) {
                Text("Shuffle the suggestion", color = tok.ink, modifier = Modifier.padding(vertical = 6.dp))
            }

            Text("Picked at ${day.outfit.pickedAt}", style = Tabular.copy(fontSize = 12.sp), color = tok.stone)
        }
    }
}

/** A suggestion, not an algorithm: one of each slot, preferring garments that have not been out for a while. */
private fun suggest(wardrobe: List<Garment>): List<String> = Garment.Slot.entries.mapNotNull { slot ->
    val items = wardrobe.filter { it.slot == slot }.sortedByDescending { it.lastWornDaysAgo ?: 99 }
    if (slot == Garment.Slot.Outer) {
        (items.firstOrNull { it.warmth == Garment.Warmth.Warm } ?: items.firstOrNull())?.id
    } else {
        items.firstOrNull()?.id
    }
}
