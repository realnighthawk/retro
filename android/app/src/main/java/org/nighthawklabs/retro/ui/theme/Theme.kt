package org.nighthawklabs.retro.ui.theme

import android.provider.Settings
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * "Tranquil Earth / Sage & Clay": linen ground, unglazed pottery, and a garden.
 *
 * The palette is deliberately small. Neutrals do all the structure — [bone] is the page, [paper] is anything that sits
 * on it, [sand] is anything recessed into it, [ink] is all text. Three colours carry meaning and nothing else is
 * coloured: **[clay] is where you act, [sage] is what you kept, [rust] is a day marked void.** Because action and
 * outcome are different colours, a screen can say both at once without either shouting. A day that was missed is
 * [sand], never a warning colour: the app describes what happened and is not allowed to be disappointed about it.
 *
 * Contrast measured with the WCAG 2.1 relative-luminance formula. Light: ink 13.8:1, stone 4.6:1, clay 4.8:1,
 * sage 5.3:1, rust 7.2:1. Dark: ink 16.1:1, stone 6.9:1, clay 6.7:1, sage 7.8:1, rust 6.5:1.
 */
@Immutable
class Tok(
    val dark: Boolean,
    val bone: Color, val paper: Color, val sand: Color, val rule: Color,
    val ink: Color, val stone: Color, val clay: Color, val sage: Color, val rust: Color,
    val heroTop: Color, val heroBottom: Color,
) {
    /** A tint of whichever colour is in charge of a surface. */
    fun wash(colour: Color, amount: Float = 0.10f): Color = colour.copy(alpha = amount)
}

val SageTok = Tok(
    dark = false,
    bone = Color(0xFFF4F1EA), paper = Color(0xFFFFFDF8), sand = Color(0xFFEAE5DA), rule = Color(0xFFDDD6C7),
    ink = Color(0xFF22251E), stone = Color(0xFF6B6F62), clay = Color(0xFFA2543A), sage = Color(0xFF4F6B3A),
    rust = Color(0xFF8E2F22), heroTop = Color(0xFFF9F6EF), heroBottom = Color(0xFFEFE9DB),
)

val DuskTok = Tok(
    dark = true,
    bone = Color(0xFF131410), paper = Color(0xFF1B1D17), sand = Color(0xFF252820), rule = Color(0xFF33372D),
    ink = Color(0xFFF2EFE6), stone = Color(0xFFA3A79A), clay = Color(0xFFD9926F), sage = Color(0xFF93BB74),
    rust = Color(0xFFE08A72), heroTop = Color(0xFF1C1F17), heroBottom = Color(0xFF131410),
)

val LocalTok = staticCompositionLocalOf { SageTok }

object Retro {
    val tok: Tok @Composable @ReadOnlyComposable get() = LocalTok.current
}

/** Tabular figures, so columns align and a counting figure does not jitter. */
val Tabular = TextStyle(fontFeatureSettings = "tnum")

/** The one large figure a screen is about. */
val HeroStyle = TextStyle(fontSize = 46.sp, lineHeight = 52.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum")

private val AppTypography = Typography().let { base ->
    base.copy(
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.8).sp),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelSmall = base.labelSmall.copy(letterSpacing = 0.6.sp),
    )
}

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp), small = RoundedCornerShape(10.dp), medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(18.dp), extraLarge = RoundedCornerShape(26.dp),
)

@Composable
fun RetroTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val t = if (dark) DuskTok else SageTok
    val scheme = if (dark) {
        darkColorScheme(
            primary = t.clay, onPrimary = t.bone, background = t.bone, onBackground = t.ink,
            surface = t.paper, onSurface = t.ink, surfaceVariant = t.sand, onSurfaceVariant = t.stone,
            secondary = t.sage, onSecondary = t.bone, tertiary = t.rust,
            surfaceContainer = t.paper, surfaceContainerHigh = t.sand, surfaceContainerHighest = t.sand,
            outline = t.rule, outlineVariant = t.rule, error = t.rust, onError = t.bone,
        )
    } else {
        lightColorScheme(
            primary = t.clay, onPrimary = t.paper, background = t.bone, onBackground = t.ink,
            surface = t.paper, onSurface = t.ink, surfaceVariant = t.sand, onSurfaceVariant = t.stone,
            secondary = t.sage, onSecondary = t.paper, tertiary = t.rust,
            surfaceContainer = t.paper, surfaceContainerHigh = t.sand, surfaceContainerHighest = t.sand,
            outline = t.rule, outlineVariant = t.rule, error = t.rust, onError = t.paper,
        )
    }
    CompositionLocalProvider(LocalTok provides t) {
        MaterialTheme(colorScheme = scheme, typography = AppTypography, shapes = AppShapes, content = content)
    }
}

/**
 * Android's Reduce Motion signal is the system animator duration scale. When it is zero the platform has already asked
 * for no animation, so the one authored moment arrives already drawn instead of being skipped halfway.
 */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}
