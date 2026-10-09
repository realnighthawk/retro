package org.nighthawklabs.retro.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.Garment
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular

/**
 * The one panel. Warm, layered, and the same everywhere, so a screen reads as one surface rather than a pile of
 * loose boxes. Content sits inside a real `Column`: a Compose `Column` is a container, so the background wraps the
 * group instead of landing on each child.
 */
@Composable
fun Panel(
    modifier: Modifier = Modifier,
    tint: Color? = null,
    content: @Composable () -> Unit,
) {
    val tok = Retro.tok
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(if (tint != null) tok.wash(tint) else tok.paper)
            .padding(18.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
    }
}

/** A section title. The heading carries its own weight — there is no label above it. */
@Composable
fun SectionHeading(text: String, trailing: String?) {
    val tok = Retro.tok
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = tok.ink)
        if (trailing != null) {
            Box(modifier = Modifier.weight(1f))
            Text(trailing, style = Tabular.copy(fontSize = 14.sp), color = tok.stone)
        }
    }
}

/** Small figures under a big one. */
@Composable
fun Stat(value: String, label: String) {
    val tok = Retro.tok
    Column {
        Text(value, style = Tabular.copy(fontSize = 20.sp, fontWeight = FontWeight.SemiBold), color = tok.ink)
        Text(label, fontSize = 11.sp, color = tok.stone)
    }
}

/**
 * A garment drawn as its tone. Photographs arrive with the wardrobe domain; nothing here depends on them, so the
 * layout will not change when they do.
 */
@Composable
fun GarmentTile(garment: Garment, selected: Boolean = false, modifier: Modifier = Modifier) {
    val tok = Retro.tok
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(74.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(
                    Brush.linearGradient(
                        listOf(garment.tone.color, garment.tone.color.copy(alpha = 0.72f))
                    )
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(garment.slot.title, fontSize = 11.sp, fontWeight = FontWeight.Medium, color = garment.tone.onColor)
        }
        Text(
            garment.name,
            fontSize = 11.sp,
            color = tok.stone,
            maxLines = 1,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}

/**
 * Garment colour is content, so it may sit outside the UI palette — but it still has to hold up in both appearances
 * and against its own glyph.
 */
val Garment.Tone.color: Color
    get() = when (this) {
        Garment.Tone.Ink -> Color(0xFF2A2D26)
        Garment.Tone.Bone -> Color(0xFFE8E3D6)
        Garment.Tone.Sand -> Color(0xFFCBB894)
        Garment.Tone.Olive -> Color(0xFF5E6B3C)
        Garment.Tone.Clay -> Color(0xFFA2543A)
        Garment.Tone.Indigo -> Color(0xFF33405E)
        Garment.Tone.Rust -> Color(0xFF8E4A2A)
        Garment.Tone.Moss -> Color(0xFF4F6B3A)
    }

/** Light garments take ink glyphs, dark garments take bone, in both appearances. */
val Garment.Tone.onColor: Color
    get() = when (this) {
        Garment.Tone.Bone, Garment.Tone.Sand -> Color(0xFF22251E)
        else -> Color(0xFFF7F5EF)
    }

/** How the day felt, as five marks rather than a number. Read at a glance, never scored. */
@Composable
fun MoodDots(mood: Int, modifier: Modifier = Modifier) {
    val tok = Retro.tok
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        (1..5).forEach { step ->
            Box(
                modifier = Modifier
                    .height(5.dp)
                    .fillMaxWidth(1f / 5f)
                    .background(if (step <= mood) tok.clay else tok.sand, RoundedCornerShape(3.dp))
            )
        }
    }
}
