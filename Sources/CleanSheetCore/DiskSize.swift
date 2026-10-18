import Foundation

public enum DiskSize {
    /// Allocated size on disk. Does not follow directory symlinks.
    public static func of(_ url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if v.isSymbolicLink == true || v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let f as URL in e {
            if let r = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]) { total += Int64(r.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    public static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: bytes)
    }
}
