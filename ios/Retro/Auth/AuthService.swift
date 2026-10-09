import ClerkKit
import Foundation

enum AuthState: Equatable {
    case loading
    case signedOut
    case signedIn(userId: String, email: String?)
}

/// Identity for the whole app: Clerk, the same instance the router verifies. There is no guest mode — records live on
/// the server, so a signed-out app has nothing to show.
@MainActor
@Observable
final class AuthService {
    /// Clerk could not finish starting (offline first launch). Show the sign-in screen rather than a blank one.
    private var loadTimedOut = false

    init() {
        if Config.devEngineURL != nil { return }
        Clerk.configure(publishableKey: Config.clerkPublishableKey)
        Task { try? await Task.sleep(for: .seconds(8)); loadTimedOut = true }
    }

    var state: AuthState {
        if Config.devEngineURL != nil { return .signedIn(userId: "dev_user", email: "dev@local") }
        if let user = Clerk.shared.user {
            return .signedIn(userId: user.id, email: user.primaryEmailAddress?.emailAddress)
        }
        return Clerk.shared.isLoaded || loadTimedOut ? .signedOut : .loading
    }

    var userId: String? {
        if case .signedIn(let id, _) = state { return id }
        return nil
    }

    /// Opens Google sign-in. Returns a message to show the user, or nil on success.
    func signInWithGoogle() async -> String? {
        if Config.devEngineURL != nil { return nil }
        do {
            try await Clerk.shared.auth.signInWithOAuth(provider: .google)
            return nil
        } catch {
            return "Couldn't sign in with Google. Check your connection and try again."
        }
    }

    func signOut() async {
        guard Config.devEngineURL == nil else { return }
        let owner = userId
        try? await Clerk.shared.auth.signOut()
        if userId != owner, let owner { DiskCache(owner: owner).wipeCaches() }
    }

    /// A session token for the router, or nil when signed out or offline. `skipCache` forces a fresh one.
    func token(skipCache: Bool = false) async -> String? {
        if Config.devEngineURL != nil { return "dev" }
        guard Clerk.shared.session != nil else { return nil }
        return try? await Clerk.shared.auth.getToken(.init(skipCache: skipCache))
    }
}
