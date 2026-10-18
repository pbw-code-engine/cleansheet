import Foundation

/// Decide se um caminho pode ser movido para a quarentena. Toda ação destrutiva passa por aqui.
public struct SafetyGuard {
    public enum Scope {
        /// Item encontrado por uma regra do app.
        case automatic
        /// Item de uma pasta que o próprio usuário escolheu (duplicatas, apps).
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

    /// Avalia o caminho e, se for symlink (mesmo quebrado), também o destino dele.
    public func check(_ url: URL, scope: Scope) -> Verdict {
        let v = checkPath(url, scope: scope)
        if case .denied = v { return v }
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            let target = URL(fileURLWithPath: dest, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            if case .denied(let why) = checkPath(target, scope: scope) { return .denied("Symlink para área protegida: \(why)") }
        }
        return .allowed
    }

    private func checkPath(_ url: URL, scope: Scope) -> Verdict {
        let path = Self.components(url)

        if path.count <= 1 { return .denied("Raiz do sistema.") }

        for root in Self.systemRoots where Self.isInside(path, URL(fileURLWithPath: root).pathComponents) {
            // /Applications fica fora da lista: apps instalados podem ser desinstalados pelo usuário.
            return .denied("Pasta do sistema (\(root)).")
        }

        let homeParts = home.pathComponents
        if path == homeParts { return .denied("Pasta pessoal inteira.") }
        // Nunca apagar pastas de topo do home nem a ~/Library em si (profundidade < 2).
        if Self.isInside(path, homeParts) && path.count - homeParts.count < 2 {
            return .denied("Pasta de topo do usuário.")
        }
        // Se o caminho é ancestral de algo protegido, também é negado.
        for rel in ["Library/Keychains", ".ssh", ".gnupg"] where Self.isInside(homePath(rel), path) || Self.isInside(path, homePath(rel)) {
            return .denied("Contém chaves ou credenciais.")
        }
        if Self.isInside(path, homePath("Library/Mobile Documents")) {
            return .denied("Documentos do iCloud Drive.")
        }
        if Self.isInside(path, homePath("Library/Application Support/PbWCodeEngine/Quarantine")) {
            return .denied("Já está na quarentena.")
        }
        if path.contains(where: { Self.packageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            // Pacote de biblioteca/projeto: só é permitido apagar o pacote inteiro se o usuário o escolheu... e mesmo assim não.
            return .denied("Biblioteca ou projeto do usuário.")
        }

        if scope == .automatic {
            for rel in ["Documents", "Desktop", "Pictures", "Music", "Movies"] where Self.isInside(path, homePath(rel)) {
                return .denied("Pasta pessoal protegida (\(rel)).")
            }
        }
        return .allowed
    }
}
