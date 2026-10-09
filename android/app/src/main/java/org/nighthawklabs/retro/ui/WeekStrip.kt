package org.nighthawklabs.retro.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.nighthawklabs.retro.data.DayMark
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular

/**
 * The week so far: one cell per day, the bar in each showing how much of that day was kept.
 *
 * This is a reading, not a score. A day with nothing kept draws a short bar rather than a warning mark, and a day marked
 * void is hatched rather than blank, because the app does not pretend a day did not happen.
 */
@Composable
fun WeekStrip(days: List<DayMark>, today: String, modifier: Modifier = Modifier) {
    val tok = Retro.tok
    Row(modifier = modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        days.forEach { day ->
            val isToday = day.id == today
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                Text(
                    day.letter,
                    style = Tabular.copy(fontSize = 11.sp, fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal),
                    color = if (isToday) tok.ink else tok.stone,
                )

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .background(tok.sand, RoundedCornerShape(5.dp))
                        .border(
                            width = if (isToday) 1.5.dp else 1.dp,
                            color = if (isToday) tok.clay else tok.rule,
                            shape = RoundedCornerShape(5.dp),
                        ),
                    contentAlignment = Alignment.BottomCenter,
                ) {
                    when {
                        day.void -> Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(tok.rust.copy(alpha = 0.18f), RoundedCornerShape(5.dp)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("–", color = tok.rust, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                        }

                        day.kept > 0 -> Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .fillMaxHeight(day.kept.toFloat().coerceIn(0.16f, 1f))
                                .background(
                                    tok.sage.copy(alpha = 0.55f + 0.45f * day.kept.toFloat()),
                                    RoundedCornerShape(5.dp),
                                ),
                        )

                        else -> Unit
                    }
                }
            }
        }
    }
}
