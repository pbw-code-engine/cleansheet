import SwiftUI
import AppKit
import CleanSheetCore

enum Tab: String, CaseIterable, Identifiable {
    case scan = "Scan", memory = "Memory", map = "Disk Map", duplicates = "Duplicates", apps = "Apps"
    case startup = "Startup", quarantine = "Quarantine", report = "Activity"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: Tab = .scan
    @Published var status = "Ready. Nothing has been deleted."
    @Published var busy = false
    @Published var showPalette = false

    // Scan
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

    // Startup / Quarantine / Activity
    @Published var agents: [LaunchAgent] = []
    @Published var quarantined: [QuarantineEntry] = []
    @Published var log: [ActivityLog.Line] = []

    let quarantine = Quarantine()

    init() {
        quarantine.purgeExpired()
        // Developer aid: `CleanSheet --tab=Memory` opens straight on that tab.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--tab=") }), let t = Tab(rawValue: String(arg.dropFirst(6))) { tab = t }
        refreshQuarantine()
    }

    var selectedBytes: Int64 {
        items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    // MARK: Scan
    func scan() {
        busy = true; status = "Scanning…"
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task.detached { [weak self] in
            let found = Scanner(runningBundleIDs: running).scan { cat in
                Task { @MainActor in self?.status = "Scanning: \(cat)" }
            }
            await MainActor.run {
                guard let self else { return }
                self.items = found
                self.selected = Set(found.filter { $0.confidence == .high && $0.skipReason == nil }.map(\.id))
                self.focused = found.first
                self.busy = false
                self.status = "\(found.count) items, \(DiskSize.format(found.reduce(0) { $0 + $1.size })) found. Review before moving anything."
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
        status = "\(DiskSize.format(moved)) moved to Quarantine (restorable for 30 days)." + (failures.isEmpty ? "" : " \(failures.count) falharam: \(failures[0])")
    }

    // MARK: Duplicates
    func pickFolderAndFindDuplicates() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Scan here"
        guard p.runModal() == .OK, let url = p.url else { return }
        dupFolder = url; busy = true; status = "Comparing files in \(url.lastPathComponent)…"
        Task.detached { [weak self] in
            let g = Duplicates.find(in: url)
            await MainActor.run {
                guard let self else { return }
                self.groups = g
                // By default, select every copy except the first of each group.
                self.dupSelected = Set(g.flatMap { $0.files.dropFirst() })
                self.busy = false
                self.status = "\(g.count) groups; \(DiskSize.format(g.reduce(0) { $0 + $1.reclaimable })) reclaimable. The first copy of each group is kept."
            }
        }
    }

    func moveSelectedDuplicates() {
        var moved: Int64 = 0, failed = 0
        for g in groups {
            // Never remove every copy of a group.
            let chosen = g.files.filter { dupSelected.contains($0) }
            guard chosen.count < g.files.count else { failed += chosen.count; continue }
            for f in chosen {
                do { try quarantine.add(f, size: g.size, scope: .userSelected, source: "Duplicate"); moved += g.size } catch { failed += 1 }
            }
        }
        groups = groups.compactMap { g in
            let left = g.files.filter { FileManager.default.fileExists(atPath: $0.path) }
            return left.count > 1 ? DuplicateGroup(hash: g.hash, size: g.size, files: left) : nil
        }
        dupSelected = []
        refreshQuarantine()
        status = "\(DiskSize.format(moved)) of duplicates moved to Quarantine." + (failed > 0 ? " \(failed) could not be moved." : "")
    }

    // MARK: Disk Map
    func openMap(_ url: URL, push: Bool = true) {
        busy = true; status = "Measuring \(url.lastPathComponent)…"
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
            await MainActor.run { self?.apps = list; self?.busy = false; self?.status = "\(list.count) apps (Apple apps are not listed)." }
        }
    }
    func focus(app: InstalledApp) {
        focusedApp = app
        leftovers = Apps.leftovers(for: app)
    }
    func uninstallFocusedApp() {
        guard let app = focusedApp else { return }
        var failures: [String] = []
        for l in leftovers { do { try quarantine.add(l.url, size: l.size, scope: .userSelected, source: "Leftover of \(app.name)") } catch { failures.append(error.localizedDescription) } }
        do { try quarantine.add(app.url, size: app.size, scope: .userSelected, source: "App \(app.name)") } catch { failures.append(error.localizedDescription) }
        apps.removeAll { $0.id == app.id }; focusedApp = nil; leftovers = []
        refreshQuarantine()
        status = failures.isEmpty ? "\(app.name) moved to Quarantine." : "Failed: \(failures[0])"
    }

    // MARK: Startup
    func loadAgents() { agents = Startup.list() }
    func disable(_ a: LaunchAgent) {
        do { try quarantine.add(a.url, size: 0, scope: .userSelected, source: "Startup agent"); loadAgents(); refreshQuarantine(); status = "\(a.label) disabled (takes effect at next login)." }
        catch { status = error.localizedDescription }
    }

    // MARK: Quarantine / Activity
    func refreshQuarantine() {
        quarantined = quarantine.entries().sorted { $0.date > $1.date }
        log = ActivityLog.shared.lines()
    }
    func restore(_ e: QuarantineEntry) {
        do { try quarantine.restore(e); status = "Restored: \(e.originalPath)" } catch { status = error.localizedDescription }
        refreshQuarantine()
    }
    /// Used by the menu bar item, where a SwiftUI dialog is not available.
    func confirmAndPurgeAll() {
        refreshQuarantine()
        guard !quarantined.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Permanently delete \(quarantined.count) items?"
        alert.informativeText = "\(DiskSize.format(quarantined.reduce(0) { $0 + $1.size })) will be freed. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete permanently")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { purgeAll() }
    }

    func purgeAll() {
        let freed = quarantine.purgeAll()
        refreshQuarantine()
        status = "Quarantine emptied. \(DiskSize.format(freed)) freed."
    }
    func purge(_ e: QuarantineEntry) { try? quarantine.purge(e); refreshQuarantine(); status = "Permanently deleted." }

    // MARK: ⌘K
    struct Command: Identifiable { let id = UUID(); let title: String; let run: () -> Void }
    func commands() -> [Command] {
        var c = Tab.allCases.map { t in Command(title: "Go to \(t.rawValue)") { [unowned self] in self.tab = t } }
        c.append(Command(title: "Scan now") { [unowned self] in self.tab = .scan; self.scan() })
        c.append(Command(title: "Find duplicates…") { [unowned self] in self.tab = .duplicates; self.pickFolderAndFindDuplicates() })
        return c
    }
}
