import Foundation
import CryptoKit

public struct DuplicateGroup: Identifiable, Hashable {
    public var id: String { hash }
    public let hash: String
    public let size: Int64
    public let files: [URL]
    public init(hash: String, size: Int64, files: [URL]) { self.hash = hash; self.size = size; self.files = files }
    /// Espaço recuperável mantendo uma cópia.
    public var reclaimable: Int64 { size * Int64(files.count - 1) }
}

public enum Duplicates {
    static func sha256(_ url: URL, limit: Int? = nil) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            let chunk = min(1 << 20, remaining)
            guard let data = try? h.read(upToCount: chunk), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Agrupa por tamanho, depois por hash dos primeiros 64 KB, depois por hash completo.
    public static func find(in folder: URL, minSize: Int64 = 1 << 20, progress: ((Int) -> Void)? = nil) -> [DuplicateGroup] {
        let fm = FileManager.default
        var bySize: [Int64: [URL]] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isPackageKey]
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var seen = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let size = Int64(v.fileSize ?? 0)
            if size >= minSize { bySize[size, default: []].append(f) }
            seen += 1
            if seen % 500 == 0 { progress?(seen) }
        }
        var groups: [DuplicateGroup] = []
        for (size, files) in bySize where files.count > 1 {
            var byPartial: [String: [URL]] = [:]
            for f in files { if let h = sha256(f, limit: 65_536) { byPartial[h, default: []].append(f) } }
            for (_, candidates) in byPartial where candidates.count > 1 {
                var byFull: [String: [URL]] = [:]
                for f in candidates { if let h = sha256(f) { byFull[h, default: []].append(f) } }
                for (h, same) in byFull where same.count > 1 {
                    groups.append(DuplicateGroup(hash: h, size: size, files: same.sorted { $0.path < $1.path }))
                }
            }
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }
}
