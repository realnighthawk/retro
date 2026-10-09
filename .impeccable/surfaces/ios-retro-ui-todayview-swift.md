---
version: 1
slug: "ios-retro-ui-todayview-swift"
primary_target: "ios/Retro/UI/TodayView.swift"
related_targets: ["android/app/src/main/java/org/nighthawklabs/retro/ui/TodayScreen.kt"]
---

# Today (Retro iOS + Android)

Operate surface. The owner opens it in the morning to see what the day is and again at night to record it.

## Direction contract

**THESIS.** The day is the primary key, and the screen proves it: one arc locates you inside today, and everything the
day owns hangs beneath it. It refuses the category default of a stack of equal summary cards — the arc is not a
statistic, it is the day itself, so there is nothing to count down and nothing to score.

**OWN-WORLD.** "Tranquil Earth / Sage & Clay": linen `#F4F1EA` ground, `#FFFDF8` paper, `#EAE5DA` sand recesses,
`#22251E` moss ink for all text. Three colours carry meaning and nothing else is coloured — clay `#A2543A` is where you
act, sage `#4F6B3A` is what you kept, rust `#8E2F22` is a day marked void. A missed day is sand, never a warning.
Type is San Francisco / Roboto: one bold tight-tracked line for the date, tabular figures everywhere a number is a
reading, hierarchy by weight and case rather than a size ladder. Panels are the only container, 18pt radius, warm
offset shadow. Dark counterpart is a lamplit room: `#131410` ground, `#D9926F` clay, `#93BB74` sage.

**STORY.** The owner opens it and, before reading a word, knows where they are in the day and how much of it they have
kept. They tick a goal and watch the run and its two-week history move with the tick, because they are the same fact.

**FIRST VIEWPORT.** An atmospheric band, full-bleed to the top edge: the weekday in clay, the date at 34pt bold and
tight-tracked, then the arc at ~150pt tall spanning the width — the day recessed in sand, the elapsed part in a clay
gradient with a haloed dot at now, and the current time set inside the arc. Beneath it the hero figure: the number kept,
large and tabular, with "/ 4 kept" quiet beside it. Everything below sits on paper: the week strip, the day's goals with
their runs and histories, the outfit, and the record field. The account control is a single icon, top right.

**FORM.** A day-arc instrument panel: the day's position rendered as the arc the sun actually crosses, with the day's
parts ruled beneath it. Assigned from the direction roll, seed key `16468f7d` (candidate 6 of the grounded list —
a print-shop job docket), adapted: on an Operate surface the world may enter only through type, palette, density and one
signature move, so the docket's ruled-ledger ground was refused as a costume and only its register kept — small-caps
field labels, tabular figures, hard-edged marks, and the void stamp.

**FINISH.** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md,
and every shipping raster carrying its provenance.
