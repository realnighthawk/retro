import SwiftUI

@main
struct RetroApp: App {
    @State private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .tint(Tok.accent)
        }
    }
}
