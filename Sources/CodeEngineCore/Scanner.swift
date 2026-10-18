import Foundation

public enum Confidence: String, Codable {
    case high = "Alta"
    case medium = "Média"
}

public struct CleanItem: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let category: String
    public let confidence: Confidence
    public let reason: String
    /// Preenchido quando o item não deve ser tocado agora (ex.: app em uso).
    public let skipReason: String?
}

struct CleanRule {
    let category: String
    let relativePath: String
    let confidence: Confidence
    let reason: String
    /// Se verdadeiro, filhos cujo nome é um bundle ID de app em execução são pulados.
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
        CleanRule(category: "Caches de apps", relativePath: "Library/Caches", confidence: .high,
                  reason: "Caches são recriados automaticamente pelo app que os criou.", checksRunningApps: true),
        CleanRule(category: "Logs", relativePath: "Library/Logs", confidence: .high,
                  reason: "Registros de diagnóstico antigos; apps criam novos quando precisam.", checksRunningApps: false),
        CleanRule(category: "Xcode: DerivedData", relativePath: "Library/Developer/Xcode/DerivedData", confidence: .high,
                  reason: "Resultados de compilação; o Xcode reconstrói na próxima build.", checksRunningApps: false),
        CleanRule(category: "Xcode: suporte a dispositivos", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", confidence: .medium,
                  reason: "Símbolos de iOS baixados de aparelhos; são baixados de novo ao conectar o aparelho.", checksRunningApps: false),
        CleanRule(category: "Simuladores: caches", relativePath: "Library/Developer/CoreSimulator/Caches", confidence: .medium,
                  reason: "Cache de simuladores iOS, recriado quando necessário.", checksRunningApps: false),
        CleanRule(category: "npm", relativePath: ".npm/_cacache", confidence: .high,
                  reason: "Cache de pacotes do npm; baixado de novo sob demanda.", checksRunningApps: false),
        CleanRule(category: "Gradle", relativePath: ".gradle/caches", confidence: .medium,
                  reason: "Dependências baixadas do Gradle; a próxima build baixa de novo.", checksRunningApps: false),
        CleanRule(category: "Cargo (Rust)", relativePath: ".cargo/registry/cache", confidence: .medium,
                  reason: "Pacotes .crate baixados; o cargo baixa de novo.", checksRunningApps: false),
        CleanRule(category: "Instaladores .dmg", relativePath: "Downloads", confidence: .medium,
                  reason: "Imagens de disco em Downloads, normalmente já instaladas.", checksRunningApps: false,
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
                    skip = "O app está aberto agora."
                }
                let size = DiskSize.of(child)
                if size == 0 { continue }
                out.append(CleanItem(url: child, size: size, category: rule.category, confidence: rule.confidence, reason: rule.reason, skipReason: skip))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
