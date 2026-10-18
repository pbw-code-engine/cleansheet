import Foundation

public enum Confidence: String, Codable {
    case high = "High"
    case medium = "Medium"
}

public struct CleanItem: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let category: String
    public let confidence: Confidence
    public let reason: String
    /// Set when the item should not be touched right now (e.g. app in use).
    public let skipReason: String?
}

struct CleanRule {
    let category: String
    let relativePath: String
    let confidence: Confidence
    let reason: String
    /// If true, children named after a running app's bundle ID are skipped.
    let checksRunningApps: Bool
    var fileFilter: ((URL) -> Bool)? = nil
}

public struct Scanner {
    private let home: URL
    private let guardian: SafetyGuard
    private let runningBundleIDs: Set<String>

    public init(guardian: SafetyGuard = SafetyGuard(), runningBundleIDs: Set<String>) {
        self.guardian = guardian
        self.home = guardian.home
        self.runningBundleIDs = runningBundleIDs
    }

    static let rules: [CleanRule] = [
        CleanRule(category: "App caches", relativePath: "Library/Caches", confidence: .high,
                  reason: "Caches are rebuilt automatically by the app that created them.", checksRunningApps: true),
        CleanRule(category: "Logs", relativePath: "Library/Logs", confidence: .high,
                  reason: "Old diagnostic logs; apps create new ones when needed.", checksRunningApps: false),
        CleanRule(category: "Xcode: DerivedData", relativePath: "Library/Developer/Xcode/DerivedData", confidence: .high,
                  reason: "Build output; Xcode rebuilds it on the next build.", checksRunningApps: false),
        CleanRule(category: "Xcode: device support", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", confidence: .medium,
                  reason: "iOS symbols downloaded from devices; fetched again when you reconnect the device.", checksRunningApps: false),
        CleanRule(category: "Simulator caches", relativePath: "Library/Developer/CoreSimulator/Caches", confidence: .medium,
                  reason: "iOS Simulator cache, recreated when needed.", checksRunningApps: false),
        CleanRule(category: "npm", relativePath: ".npm/_cacache", confidence: .high,
                  reason: "npm package cache; downloaded again on demand.", checksRunningApps: false),
        CleanRule(category: "Gradle", relativePath: ".gradle/caches", confidence: .medium,
                  reason: "Gradle downloaded dependencies; the next build fetches them again.", checksRunningApps: false),
        CleanRule(category: "Cargo (Rust)", relativePath: ".cargo/registry/cache", confidence: .medium,
                  reason: "Downloaded .crate packages; cargo fetches them again.", checksRunningApps: false),
        CleanRule(category: "Installer .dmg files", relativePath: "Downloads", confidence: .medium,
                  reason: "Disk images in Downloads, usually already installed.", checksRunningApps: false,
                  fileFilter: { $0.pathExtension.lowercased() == "dmg" }),
    ]

    public func scan(progress: ((String) -> Void)? = nil) -> [CleanItem] {
        let fm = FileManager.default
        var out: [CleanItem] = []
        for rule in Self.rules {
            progress?(rule.category)
            let dir = home.appendingPathComponent(rule.relativePath)
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else { continue }
            for child in children {
                if let filter = rule.fileFilter, !filter(child) { continue }
                if case .denied = guardian.check(child, scope: .automatic) { continue }
                var skip: String? = nil
                if rule.checksRunningApps, runningBundleIDs.contains(child.lastPathComponent) {
                    skip = "The app is open right now."
                }
                let size = DiskSize.of(child)
                if size == 0 { continue }
                out.append(CleanItem(url: child, size: size, category: rule.category, confidence: rule.confidence, reason: rule.reason, skipReason: skip))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
