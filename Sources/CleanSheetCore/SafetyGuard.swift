import Foundation

/// Decides whether a path may be moved to Quarantine. Every destructive action goes through here.
public struct SafetyGuard {
    public enum Scope {
        /// Item found by an app rule.
        case automatic
        /// Item from a folder the user chose (duplicates, apps).
        case userSelected
    }

    public enum Verdict: Equatable {
        case allowed
        case denied(String)
    }

    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
    }

    static func components(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }

    static func isInside(_ child: [String], _ parent: [String]) -> Bool {
        child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }

    private func homePath(_ rel: String) -> [String] {
        home.appendingPathComponent(rel).pathComponents
    }

    private static let systemRoots = ["/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/dev", "/Library", "/private", "/cores", "/opt", "/Volumes"]
    private static let packageExtensions: Set<String> = ["photoslibrary", "musiclibrary", "tvlibrary", "fcpbundle", "logicx", "xcodeproj", "xcworkspace"]

    /// Checks the path and, if it is a symlink (even a broken one), its target too.
    public func check(_ url: URL, scope: Scope) -> Verdict {
        let v = checkPath(url, scope: scope)
        if case .denied = v { return v }
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            let target = URL(fileURLWithPath: dest, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            if case .denied(let why) = checkPath(target, scope: scope) { return .denied("Symlink to a protected area: \(why)") }
        }
        return .allowed
    }

    private func checkPath(_ url: URL, scope: Scope) -> Verdict {
        let path = Self.components(url)

        if path.count <= 1 { return .denied("System root.") }

        for root in Self.systemRoots where Self.isInside(path, URL(fileURLWithPath: root).pathComponents) {
            // /Applications is not in the list: installed apps may be uninstalled by the user.
            return .denied("System folder (\(root)).")
        }

        let homeParts = home.pathComponents
        if path == homeParts { return .denied("Entire home folder.") }
        // Never touch top-level home folders nor ~/Library itself (depth < 2).
        if Self.isInside(path, homeParts) && path.count - homeParts.count < 2 {
            return .denied("Top-level user folder.")
        }
        // A path that is an ancestor of something protected is also denied.
        for rel in ["Library/Keychains", ".ssh", ".gnupg"] where Self.isInside(homePath(rel), path) || Self.isInside(path, homePath(rel)) {
            return .denied("Contains keys or credentials.")
        }
        if Self.isInside(path, homePath("Library/Mobile Documents")) {
            return .denied("iCloud Drive documents.")
        }
        if Self.isInside(path, homePath("Library/Application Support/CleanSheet/Quarantine")) {
            return .denied("Already in Quarantine.")
        }
        if path.contains(where: { Self.packageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            // Library/project packages are never touched, even if the user picked them.
            return .denied("User library or project.")
        }

        if scope == .automatic {
            for rel in ["Documents", "Desktop", "Pictures", "Music", "Movies"] where Self.isInside(path, homePath(rel)) {
                return .denied("Protected personal folder (\(rel)).")
            }
        }
        return .allowed
    }
}
