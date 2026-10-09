import AppIntents
import Foundation

struct AddRetroGarment: AppIntent {
    static var title: LocalizedStringResource = "Add a garment"
    static var description = IntentDescription("Open Retro's garment form for your review. Nothing is saved automatically.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult {
        WardrobeEntryPoint.shared.open(WardrobeEntryAction.add.url)
        return .result()
    }
}
struct SearchRetroWardrobe: AppIntent {
    static var title: LocalizedStringResource = "Search wardrobe"
    static var description = IntentDescription("Open a name search in your signed-in Retro wardrobe.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Garment name", default: "") var query: String
    @MainActor func perform() async throws -> some IntentResult {
        let action = WardrobeEntryAction.search(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard WardrobeEntryAction(url: action.url) != nil else { throw WardrobeWriteError("Use a garment name of at most 100 bytes without control characters.") }
        WardrobeEntryPoint.shared.open(action.url)
        return .result()
    }
}
struct OpenRetroToday: AppIntent {
    static var title: LocalizedStringResource = "Today's outfits"
    static var description = IntentDescription("Open today's outfits in Retro after unlocking and signing in.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult {
        WardrobeEntryPoint.shared.open(WardrobeEntryAction.today.url)
        return .result()
    }
}
struct RetroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddRetroGarment(), phrases: ["Add a garment in \(.applicationName)"], shortTitle: "Add garment", systemImageName: "hanger")
        AppShortcut(intent: SearchRetroWardrobe(), phrases: ["Search my wardrobe in \(.applicationName)"], shortTitle: "Search wardrobe", systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenRetroToday(), phrases: ["Open today's outfits in \(.applicationName)"], shortTitle: "Today's outfits", systemImageName: "sun.horizon")
    }
}
