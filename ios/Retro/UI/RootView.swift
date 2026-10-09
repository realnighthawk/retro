import SwiftUI

/// The whole app branches on one thing: who is signed in. A different user is a different shell, never a reused one.
struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack {
            Tok.bg.ignoresSafeArea()

            switch auth.state {
            case .loading:
                LoadingView().transition(.opacity)
            case .signedOut:
                WelcomeView().transition(.opacity)
            case .signedIn(let id, _):
                ProvisionGate(userId: id).id(id).transition(.opacity)
            }
        }
        .animation(Motion.state, value: auth.state)
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            RetroMark(size: 56)
            ProgressView().tint(Tok.accent)
        }
        .accessibilityLabel("Opening Retro")
    }
}

/// Sign-in. One quiet screen: the mark, what the app is for, and one action.
private struct WelcomeView: View {
    @Environment(AuthService.self) private var auth
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Tok.heroTop, Tok.heroBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                RetroMark(size: 78)

                Text("Retro")
                    .font(.system(size: 52, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Tok.ink)
                    .padding(.top, 22)

                Text("Your wardrobe, today's outfit, and a dependable history of what you wore.")
                    .font(.body)
                    .foregroundStyle(Tok.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Spacer()

                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Tok.stamp)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                Button {
                    Task {
                        working = true
                        problem = await auth.signInWithGoogle()
                        working = false
                    }
                } label: {
                    if working {
                        ProgressView().tint(Tok.surface)
                    } else {
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)

                Text("Your records stay yours. Nothing is shared.")
                    .font(.footnote)
                    .foregroundStyle(Tok.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 22)
        }
        .animation(Motion.state, value: problem)
    }
}

/// Account. A sheet for a self-contained task, and a standard grouped list inside it.
struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let email: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Signed in") {
                    Text(email ?? "Your account").font(.body)
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut(); dismiss() }
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension AuthService {
    /// The signed-in address, or nil. Kept here so views never reach into Clerk themselves.
    var email: String? {
        if case .signedIn(_, let email) = state { return email }
        return nil
    }
}
