import SwiftUI

@main
struct RetroApp: App {
    @State private var auth = AuthService()
    @State private var entryPoint = WardrobeEntryPoint.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(entryPoint)
                .onOpenURL { entryPoint.open($0) }
                .onChange(of: auth.userId) { old, new in if old != nil && old != new { entryPoint.pending = nil } }
                .tint(Tok.accent)
        }
    }
}
