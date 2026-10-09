import SwiftUI

/// The app's five surfaces, each with one job. The order is the order of a day: the day itself, the long game, what
/// you put on, how it is going, and the system underneath.
enum DemoSurface: String, CaseIterable, Identifiable {
    case today, goals, wardrobe, review, you
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .goals: "Goals"
        case .wardrobe: "Wardrobe"
        case .review: "Review"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .goals: "target"
        case .wardrobe: "hanger"
        case .review: "chart.bar.doc.horizontal"
        case .you: "person"
        }
    }

    /// Where the shell opens. Today unless a DEBUG launch argument says otherwise.
    static func startingOn() -> DemoSurface {
        guard let name = Config.devSurface else { return .today }
        return DemoSurface(rawValue: name) ?? .today
    }
}

/// The signed-in shell. Owns the day, because every surface reads or writes it, and owns the one place a thought can be
/// captured from anywhere — the moment you have to navigate to record something, you have lost it.
struct ProductivityDemoShell: View {
    @Environment(AuthService.self) private var auth

    @State private var surface: DemoSurface = DemoSurface.startingOn()
    @State private var day = DemoData.today(demoHour: Config.devHour)
    @State private var goals = DemoData.goals
    @State private var wardrobe = DemoData.wardrobe
    @State private var entries = DemoData.entries
    @State private var capturing = false
    @State private var showingAccount = false

    var body: some View {
        TabView(selection: $surface) {
            TodayView(day: $day, wardrobe: wardrobe, open: open)
                .tabItem { Label(DemoSurface.today.title, systemImage: DemoSurface.today.symbol) }
                .tag(DemoSurface.today)

            GoalsView(goals: $goals)
                .tabItem { Label(DemoSurface.goals.title, systemImage: DemoSurface.goals.symbol) }
                .tag(DemoSurface.goals)

            WardrobeView(wardrobe: $wardrobe, day: $day)
                .tabItem { Label(DemoSurface.wardrobe.title, systemImage: DemoSurface.wardrobe.symbol) }
                .tag(DemoSurface.wardrobe)

            ReviewView(entries: $entries, day: day)
                .tabItem { Label(DemoSurface.review.title, systemImage: DemoSurface.review.symbol) }
                .tag(DemoSurface.review)

            YouView(email: auth.email, open: open)
                .tabItem { Label(DemoSurface.you.title, systemImage: DemoSurface.you.symbol) }
                .tag(DemoSurface.you)
        }
        .tint(Tok.accent)
        .overlay(alignment: .bottomTrailing) { captureButton }
        .sheet(isPresented: $capturing) {
            CaptureSheet(goals: $goals, day: $day, wardrobe: wardrobe)
        }
        .sheet(isPresented: $showingAccount) {
            AccountView(email: auth.email)
        }
    }

    /// One control, on every surface, for the thought you had while doing something else.
    private var captureButton: some View {
        Button {
            capturing = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Tok.surface)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(colors: [Tok.accent, Tok.accent.opacity(0.86)], startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .shadow(color: Tok.accent.opacity(0.35), radius: 14, y: 6)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 68)
        .accessibilityLabel("Capture")
    }

    private func open(_ destination: Destination) {
        switch destination {
        case .wardrobe: surface = .wardrobe
        case .review: surface = .review
        case .goals: surface = .goals
        }
    }

    enum Destination { case wardrobe, review, goals }
}

#Preview {
    ProductivityDemoShell().environment(AuthService())
}
