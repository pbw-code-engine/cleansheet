import Foundation

public struct LaunchAgent: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let label: String
    public let program: String
}

public enum Startup {
    /// Agentes de inicialização do usuário (só leitura; remover = mover para a quarentena).
    public static func list(home: URL = SafetyGuard().home) -> [LaunchAgent] {
        let dir = home.appendingPathComponent("Library/LaunchAgents")
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "plist" }.compactMap { url in
            guard let d = NSDictionary(contentsOf: url) else { return nil }
            let label = d["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
            let program = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first ?? "—"
            return LaunchAgent(url: url, label: label, program: program)
        }.sorted { $0.label < $1.label }
    }
}
