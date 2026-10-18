import Foundation

public struct DiskNode: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let isDirectory: Bool
}

public enum DiskMap {
    /// Filhos imediatos de uma pasta com seus tamanhos, do maior para o menor.
    public static func children(of folder: URL) -> [DiskNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return [] }
        return items.map { u in
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDir = v?.isDirectory == true && v?.isSymbolicLink != true
            return DiskNode(url: u, size: DiskSize.of(u), isDirectory: isDir)
        }.sorted { $0.size > $1.size }
    }
}
