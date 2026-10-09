package org.nighthawklabs.retro.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import org.nighthawklabs.retro.ui.theme.Retro
import org.nighthawklabs.retro.ui.theme.Tabular
import org.nighthawklabs.retro.ui.theme.rememberReduceMotion
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * The hero: the day drawn as an arc from waking to now, the way the sun actually crosses it.
 *
 * This is the one authored moment in the app, and it is doing work — it answers "where am I in this day" at a glance,
 * which is the question the Today board exists for. It draws once when the screen opens and then stays still, because
 * a working screen that keeps moving is a working screen you cannot read. Under Reduce Motion it arrives already drawn.
 */
@Composable
fun DayArc(
    progress: Double,
    nowLabel: String,
    startLabel: String,
    endLabel: String,
    modifier: Modifier = Modifier,
) {
    val tok = Retro.tok
    val reduceMotion = rememberReduceMotion()
    val drawn = remember { Animatable(0f) }
    val target = progress.coerceIn(0.0, 1.0).toFloat()

    LaunchedEffect(target, reduceMotion) {
        drawn.snapTo(0f)
        if (reduceMotion) {
            drawn.snapTo(target)
        } else {
            // A beat before drawing, so the arc is watched rather than caught mid-start.
            delay(60)
            drawn.animateTo(target, tween(durationMillis = 1050, easing = LinearOutSlowInEasing))
        }
    }

    val strokeWidth = with(LocalDensity.current) { 10.dp.toPx() }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(150.dp)
                .clearAndSetSemantics {
                    contentDescription = "Day elapsed ${(target * 100).toInt()} percent, $nowLabel"
                },
            contentAlignment = Alignment.BottomCenter,
        ) {
            Canvas(modifier = Modifier.fillMaxWidth().height(150.dp)) {
                val radius = min(size.width, size.height * 2f) / 2f - strokeWidth - 10f
                val centre = Offset(size.width / 2f, size.height)

                // The whole day, recessed.
                drawArc(
                    color = tok.sand,
                    startAngle = 180f,
                    sweepAngle = 180f,
                    useCenter = false,
                    topLeft = Offset(centre.x - radius, centre.y - radius),
                    size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2),
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
                )

                // Hour ticks, every sixth taller, so the arc reads as a day and not a progress bar.
                for (hour in 0..24) {
                    val fraction = hour / 24.0
                    val angle = Math.PI * (1 + fraction)
                    val outer = radius + strokeWidth / 2f + 4f
                    val inner = outer + if (hour % 6 == 0) 6f else 3f
                    drawLine(
                        color = tok.rule,
                        start = Offset(centre.x + cos(angle).toFloat() * outer, centre.y + sin(angle).toFloat() * outer),
                        end = Offset(centre.x + cos(angle).toFloat() * inner, centre.y + sin(angle).toFloat() * inner),
                        strokeWidth = 1f,
                    )
                }

                val swept = 180f * drawn.value
                if (swept > 0f) {
                    drawArc(
                        brush = Brush.linearGradient(
                            colors = listOf(tok.clay.copy(alpha = 0.72f), tok.clay),
                            start = Offset(0f, size.height),
                            end = Offset(size.width, 0f),
                        ),
                        startAngle = 180f,
                        sweepAngle = swept,
                        useCenter = false,
                        topLeft = Offset(centre.x - radius, centre.y - radius),
                        size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2),
                        style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
                    )

                    // Now: a dot on the arc with a halo, so it reads as a position rather than an end cap.
                    val angle = Math.PI * (1 + drawn.value)
                    val point = Offset(
                        centre.x + cos(angle).toFloat() * radius,
                        centre.y + sin(angle).toFloat() * radius,
                    )
                    drawCircle(tok.clay.copy(alpha = 0.16f), radius = 14f, center = point)
                    drawCircle(tok.clay, radius = 7.5f, center = point)
                    drawCircle(tok.paper, radius = 3f, center = point)
                }
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(bottom = 34.dp),
            ) {
                Text(nowLabel, style = Tabular.copy(fontSize = 20.sp, fontWeight = FontWeight.SemiBold), color = tok.ink)
                Text("now", fontSize = 11.sp, color = tok.stone)
            }
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(startLabel, style = Tabular.copy(fontSize = 11.sp), color = tok.stone)
            Text(endLabel, style = Tabular.copy(fontSize = 11.sp), color = tok.stone)
        }
    }
}
