import Foundation

/// Authored demonstration content so the app can be built and judged before `/retro` exists.
///
/// This is synthetic and labelled as such wherever it appears. It is not the owner's data, and it is the first thing to
/// replace when the engine lands. Nothing here is a claim about the product — no metrics, no ratings, no prices.
enum DemoData {
    static let wakingHour = 6
    static let endingHour = 23

    // MARK: Goals

    static let goals: [Goal] = [
        Goal(
            title: "Read 20 pages",
            area: .mind,
            cadence: .daily,
            done: true,
            streak: 12,
            history: history(keptRatio: 0.86, seed: 1),
            note: "Currently on The Glass Bead Game. Twenty pages is the floor, not the target."
        ),
        Goal(
            title: "Ship the Retro client",
            area: .craft,
            cadence: .weekdays,
            done: false,
            streak: 4,
            history: history(keptRatio: 0.54, seed: 2),
            note: "One work package a day. Small enough that a bad day still counts."
        ),
        Goal(
            title: "Walk 8,000 steps",
            area: .health,
            cadence: .daily,
            done: false,
            streak: 31,
            history: history(keptRatio: 0.93, seed: 3),
            note: "Before the weather turns, if the weather is going to turn."
        ),
        Goal(
            title: "No screens after 22:00",
            area: .health,
            cadence: .daily,
            done: false,
            streak: 2,
            history: history(keptRatio: 0.36, seed: 4),
            note: "The one that actually moves everything else."
        ),
        Goal(
            title: "Water the plants",
            area: .home,
            cadence: .timesPerWeek(2),
            done: false,
            streak: 6,
            history: history(keptRatio: 0.62, seed: 5),
            note: ""
        )
    ]

    // MARK: Wardrobe

    static let wardrobe: [Garment] = [
        Garment(name: "Wool overshirt", slot: .outer, tone: .olive, warmth: .warm, timesWorn: 34, lastWornDaysAgo: 1),
        Garment(name: "Waxed jacket", slot: .outer, tone: .ink, warmth: .warm, timesWorn: 18, lastWornDaysAgo: 6),
        Garment(name: "Linen tee", slot: .top, tone: .bone, warmth: .light, timesWorn: 61, lastWornDaysAgo: 2),
        Garment(name: "Merino crew", slot: .top, tone: .clay, warmth: .mid, timesWorn: 27, lastWornDaysAgo: 0),
        Garment(name: "Poplin shirt", slot: .top, tone: .sand, warmth: .light, timesWorn: 12, lastWornDaysAgo: 9),
        Garment(name: "Selvedge denim", slot: .bottom, tone: .indigo, warmth: .mid, timesWorn: 88, lastWornDaysAgo: 1),
        Garment(name: "Wool trousers", slot: .bottom, tone: .ink, warmth: .warm, timesWorn: 22, lastWornDaysAgo: 4),
        Garment(name: "Field chinos", slot: .bottom, tone: .sand, warmth: .mid, timesWorn: 41, lastWornDaysAgo: 3),
        Garment(name: "Leather boots", slot: .feet, tone: .rust, warmth: .warm, timesWorn: 52, lastWornDaysAgo: 1),
        Garment(name: "Canvas sneakers", slot: .feet, tone: .bone, warmth: .light, timesWorn: 73, lastWornDaysAgo: 2)
    ]

    // MARK: Day

    static func today(demoHour: Int? = nil) -> Day {
        let now = Date.now
        let hour = demoHour ?? Calendar.current.component(.hour, from: now)
        let minute = demoHour == nil ? Calendar.current.component(.minute, from: now) : 0
        let elapsed = (Double(hour) + Double(minute) / 60 - Double(wakingHour)) / Double(endingHour - wakingHour)

        let dayGoals = goals
        return Day(
            id: isoDay(now),
            date: now,
            goals: dayGoals,
            agenda: agenda,
            // The one thing: the goal with the longest unbroken run that is still open. The app chooses, so the
            // owner does not have to re-decide what matters most every morning.
            focusGoalID: dayGoals.first { !$0.done && $0.streak >= 20 }?.id ?? dayGoals.first { !$0.done }?.id,
            progress: elapsed,
            nowLabel: String(format: "%02d:%02d", hour, minute),
            week: weekMarks,
            outfit: Outfit(
                garmentIDs: [],
                summary: "14° · Clear",
                pickedAt: "07:20"
            ),
            record: "Long walk before the weather turned. Finished the theme, still owe the engine.",
            cancelled: false
        )
    }

    static let agenda: [AgendaItem] = [
        AgendaItem(time: "07:20", title: "Walk before the weather", kind: .personal, done: true),
        AgendaItem(time: "09:30", title: "Retro — theme pass", kind: .focus),
        AgendaItem(time: "13:00", title: "Standing call", kind: .fixed),
        AgendaItem(time: "20:00", title: "Read, screens off", kind: .personal)
    ]

    static let weekMarks: [DayMark] = {
        let kept: [Double] = [1, 0.5, 0, 0.75, 0.25, 0, 0.5]
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).map { index in
            DayMark(id: "\(index)", letter: letters[index], kept: kept[index], void: index == 2)
        }
    }()

    // MARK: Record

    /// Five weeks of entries, newest first, so Review has something real to widen out onto.
    static let entries: [Entry] = [
        entry(daysAgo: 0, text: "Long walk before the weather turned. Finished the theme, still owe the engine.", mood: 4),
        entry(daysAgo: 1, text: "Slow start, good afternoon. The overshirt was the right call.", mood: 3),
        entry(daysAgo: 2, text: "", cancelled: true),
        entry(daysAgo: 3, text: "Shipped the goal detail screen. Read 40 pages by accident.", mood: 5),
        entry(daysAgo: 4, text: "Rain all day. Walked indoors, which counts less and I know it.", mood: 2),
        entry(daysAgo: 5, text: "Quiet. Nothing worth writing, which is itself worth noting.", mood: 3),
        entry(daysAgo: 6, text: "Rebuilt the arc three times before it read right.", mood: 4),
        entry(daysAgo: 8, text: "First day the wardrobe pick felt like it knew something I didn't.", mood: 4),
        entry(daysAgo: 11, text: "Travelled. Kept two of five and that was the honest ceiling.", mood: 3),
        entry(daysAgo: 14, text: "Started the no-screens rule again. Third attempt.", mood: 3)
    ]

    // MARK: Helpers

    /// A believable run of days from a rough ratio, deterministic so the screens look the same every launch.
    private static func history(keptRatio: Double, seed: Int) -> [Bool] {
        var state = UInt64(seed &* 2_654_435_761 &+ 1)
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 10_000) / 10_000
        }
        return (0..<56).map { _ in next() < keptRatio }
    }

    private static func entry(daysAgo: Int, text: String, mood: Int? = nil, cancelled: Bool = false) -> Entry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return Entry(id: isoDay(date), date: date, text: text, cancelled: cancelled, mood: mood)
    }

    static func isoDay(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
