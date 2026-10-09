import SwiftUI

struct AppShell: View {
    let userId: String
    @Environment(AuthService.self) private var auth
    @Environment(WardrobeEntryPoint.self) private var entryPoint
    @State private var store: WardrobeStore?
    @State private var surface = Config.devSurface ?? "today"
    @State private var showingAccount = false
    @State private var showingPending = false
    @State private var showingSettings = false
    @State private var shortcutAdding = false
    @State private var shortcutSearch = ""
    @State private var navigationID = UUID()
    @State private var reachability = Reachability()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let store {
                TabView(selection: $surface) {
                    NavigationStack {
                        WardrobeTodayView(store: store)
                            .toolbar { accountControl }
                    }
                    .tabItem { Label("Today", systemImage: "sun.horizon") }.tag("today")

                    NavigationStack {
                        WardrobeInventoryView(store: store, initialSearch: shortcutSearch)
                            .toolbar { accountControl }
                    }
                    .tabItem { Label("Wardrobe", systemImage: "hanger") }.tag("wardrobe")

                    NavigationStack {
                        WardrobeHistoryView(store: store)
                            .toolbar { accountControl }
                    }
                    .tabItem { Label("History", systemImage: "clock") }.tag("history")
                }
                .id(navigationID)
                .tint(Tok.accent)
            } else {
                ProgressView("Opening your wardrobe")
            }
        }
        .task(id: userId) {
            guard store == nil else { return }
            if !["today", "wardrobe", "history"].contains(surface) { surface = "today" }
            let engine = Engine(owner: userId, currentUser: { auth.userId }, token: { await auth.token(skipCache: $0) })
            store = WardrobeStore(engine: engine)
        }
        .sheet(isPresented: $showingAccount) { AccountView(email: auth.email) }
        .sheet(isPresented: $showingPending) { if let store { WardrobePendingView(store: store) } }
        .sheet(isPresented: $showingSettings) { if let store { WardrobeSettingsView(store: store, record: .preferences) } }
        .sheet(isPresented: $shortcutAdding) { if let store { WardrobeGarmentEditor(store: store) } }
        .onChange(of: entryPoint.pending?.id) { _, _ in applyEntry() }
        .onChange(of: store != nil) { _, _ in applyEntry() }
        .onChange(of: scenePhase) { _, value in
            store?.photos.foreground = value != .background
            if value == .background { store?.assistant.pause() }
        }
        .onChange(of: auth.userId) { _, value in if value != userId { store?.assistant.pause() } }
        .onDisappear { store?.assistant.pause() }
        .task(id: scenePhase) { if scenePhase == .active { await store?.sync() } }
        .task(id: reachability.online) { if reachability.online { await store?.sync() } }
        .task(id: store != nil) { await store?.sync() }
    }

    private func applyEntry() {
        guard let store, let action = entryPoint.consume(owner: store.isCurrentOwner) else { return }
        showingAccount = false; showingPending = false; shortcutAdding = false; shortcutSearch = ""
        navigationID = UUID()
        switch action {
        case .add: surface = "wardrobe"; shortcutAdding = true
        case .search(let text): shortcutSearch = text; surface = "wardrobe"
        case .today: surface = "today"
        }
    }

    @ToolbarContentBuilder private var accountControl: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Wardrobe settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingPending = true } label: {
                Image(systemName: "arrow.triangle.2.circlepath").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Pending saves, \((store?.writes.items.count ?? 0) + (store?.photos.batches.count ?? 0))")
            .overlay(alignment: .topTrailing) {
                let count = (store?.writes.items.count ?? 0) + (store?.photos.batches.count ?? 0) + (store?.drafts.items.count ?? 0) + (store?.photos.drafts.count ?? 0)
                if count > 0 { Text("\(count)").font(.caption2).padding(3).background(Tok.surface, in: Circle()).accessibilityHidden(true) }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingAccount = true } label: {
                Image(systemName: "person.crop.circle").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Account")
        }
    }
}
