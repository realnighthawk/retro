package org.nighthawklabs.retro.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.nighthawklabs.retro.ui.theme.Retro

/**
 * The app's mark: a rewind glyph, the one gesture everyone already reads as "go back over it". Drawn rather than
 * shipped as an image, so it takes the ink and clay colours and scales cleanly at any size.
 */
@Composable
fun RetroMark(size: Dp = 64.dp, modifier: Modifier = Modifier) {
    val tok = Retro.tok
    Canvas(modifier = modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        val stroke = w * 0.115f
        val chevronW = w * 0.30f
        val chevronH = h * 0.50f
        val centreX = w / 2f
        val top = h / 2f - chevronH / 2f

        fun chevron(offsetX: Float, colour: androidx.compose.ui.graphics.Color) {
            val right = centreX + offsetX + chevronW / 2f
            val left = right - chevronW
            drawLine(colour, Offset(right, top), Offset(left, h / 2f), strokeWidth = stroke, cap = StrokeCap.Round)
            drawLine(colour, Offset(left, h / 2f), Offset(right, top + chevronH), strokeWidth = stroke, cap = StrokeCap.Round)
        }

        chevron(-w * 0.19f, tok.ink.copy(alpha = 0.3f))
        chevron(w * 0.19f, tok.clay)
    }
}
