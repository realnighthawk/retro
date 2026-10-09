package org.nighthawklabs.retro.data

import java.util.Calendar
import java.util.Locale

// The domain. Everything hangs off a day, and a day is a row you can point at.

/** Which part of life a goal belongs to. Used to group the list, not to score anything. */
enum class Area(val title: String) {
    Health("Health"), Craft("Craft"), Home("Home"), Mind("Mind")
}

/** How often a goal is meant to happen. The app never assumes daily is the right answer. */
sealed interface Cadence {
    val title: String

    data object Daily : Cadence { override val title = "Every day" }
    data object Weekdays : Cadence { override val title = "Weekdays" }
    data class TimesPerWeek(val count: Int) : Cadence { override val title = "$count× a week" }
}

data class Goal(
    val id: String,
    val title: String,
    val area: Area = Area.Craft,
    val cadence: Cadence = Cadence.Daily,
    val done: Boolean = false,
    /** Consecutive days kept. A reading, never a score to protect. */
    val streak: Int = 0,
    /** Daily outcomes, oldest first. The list draws the recent tail; the detail draws the whole thing. */
    val history: List<Boolean> = emptyList(),
    val note: String = "",
) {
    val keptRecently: Int get() = history.takeLast(30).count { it }
}

/**
 * A garment. The first build draws it as a tone rather than a photograph; the photograph arrives with the wardrobe
 * domain, and nothing in the layout depends on it.
 */
data class Garment(
    val id: String,
    val name: String,
    val slot: Slot,
    val tone: Tone,
    val warmth: Warmth = Warmth.Mid,
    val timesWorn: Int = 0,
    val lastWornDaysAgo: Int? = null,
) {
    enum class Slot(val title: String) {
        Outer("Outer"), Top("Top"), Bottom("Bottom"), Feet("Feet")
    }

    /** Garment colour is content, not chrome, so it is its own small set of earthy tones rather than UI tokens. */
    enum class Tone(val title: String) {
        Ink("Ink"), Bone("Bone"), Sand("Sand"), Olive("Olive"),
        Clay("Clay"), Indigo("Indigo"), Rust("Rust"), Moss("Moss")
    }

    enum class Warmth(val title: String) {
        Light("Light"), Mid("Mid"), Warm("Warm")
    }
}

/** The outfit chosen for a day. */
data class Outfit(
    val garmentIDs: List<String> = emptyList(),
    val summary: String = "",
    val pickedAt: String = "",
)

/** One thing on the day's agenda, whether it is a goal, a fixed commitment, or something personal. */
data class AgendaItem(
    val id: String,
    val time: String,
    val title: String,
    val kind: Kind,
    val done: Boolean = false,
) {
    enum class Kind(val title: String) {
        Focus("Focus"), Fixed("Fixed"), Personal("Personal")
    }
}

/** A day's written record. */
data class Entry(
    val id: String,
    val date: java.util.Date,
    val text: String,
    /** A day that was missed is marked, not deleted. The app never pretends a day did not happen. */
    val cancelled: Boolean = false,
    /** How the day felt, on a five-point scale. Optional, because not every day has a reading. */
    val mood: Int? = null,
) {
    val weekday: String get() = fmt("EEE", date)
    val dayLabel: String get() = fmt("d MMM", date)

    private fun fmt(pattern: String, date: java.util.Date) =
        java.text.SimpleDateFormat(pattern, Locale.US).format(date)
}

/** One day in the week strip: how much of it was kept, and whether it was marked void. */
data class DayMark(val id: String, val letter: String, val kept: Double, val void: Boolean)

/** A day: everything the app knows about one date. */
data class Day(
    val id: String,
    val dateLabel: String,
    val weekdayLabel: String,
    val goals: List<Goal>,
    val agenda: List<AgendaItem>,
    /** The one thing. A person cannot hold four priorities, so the app picks one and says so. */
    val focusGoalID: String?,
    /** 0 at waking, 1 at the end of the waking day. */
    val progress: Double,
    val nowLabel: String,
    val week: List<DayMark>,
    val outfit: Outfit,
    val record: String,
    val cancelled: Boolean = false,
) {
    val kept: Int get() = goals.count { it.done }
    val total: Int get() = goals.size
    val focus: Goal? get() = goals.firstOrNull { it.id == focusGoalID }
}

/**
 * Authored demonstration content so the app can be built and judged before `/retro` exists.
 *
 * This is synthetic and labelled as such wherever it appears. It is not the owner's data, and it is the first thing to
 * replace when the engine lands. Nothing here is a claim about the product.
 */
object DemoData {
    const val WAKING_HOUR = 6
    const val ENDING_HOUR = 23

    val goals: List<Goal> = listOf(
        Goal(
            "g1", "Read 20 pages", Area.Mind, Cadence.Daily, done = true, streak = 12,
            history = history(0.86, 1),
            note = "Currently on The Glass Bead Game. Twenty pages is the floor, not the target.",
        ),
        Goal(
            "g2", "Ship the Retro client", Area.Craft, Cadence.Weekdays, done = false, streak = 4,
            history = history(0.54, 2),
            note = "One work package a day. Small enough that a bad day still counts.",
        ),
        Goal(
            "g3", "Walk 8,000 steps", Area.Health, Cadence.Daily, done = false, streak = 31,
            history = history(0.93, 3),
            note = "Before the weather turns, if the weather is going to turn.",
        ),
        Goal(
            "g4", "No screens after 22:00", Area.Health, Cadence.Daily, done = false, streak = 2,
            history = history(0.36, 4),
            note = "The one that actually moves everything else.",
        ),
        Goal(
            "g5", "Water the plants", Area.Home, Cadence.TimesPerWeek(2), done = false, streak = 6,
            history = history(0.62, 5),
        ),
    )

    val wardrobe: List<Garment> = listOf(
        Garment("w1", "Wool overshirt", Garment.Slot.Outer, Garment.Tone.Olive, Garment.Warmth.Warm, 34, 1),
        Garment("w2", "Waxed jacket", Garment.Slot.Outer, Garment.Tone.Ink, Garment.Warmth.Warm, 18, 6),
        Garment("w3", "Linen tee", Garment.Slot.Top, Garment.Tone.Bone, Garment.Warmth.Light, 61, 2),
        Garment("w4", "Merino crew", Garment.Slot.Top, Garment.Tone.Clay, Garment.Warmth.Mid, 27, 0),
        Garment("w5", "Poplin shirt", Garment.Slot.Top, Garment.Tone.Sand, Garment.Warmth.Light, 12, 9),
        Garment("w6", "Selvedge denim", Garment.Slot.Bottom, Garment.Tone.Indigo, Garment.Warmth.Mid, 88, 1),
        Garment("w7", "Wool trousers", Garment.Slot.Bottom, Garment.Tone.Ink, Garment.Warmth.Warm, 22, 4),
        Garment("w8", "Field chinos", Garment.Slot.Bottom, Garment.Tone.Sand, Garment.Warmth.Mid, 41, 3),
        Garment("w9", "Leather boots", Garment.Slot.Feet, Garment.Tone.Rust, Garment.Warmth.Warm, 52, 1),
        Garment("w10", "Canvas sneakers", Garment.Slot.Feet, Garment.Tone.Bone, Garment.Warmth.Light, 73, 2),
    )

    val agenda: List<AgendaItem> = listOf(
        AgendaItem("a1", "07:20", "Walk before the weather", AgendaItem.Kind.Personal, done = true),
        AgendaItem("a2", "09:30", "Retro — theme pass", AgendaItem.Kind.Focus),
        AgendaItem("a3", "13:00", "Standing call", AgendaItem.Kind.Fixed),
        AgendaItem("a4", "20:00", "Read, screens off", AgendaItem.Kind.Personal),
    )

    val weekMarks: List<DayMark> = run {
        val kept = listOf(1.0, 0.5, 0.0, 0.75, 0.25, 0.0, 0.5)
        val letters = listOf("M", "T", "W", "T", "F", "S", "S")
        letters.indices.map { DayMark("$it", letters[it], kept[it], void = it == 2) }
    }

    /** Five weeks of entries, newest first, so Review has something real to widen out onto. */
    val entries: List<Entry> = listOf(
        entry(0, "Long walk before the weather turned. Finished the theme, still owe the engine.", 4),
        entry(1, "Slow start, good afternoon. The overshirt was the right call.", 3),
        entry(2, "", null, cancelled = true),
        entry(3, "Shipped the goal detail screen. Read 40 pages by accident.", 5),
        entry(4, "Rain all day. Walked indoors, which counts less and I know it.", 2),
        entry(5, "Quiet. Nothing worth writing, which is itself worth noting.", 3),
        entry(6, "Rebuilt the arc three times before it read right.", 4),
        entry(8, "First day the wardrobe pick felt like it knew something I didn't.", 4),
        entry(11, "Travelled. Kept two of five and that was the honest ceiling.", 3),
        entry(14, "Started the no-screens rule again. Third attempt.", 3),
    )

    fun today(demoHour: Int? = null): Day {
        val cal = Calendar.getInstance()
        val hour = demoHour ?: cal.get(Calendar.HOUR_OF_DAY)
        val minute = if (demoHour == null) cal.get(Calendar.MINUTE) else 0
        val elapsed = (hour + minute / 60.0 - WAKING_HOUR) / (ENDING_HOUR - WAKING_HOUR)

        return Day(
            id = fmt("yyyy-MM-dd", cal.time),
            dateLabel = fmt("d MMMM", cal.time),
            weekdayLabel = fmt("EEEE", cal.time),
            goals = goals,
            agenda = agenda,
            // The one thing: the goal with the longest unbroken run that is still open, so the owner does not have to
            // re-decide what matters most every morning.
            focusGoalID = goals.firstOrNull { !it.done && it.streak >= 20 }?.id
                ?: goals.firstOrNull { !it.done }?.id,
            progress = elapsed,
            nowLabel = String.format(Locale.US, "%02d:%02d", hour, minute),
            week = weekMarks,
            outfit = Outfit(summary = "14° · Clear", pickedAt = "07:20"),
            record = "Long walk before the weather turned. Finished the theme, still owe the engine.",
        )
    }

    /** A believable run of days from a rough ratio, deterministic so the screens look the same every launch. */
    private fun history(keptRatio: Double, seed: Int): List<Boolean> {
        var state = (seed.toLong() * 2_654_435_761L) + 1L
        return (0 until 56).map {
            state = state * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
            val value = ((state ushr 33) % 10_000L).toDouble() / 10_000.0
            value < keptRatio
        }
    }

    private fun entry(daysAgo: Int, text: String, mood: Int?, cancelled: Boolean = false): Entry {
        val date = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -daysAgo) }.time
        return Entry(fmt("yyyy-MM-dd", date), date, text, cancelled, mood)
    }

    private fun fmt(pattern: String, date: java.util.Date) =
        java.text.SimpleDateFormat(pattern, Locale.US).format(date)
}
