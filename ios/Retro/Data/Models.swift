import Foundation

// The domain. Everything hangs off a day, and a day is a row you can point at.

/// Which part of life a goal belongs to. Used to group the list, not to score anything.
enum Area: String, CaseIterable, Identifiable {
    case health, craft, home, mind
    var id: String { rawValue }

    var title: String {
        switch self {
        case .health: "Health"
        case .craft: "Craft"
        case .home: "Home"
        case .mind: "Mind"
        }
    }

    var symbol: String {
        switch self {
        case .health: "figure.walk"
        case .craft: "hammer"
        case .home: "house"
        case .mind: "book.closed"
        }
    }
}

/// How often a goal is meant to happen. The app never assumes daily is the right answer.
enum Cadence: Hashable {
    case daily
    case weekdays
    case timesPerWeek(Int)

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .timesPerWeek(let count): "\(count)× a week"
        }
    }
}

struct Goal: Identifiable, Equatable {
    let id: UUID
    var title: String
    var area: Area
    var cadence: Cadence
    /// Whether it is kept today.
    var done: Bool
    /// Consecutive days kept. A reading, never a score to protect.
    var streak: Int
    /// Daily outcomes, oldest first. The list draws the recent tail; the detail draws the whole thing.
    var history: [Bool]
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        area: Area = .craft,
        cadence: Cadence = .daily,
        done: Bool = false,
        streak: Int = 0,
        history: [Bool] = [],
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.area = area
        self.cadence = cadence
        self.done = done
        self.streak = streak
        self.history = history
        self.note = note
    }

    /// Kept in the last 30 days, as a count. Used on the detail screen.
    var keptRecently: Int { history.suffix(30).filter { $0 }.count }
}

/// A garment. The first build draws it as a tone rather than a photograph; the photograph arrives with the wardrobe
/// domain, and nothing in the layout depends on it.
struct Garment: Identifiable, Equatable {
    let id: UUID
    var name: String
    var slot: Slot
    var tone: Tone
    var warmth: Warmth
    var timesWorn: Int
    var lastWornDaysAgo: Int?

    enum Slot: String, CaseIterable, Identifiable {
        case outer, top, bottom, feet
        var id: String { rawValue }

        var title: String {
            switch self {
            case .outer: "Outer"
            case .top: "Top"
            case .bottom: "Bottom"
            case .feet: "Feet"
            }
        }

        var symbol: String {
            switch self {
            case .outer: "jacket"
            case .top: "tshirt"
            case .bottom: "rectangle.portrait"
            case .feet: "shoe"
            }
        }
    }

    /// Garment colour is content, not chrome, so it is its own small set of earthy tones rather than UI tokens.
    enum Tone: String, CaseIterable, Identifiable {
        case ink, bone, sand, olive, clay, indigo, rust, moss
        var id: String { rawValue }

        var title: String {
            switch self {
            case .ink: "Ink"
            case .bone: "Bone"
            case .sand: "Sand"
            case .olive: "Olive"
            case .clay: "Clay"
            case .indigo: "Indigo"
            case .rust: "Rust"
            case .moss: "Moss"
            }
        }
    }

    enum Warmth: String, CaseIterable, Identifiable {
        case light, mid, warm
        var id: String { rawValue }

        var title: String {
            switch self {
            case .light: "Light"
            case .mid: "Mid"
            case .warm: "Warm"
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        slot: Slot,
        tone: Tone,
        warmth: Warmth = .mid,
        timesWorn: Int = 0,
        lastWornDaysAgo: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.slot = slot
        self.tone = tone
        self.warmth = warmth
        self.timesWorn = timesWorn
        self.lastWornDaysAgo = lastWornDaysAgo
    }
}

/// The outfit chosen for a day.
struct Outfit: Equatable {
    var garmentIDs: [UUID]
    var summary: String
    var pickedAt: String
}

/// One thing on the day's agenda, whether it is a goal, a fixed commitment, or something personal.
struct AgendaItem: Identifiable, Equatable {
    let id: UUID
    var time: String
    var title: String
    var kind: Kind
    var done: Bool

    enum Kind: String {
        case focus, fixed, personal

        var title: String {
            switch self {
            case .focus: "Focus"
            case .fixed: "Fixed"
            case .personal: "Personal"
            }
        }
    }

    init(id: UUID = UUID(), time: String, title: String, kind: Kind, done: Bool = false) {
        self.id = id
        self.time = time
        self.title = title
        self.kind = kind
        self.done = done
    }
}

/// A day's written record.
struct Entry: Identifiable, Equatable {
    let id: String
    var date: Date
    var text: String
    /// A day that was missed is marked, not deleted. The app never pretends a day did not happen.
    var cancelled: Bool
    /// How the day felt, on a five-point scale. Optional, because not every day has a reading.
    var mood: Int?

    var weekday: String { date.formatted(.dateTime.weekday(.abbreviated)) }
    var dayLabel: String { date.formatted(.dateTime.day().month(.abbreviated)) }
}

/// A day: everything the app knows about one date.
struct Day: Identifiable, Equatable {
    var id: String
    var date: Date
    var goals: [Goal]
    var agenda: [AgendaItem]
    /// The one thing. A person cannot hold four priorities, so the app picks one and says so.
    var focusGoalID: UUID?
    /// 0 at waking, 1 at the end of the waking day.
    var progress: Double
    var nowLabel: String
    var week: [DayMark]
    var outfit: Outfit
    var record: String
    var cancelled: Bool

    var kept: Int { goals.filter(\.done).count }
    var total: Int { goals.count }
    var focus: Goal? { goals.first { $0.id == focusGoalID } }
}

/// One day in the week strip: how much of it was kept, and whether it was marked void.
struct DayMark: Identifiable, Equatable {
    let id: String
    let letter: String
    /// 0...1 of that day's goals kept.
    let kept: Double
    let void: Bool
}
