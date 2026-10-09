import SwiftUI

struct ProvisionGate: View {
    let userId: String
    @Environment(AuthService.self) private var auth
    @State private var model: OnboardingModel?

    var body: some View {
        Group {
            if Config.devEngineURL != nil || model?.phase == .ready {
                AppShell(userId: userId)
            } else {
                VStack(spacing: 18) {
                    RetroMark(size: 72)
                    Text(model == nil || model?.phase == .checking ? "Checking your workspace" : model?.phase == .provisioning ? "Setting up your workspace" : "Your space for Retro")
                        .font(.title2.bold()).foregroundStyle(Tok.ink)
                    if model == nil || model?.phase == .checking || model?.phase == .provisioning {
                        ProgressView().tint(Tok.accent)
                        if model?.phase == .provisioning {
                            Text("You can leave and come back. Setup will carry on.")
                                .font(.body).foregroundStyle(Tok.faint)
                        }
                    } else {
                        Text("Create your private workspace, shared with your other Nighthawk apps.")
                            .font(.body).foregroundStyle(Tok.faint)
                        Button(model?.phase == .unavailable ? "Check setup again" : model?.phase == .failed ? "Try setup again" : "Create my workspace") {
                            Task {
                                if model?.phase == .unavailable { await model?.refresh() } else { await model?.start() }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle()).disabled(model?.working == true)
                    }
                    if let problem = model?.problem {
                        Text(problem).font(.footnote).foregroundStyle(Tok.stamp)
                    }
                    Button("Sign out") { Task { await auth.signOut() } }
                        .buttonStyle(PressStyle()).foregroundStyle(Tok.faint).frame(minHeight: 44)
                }
                .multilineTextAlignment(.center)
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tok.bg.ignoresSafeArea())
            }
        }
        .task(id: userId) {
            guard Config.devEngineURL == nil else { return }
            let engine = Engine(owner: userId, currentUser: { auth.userId }, token: { await auth.token(skipCache: $0) })
            let onboarding = OnboardingModel(status: { await engine.onboardingStatus() }, submit: { await engine.startOnboarding($0) })
            model = onboarding
            await onboarding.refresh()
        }
        .task(id: model?.phase) {
            if model?.phase == .provisioning { await model?.watch() }
        }
    }
}
