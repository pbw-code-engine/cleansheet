import Foundation

public struct AppCandidate: Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let memoryBytes: UInt64
    public let hasVisibleWindows: Bool
    public let isFrontmost: Bool
    public let idleSeconds: TimeInterval

    public init(pid: Int32, bundleID: String, name: String, memoryBytes: UInt64, hasVisibleWindows: Bool, isFrontmost: Bool, idleSeconds: TimeInterval) {
        self.pid = pid; self.bundleID = bundleID; self.name = name; self.memoryBytes = memoryBytes
        self.hasVisibleWindows = hasVisibleWindows; self.isFrontmost = isFrontmost; self.idleSeconds = idleSeconds
    }
}

public enum CloseLevel: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High risk"
    case sweep = "Sweep"

    public var id: String { rawValue }

    public var summary: String {
        switch self {
        case .low: return "Apps with no visible window that you haven't touched for 10+ minutes and that use 150 MB or more."
        case .medium: return "Low, plus background apps idle for 30+ minutes that use 300 MB or more."
        case .high: return "Every app you aren't using right now that takes 100 MB or more. May ask you to save."
        case .sweep: return "Everything except protected apps, even the one in front. Last resort."
        }
    }

    /// Apps that are never closed at any level.
    public static let alwaysProtected: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight",
        "studio.pbw.cleansheet",
        // Terminals may be running long jobs.
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        // Media players: closing them cuts the sound.
        "com.spotify.client", "com.apple.Music",
    ]

    private static let MB: UInt64 = 1 << 20

    public func select(_ apps: [AppCandidate], neverClose: Set<String>) -> [AppCandidate] {
        let blocked = Self.alwaysProtected.union(neverClose)
        let eligible = apps.filter { !blocked.contains($0.bundleID) }
        let picked: [AppCandidate]
        switch self {
        case .low:
            picked = eligible.filter { Self.isLow($0) }
        case .medium:
            picked = eligible.filter { Self.isLow($0) || (!$0.isFrontmost && $0.idleSeconds >= 1800 && $0.memoryBytes >= 300 * Self.MB) }
        case .high:
            picked = eligible.filter { !$0.isFrontmost && $0.memoryBytes >= 100 * Self.MB }
        case .sweep:
            picked = eligible
        }
        return picked.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    private static func isLow(_ a: AppCandidate) -> Bool {
        !a.isFrontmost && !a.hasVisibleWindows && a.idleSeconds >= 600 && a.memoryBytes >= 150 * MB
    }
}
