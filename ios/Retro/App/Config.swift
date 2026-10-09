import Foundation

/// Everything the app needs to know about where it runs. The values live in Info.plist (set in `project.yml`), so there
/// is no secrets file and no build-time code generation; the Clerk publishable key is public by design.
enum Config {
    static let routerBaseURL: String = info("RouterBaseURL")
    static let clerkPublishableKey: String = info("ClerkPublishableKey")

    /// This service's path on the shared router. Everything else in the family has one (`/finance`, `/maps`).
    static let servicePath = "/retro"

    /// DEBUG only: `-dev-engine <url>` points the app at an engine running on this Mac and skips Clerk entirely, which
    /// is how the UI tests drive the real screens. Release builds ignore it.
    static var devEngineURL: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-dev-engine"), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }

    /// DEBUG only: `-demo-tab <today|wardrobe|history>` opens straight onto one surface, so a screen can be
    /// captured or tested without walking the tabs to reach it. Release builds ignore it.
    static var devSurface: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demo-tab"), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }

    /// DEBUG only: `-demo-hour <0-23>` pins the clock, so the day arc's focal moment can be seen and captured at a
    /// chosen hour and UI tests do not depend on when they run. Release builds ignore it.
    static var devHour: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demo-hour"), i + 1 < args.count, let hour = Int(args[i + 1]) {
            return min(23, max(0, hour))
        }
        #endif
        return nil
    }

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }
}
