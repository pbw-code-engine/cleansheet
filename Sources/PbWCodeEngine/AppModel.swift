import SwiftUI
import AppKit
import CodeEngineCore

enum Tab: String, CaseIterable, Identifiable {
    case scan = "Varredura", map = "Mapa", duplicates = "Duplicatas", apps = "Apps"
    case startup = "Inicialização", quarantine = "Quarentena", report = "Relatório"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: Tab = .scan
    @Published var status = "Pronto. Nada foi apagado."
    @Published var busy = false
    @Published var showPalette = false

    // Varredura
    @Published var items: [CleanItem] = []
    @Published var selected: Set<String> = []
    @Published var focused: CleanItem?
    @Published var confirmingMove = false

    // Duplicatas
    @Published var groups: [DuplicateGroup] = []
    @Published var dupSelected: Set<URL> = []
    @Published var dupFolder: URL?

    // Mapa
    @Published var mapPath: [URL] = []
    @Published var mapNodes: [DiskNode] = []

    // Apps
    @Published var apps: [InstalledApp] = []
    @Published var focusedApp: InstalledApp?
    @Published var leftovers: [AppLeftover] = []

    // Inicialização / Quarentena / Relatório
    @Published var agents: [LaunchAgent] = []
    @Published var quarantined: [QuarantineEntry] = []
    @Published var log: [ActivityLog.Line] = []

    let quarantine = Quarantine()

    init() {
        quarantine.purgeExpired()
        refreshQuarantine()
    }

    var selectedBytes: Int64 {
        items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    // MARK: Varredura
    func scan() {
        busy = true; status = "Procurando…"
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task.detached { [weak self] in
            let found = Scanner(runningBundleIDs: running).scan { cat in
                Task { @MainActor in self?.status = "Procurando: \(cat)" }
            }
            await MainActor.run {
                guard let self else { return }
                self.items = found
                self.selected = Set(found.filter { $0.confidence == .high && $0.skipReason == nil }.map(\.id))
                self.focused = found.first
                self.busy = false
                self.status = "\(found.count) itens, \(DiskSize.format(found.reduce(0) { $0 + $1.size })) encontrados. Revise antes de mover."
            }
        }
    }

    func moveSelectedToQuarantine() {
        var moved: Int64 = 0, failures: [String] = []
        for item in items where selected.contains(item.id) && item.skipReason == nil {
            do { try quarantine.add(item.url, size: item.size, scope: .automatic, source: item.category); moved += item.size }
            catch { failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)") }
        }
        items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        selected.formIntersection(Set(items.map(\.id)))
        refreshQuarantine()
        status = "\(DiskSize.format(moved)) movidos para a Quarentena (restauráveis por 30 dias)." + (failures.isEmpty ? "" : " \(failures.count) falharam: \(failures[0])")
    }

    // MARK: Duplicatas
    func pickFolderAndFindDuplicates() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Procurar aqui"
        guard p.runModal() == .OK, let url = p.url else { return }
        dupFolder = url; busy = true; status = "Comparando arquivos em \(url.lastPathComponent)…"
        Task.detached { [weak self] in
            let g = Duplicates.find(in: url)
            await MainActor.run {
                guard let self else { return }
                self.groups = g
                // Por padrão marca todas as cópias, menos a primeira de cada grupo.
                self.dupSelected = Set(g.flatMap { $0.files.dropFirst() })
                self.busy = false
                self.status = "\(g.count) grupos; \(DiskSize.format(g.reduce(0) { $0 + $1.reclaimable })) recuperáveis. A primeira cópia de cada grupo é mantida."
            }
        }
    }

    func moveSelectedDuplicates() {
        var moved: Int64 = 0, failed = 0
        for g in groups {
            // Nunca remove todas as cópias de um grupo.
            let chosen = g.files.filter { dupSelected.contains($0) }
            guard chosen.count < g.files.count else { failed += chosen.count; continue }
            for f in chosen {
                do { try quarantine.add(f, size: g.size, scope: .userSelected, source: "Duplicata"); moved += g.size } catch { failed += 1 }
            }
        }
        groups = groups.compactMap { g in
            let left = g.files.filter { FileManager.default.fileExists(atPath: $0.path) }
            return left.count > 1 ? DuplicateGroup(hash: g.hash, size: g.size, files: left) : nil
        }
        dupSelected = []
        refreshQuarantine()
        status = "\(DiskSize.format(moved)) de duplicatas na Quarentena." + (failed > 0 ? " \(failed) não foram movidas." : "")
    }

    // MARK: Mapa
    func openMap(_ url: URL, push: Bool = true) {
        busy = true; status = "Medindo \(url.lastPathComponent)…"
        if push { mapPath.append(url) }
        Task.detached { [weak self] in
            let nodes = DiskMap.children(of: url)
            await MainActor.run { self?.mapNodes = nodes; self?.busy = false; self?.status = "\(url.path)" }
        }
    }
    func mapBack() {
        guard mapPath.count > 1 else { return }
        mapPath.removeLast(); openMap(mapPath.last!, push: false)
    }
    func mapPickRoot() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { mapPath = []; openMap(u) }
    }

    // MARK: Apps
    func loadApps() {
        busy = true
        Task.detached { [weak self] in
            let list = Apps.list()
            await MainActor.run { self?.apps = list; self?.busy = false; self?.status = "\(list.count) apps (apps da Apple não são listados)." }
        }
    }
    func focus(app: InstalledApp) {
        focusedApp = app
        leftovers = Apps.leftovers(for: app)
    }
    func uninstallFocusedApp() {
        guard let app = focusedApp else { return }
        var failures: [String] = []
        for l in leftovers { do { try quarantine.add(l.url, size: l.size, scope: .userSelected, source: "Resto de \(app.name)") } catch { failures.append(error.localizedDescription) } }
        do { try quarantine.add(app.url, size: app.size, scope: .userSelected, source: "App \(app.name)") } catch { failures.append(error.localizedDescription) }
        apps.removeAll { $0.id == app.id }; focusedApp = nil; leftovers = []
        refreshQuarantine()
        status = failures.isEmpty ? "\(app.name) movido para a Quarentena." : "Falhou: \(failures[0])"
    }

    // MARK: Inicialização
    func loadAgents() { agents = Startup.list() }
    func disable(_ a: LaunchAgent) {
        do { try quarantine.add(a.url, size: 0, scope: .userSelected, source: "Agente de inicialização"); loadAgents(); refreshQuarantine(); status = "\(a.label) desativado (vale no próximo login)." }
        catch { status = error.localizedDescription }
    }

    // MARK: Quarentena / Relatório
    func refreshQuarantine() {
        quarantined = quarantine.entries().sorted { $0.date > $1.date }
        log = ActivityLog.shared.lines()
    }
    func restore(_ e: QuarantineEntry) {
        do { try quarantine.restore(e); status = "Restaurado: \(e.originalPath)" } catch { status = error.localizedDescription }
        refreshQuarantine()
    }
    func purge(_ e: QuarantineEntry) { try? quarantine.purge(e); refreshQuarantine(); status = "Excluído definitivamente." }

    // MARK: ⌘K
    struct Command: Identifiable { let id = UUID(); let title: String; let run: () -> Void }
    func commands() -> [Command] {
        var c = Tab.allCases.map { t in Command(title: "Ir para \(t.rawValue)") { [unowned self] in self.tab = t } }
        c.append(Command(title: "Varrer agora") { [unowned self] in self.tab = .scan; self.scan() })
        c.append(Command(title: "Procurar duplicatas…") { [unowned self] in self.tab = .duplicates; self.pickFolderAndFindDuplicates() })
        return c
    }
}
