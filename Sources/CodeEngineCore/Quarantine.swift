import Foundation

public struct QuarantineEntry: Codable, Identifiable, Hashable {
    public let id: UUID
    public let originalPath: String
    public let storedName: String
    public let size: Int64
    public let date: Date
    public let source: String
}

public enum QuarantineError: Error, LocalizedError {
    case denied(String)
    case restoreTargetExists(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .denied(let why): return "Bloqueado pela proteção: \(why)"
        case .restoreTargetExists(let p): return "Já existe um item em \(p)."
        case .notFound: return "Item não encontrado na quarentena."
        }
    }
}

/// Cofre onde os itens ficam por 30 dias antes da exclusão definitiva.
public final class Quarantine {
    public static let retentionDays = 30

    public let root: URL
    private let guardian: SafetyGuard
    private let fm = FileManager.default
    private var manifestURL: URL { root.appendingPathComponent("manifest.json") }

    public init(root: URL? = nil, guardian: SafetyGuard = SafetyGuard()) {
        self.guardian = guardian
        self.root = root ?? guardian.home.appendingPathComponent("Library/Application Support/PbWCodeEngine/Quarantine")
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    public func entries() -> [QuarantineEntry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([QuarantineEntry].self, from: data)) ?? []
    }

    private func save(_ list: [QuarantineEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(list).write(to: manifestURL, options: .atomic)
    }

    @discardableResult
    public func add(_ url: URL, size: Int64, scope: SafetyGuard.Scope, source: String) throws -> QuarantineEntry {
        if case .denied(let why) = guardian.check(url, scope: scope) { throw QuarantineError.denied(why) }
        let id = UUID()
        let dir = root.appendingPathComponent(id.uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        // Move o caminho original (sem seguir symlink): um symlink é movido como symlink.
        try fm.moveItem(at: url, to: dir.appendingPathComponent(name))
        let entry = QuarantineEntry(id: id, originalPath: url.path, storedName: name, size: size, date: Date(), source: source)
        try save(entries() + [entry])
        ActivityLog.shared.record("quarentena", "\(url.path) (\(size) bytes) — \(source)")
        return entry
    }

    public func restore(_ entry: QuarantineEntry) throws {
        let stored = root.appendingPathComponent(entry.id.uuidString).appendingPathComponent(entry.storedName)
        guard fm.fileExists(atPath: stored.path) || (try? stored.checkResourceIsReachable()) != nil else { throw QuarantineError.notFound }
        let target = URL(fileURLWithPath: entry.originalPath)
        if fm.fileExists(atPath: target.path) { throw QuarantineError.restoreTargetExists(target.path) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: stored, to: target)
        try? fm.removeItem(at: root.appendingPathComponent(entry.id.uuidString))
        try save(entries().filter { $0.id != entry.id })
        ActivityLog.shared.record("restaurado", entry.originalPath)
    }

    public func purge(_ entry: QuarantineEntry) throws {
        try? fm.removeItem(at: root.appendingPathComponent(entry.id.uuidString))
        try save(entries().filter { $0.id != entry.id })
        ActivityLog.shared.record("excluído-definitivo", entry.originalPath)
    }

    public func purgeExpired(now: Date = Date()) {
        let limit = TimeInterval(Self.retentionDays * 86_400)
        for e in entries() where now.timeIntervalSince(e.date) > limit { try? purge(e) }
    }
}
