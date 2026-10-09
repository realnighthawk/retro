package org.nighthawklabs.retro.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.Goal
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular
import org.nighthawklabs.retro.ui.theme.rememberReduceMotion

/**
 * A drawn tick: a rounded square that fills with sage and draws its own checkmark, so the one action on this screen
 * lands as a single authored motion rather than a symbol swap.
 */
@Composable
fun TickBox(done: Boolean, modifier: Modifier = Modifier) {
    val tok = Retro.tok
    val reduceMotion = rememberReduceMotion()
    val fill by animateFloatAsState(
        targetValue = if (done) 1f else 0f,
        animationSpec = tween(durationMillis = if (reduceMotion) 0 else 220),
        label = "tickFill",
    )
    val tick by animateFloatAsState(
        targetValue = if (done) 1f else 0f,
        animationSpec = tween(durationMillis = if (reduceMotion) 0 else 260),
        label = "tickDraw",
    )

    Box(
        modifier = modifier
            .size(30.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(if (fill > 0f) tok.sage.copy(alpha = fill) else Color.Transparent)
            .border(1.5.dp, if (done) tok.sage else tok.stone, RoundedCornerShape(9.dp))
            .drawWithContent {
                drawContent()
                if (tick > 0f) {
                    val w = size.width
                    val h = size.height
                    val start = Offset(w * 0.26f, h * 0.52f)
                    val elbow = Offset(w * 0.44f, h * 0.70f)
                    val end = Offset(w * 0.76f, h * 0.32f)
                    val first = (tick.coerceIn(0f, 0.5f)) / 0.5f
                    val second = ((tick - 0.5f) / 0.5f).coerceIn(0f, 1f)
                    val stroke = 2.6.dp.toPx()
                    drawLine(tok.paper, start, lerp(start, elbow, first), strokeWidth = stroke, cap = StrokeCap.Round)
                    if (second > 0f) {
                        drawLine(tok.paper, elbow, lerp(elbow, end, second), strokeWidth = stroke, cap = StrokeCap.Round)
                    }
                }
            },
    )
}

private fun lerp(a: Offset, b: Offset, t: Float) = Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)

/**
 * The recent run at a glance. Real recorded days, so a gap is information rather than a reproach.
 *
 * A day that was not kept is `sand`, never a warning colour: the app describes what happened and is not allowed to be
 * disappointed about it. The count is capped here so a goal carrying a long history cannot widen a row past the screen.
 */
@Composable
fun HistoryRow(history: List<Boolean>, days: Int = 14, modifier: Modifier = Modifier) {
    val tok = Retro.tok
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        history.takeLast(days).forEach { kept ->
            Box(
                modifier = Modifier
                    .size(width = 4.dp, height = 20.dp)
                    .background(if (kept) tok.sage else tok.sand, RoundedCornerShape(2.dp))
            )
        }
    }
}

/**
 * One goal in a list: a tick you can hit without leaving the list, and a row you can open.
 *
 * Two separate controls rather than one wrapping the other — and the tick is named for its action, because two controls
 * sharing one accessible name is how a screen reader ends up with a button nobody can predict.
 */
@Composable
fun GoalRow(
    goal: Goal,
    onToggle: () -> Unit,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tok = Retro.tok
    Row(
        modifier = modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clickable(onClick = onToggle)
                .semantics { contentDescription = if (goal.done) "Mark ${goal.title} as not kept" else "Mark ${goal.title} as kept" },
            contentAlignment = Alignment.Center,
        ) {
            TickBox(done = goal.done)
        }

        Row(
            modifier = Modifier.weight(1f).clickable(onClick = onOpen),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.weight(1f)) {
                Text(
                    goal.title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (goal.done) tok.stone else tok.ink,
                    textDecoration = if (goal.done) TextDecoration.LineThrough else null,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "${goal.streak} days running",
                        style = Tabular.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium),
                        color = if (goal.done) tok.sage else tok.stone,
                    )
                    HistoryRow(goal.history, days = 10)
                }
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = tok.stone,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}
