import SwiftUI

/// You: the system itself, and the only place the app talks about the app.
struct YouView: View {
    @Environment(AuthService.self) private var auth
    let email: String?
    let open: (ProductivityDemoShell.Destination) -> Void

    @State private var showingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    whatRetroKnows
                    howItReads
                    accountPanel
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Tok.bg)
            .navigationTitle("You")
            .sheet(isPresented: $showingAccount) {
                AccountView(email: email)
            }
        }
    }

    private var whatRetroKnows: some View {
        Panel(tint: Tok.accent) {
            SectionTitle(text: "What Retro knows", trailing: nil).padding(.horizontal, 2)
            HStack(spacing: 24) {
                stat("\(DemoData.goals.count)", "goals")
                stat("\(DemoData.wardrobe.count)", "pieces")
                stat("\(DemoData.entries.filter { !$0.cancelled }.count)", "days recorded")
            }
            Text("All of it on this device. The /retro engine is not connected yet.")
                .font(.caption)
                .foregroundStyle(Tok.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItReads: some View {
        Panel {
            SectionTitle(text: "How it reads your days", trailing: nil).padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 10) {
                rule("A missed day is drawn flat", "Never red. The app is not allowed to be disappointed in you.")
                rule("A void day is kept, not deleted", "Some days should not count. They still exist in the record.")
                rule("Numbers are readings, not scores", "A streak describes what happened. It is not something to protect.")
                rule("One thing gets the weight", "Everything else on Today is deliberately quieter than the one thing.")
            }
        }
    }

    private func rule(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Tok.ink)
            Text(detail).font(.caption).foregroundStyle(Tok.faint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountPanel: some View {
        Panel {
            SectionTitle(text: "Account", trailing: nil).padding(.horizontal, 2)
            Button {
                showingAccount = true
            } label: {
                HStack {
                    Text(email ?? "Your account")
                        .font(.body)
                        .foregroundStyle(Tok.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Tok.faint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).figures(.title2, weight: .semibold).foregroundStyle(Tok.ink)
            Text(label).font(.caption2).foregroundStyle(Tok.faint)
        }
    }
}
