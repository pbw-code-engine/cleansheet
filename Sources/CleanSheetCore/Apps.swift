import Foundation

public struct InstalledApp: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let size: Int64
}

public struct AppLeftover: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
}

public enum Apps {
    public static func list(in folders: [URL] = [URL(fileURLWithPath: "/Applications")]) -> [InstalledApp] {
        let fm = FileManager.default
        var out: [InstalledApp] = []
        for dir in folders {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
                let bid = info?["CFBundleIdentifier"] as? String
                // Apple apps are never offered for removal.
                if bid?.hasPrefix("com.apple.") == true { continue }
                out.append(InstalledApp(url: url, name: url.deletingPathExtension().lastPathComponent, bundleID: bid, size: DiskSize.of(url)))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Looks for app files in known locations, by EXACT bundle ID match.
    public static func leftovers(for app: InstalledApp, home: URL = SafetyGuard().home) -> [AppLeftover] {
        guard let bid = app.bundleID, !bid.isEmpty else { return [] }
        let lib = home.appendingPathComponent("Library")
        let candidates = [
            "Application Support/\(bid)", "Caches/\(bid)", "Preferences/\(bid).plist", "Containers/\(bid)",
            "Saved Application State/\(bid).savedState", "Logs/\(bid)", "HTTPStorages/\(bid)", "WebKit/\(bid)",
        ]
        return candidates.compactMap { rel in
            let u = lib.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: u.path) else { return nil }
            return AppLeftover(url: u, size: DiskSize.of(u))
        }
    }
}
