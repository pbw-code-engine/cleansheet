import SwiftUI
import AppKit
import CleanSheetCore

@MainActor
final class MemoryModel: ObservableObject {
    @Published var snapshot = MemoryMonitor.read()
    @Published var apps: [AppCandidate] = []
    @Published var level: CloseLevel { didSet { defaults.set(level.rawValue, forKey: "memory.level") } }
    @Published var autoEnabled: Bool { didSet { defaults.set(autoEnabled, forKey: "memory.auto"); if autoEnabled { Notifier.requestIfNeeded() } } }
    @Published var threshold: Double { didSet { defaults.set(threshold, forKey: "memory.threshold") } }
    @Published var neverClose: Set<String> { didSet { defaults.set(Array(neverClose), forKey: "memory.never") } }
    @Published var lastResult = ""
    @Published var closing = false

    private let defaults = UserDefaults.standard
    private var lastActive: [Int32: Date] = [:]
    private var lastAuto = Date.distantPast
    private var timer: Timer?
    private let selfBundleID = Bundle.main.bundleIdentifier

    init() {
        level = CloseLevel(rawValue: defaults.string(forKey: "memory.level") ?? "") ?? .low
        autoEnabled = defaults.bool(forKey: "memory.auto")
        let t = defaults.double(forKey: "memory.threshold")
        threshold = t == 0 ? 88 : t
        neverClose = Set(defaults.stringArray(forKey: "memory.never") ?? [])
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.lastActive[app.processIdentifier] = Date() }
        }
        refresh()
        schedule(every: 5)
        // Window closed → poll every 20 s instead of 5 s: the same job at a fraction of the CPU.
        BackgroundManager.shared.visibilityHandlers.append { [weak self] visible in self?.schedule(every: visible ? 5 : 20) }
    }

    private func schedule(every seconds: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        t.tolerance = seconds * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// What the selected level would close right now.
    var targets: [AppCandidate] { level.select(apps, neverClose: neverClose) }
    var targetBytes: UInt64 { targets.reduce(0) { $0 + $1.memoryBytes } }

    var isUnderPressure: Bool { snapshot.pressure == .critical || snapshot.fraction * 100 >= threshold }

    func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let windows = Self.onScreenWindowCounts()
        let now = Date()
        let entries = running.map { (pid: $0.processIdentifier, id: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!, launch: $0.launchDate ?? now) }
        Task.detached { [weak self] in
            let rows = ProcessTable.current()
            let totals = ProcessTable.totals(for: entries.map(\.pid), in: rows)
            let snap = MemoryMonitor.read()
            await MainActor.run {
                guard let self else { return }
                self.snapshot = snap
                self.apps = entries.map { e in
                    AppCandidate(pid: e.pid, bundleID: e.id, name: e.name, memoryBytes: totals[e.pid] ?? 0,
                                 hasVisibleWindows: (windows[e.pid] ?? 0) > 0, isFrontmost: e.pid == front,
                                 idleSeconds: now.timeIntervalSince(self.lastActive[e.pid] ?? e.launch))
                }.sorted { $0.memoryBytes > $1.memoryBytes }
                self.autoCloseIfNeeded()
            }
        }
    }

    private static func onScreenWindowCounts() -> [Int32: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var out: [Int32: Int] = [:]
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = w[kCGWindowOwnerPID as String] as? Int32 { out[pid, default: 0] += 1 }
        }
        return out
    }

    // MARK: Closing
    private func autoCloseIfNeeded() {
        guard autoEnabled, !closing, isUnderPressure, Date().timeIntervalSince(lastAuto) > 120 else { return }
        lastAuto = Date()
        close(targets, reason: "auto/\(level.rawValue)")
    }

    func freeNow() { close(targets, reason: "manual/\(level.rawValue)") }

    private func close(_ list: [AppCandidate], reason: String) {
        guard !list.isEmpty else { lastResult = "Nothing to close at level \(level.rawValue)."; return }
        closing = true
        let before = snapshot.used
        var asked: [NSRunningApplication] = []
        for c in list {
            guard let app = NSRunningApplication(processIdentifier: c.pid), app.bundleIdentifier != selfBundleID else { continue }
            // Polite quit only: apps with unsaved work will ask the user to save.
            if app.terminate() { asked.append(app) }
            ActivityLog.shared.record("memory-close", "\(c.name) (\(DiskSize.format(Int64(c.memoryBytes)))) — \(reason)")
        }
        lastResult = "Asked \(asked.count) apps to quit…"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self else { return }
            let stuck = asked.filter { !$0.isTerminated }
            self.refresh()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let freed = Int64(before) - Int64(self.snapshot.used)
            self.lastResult = "Closed \(asked.count - stuck.count) of \(asked.count) apps, ~\(DiskSize.format(max(0, freed))) freed." +
                (stuck.isEmpty ? "" : " \(stuck.count) still open (probably asking to save): \(stuck.compactMap(\.localizedName).joined(separator: ", ")).")
            self.closing = false
            if reason.hasPrefix("auto"), !BackgroundManager.shared.windowVisible { Notifier.post("CleanSheet freed memory", self.lastResult) }
        }
    }

    func neverCloseToggle(_ id: String) {
        if neverClose.contains(id) { neverClose.remove(id) } else { neverClose.insert(id) }
    }
}
