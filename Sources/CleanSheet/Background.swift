import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications

/// Keeps CleanSheet useful when no window is open: it lives in the menu bar, can start at login without
/// opening a window, drops its Dock icon while hidden, and stays awake enough to keep watching memory.
@MainActor
final class BackgroundManager: ObservableObject {
    static let shared = BackgroundManager()
    private let d = UserDefaults.standard

    /// No Dock icon while every CleanSheet window is closed (the menu bar item stays).
    @Published var hideDock: Bool { didSet { d.set(hideDock, forKey: "bg.hideDock"); evaluate() } }
    /// When started at login, don't open the window.
    @Published var startHidden: Bool { didSet { d.set(startHidden, forKey: "bg.startHidden") } }
    @Published var showPercent: Bool { didSet { d.set(showPercent, forKey: "bg.showPercent") } }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNote = ""
    /// True while any CleanSheet window is on screen. The memory monitor polls less often when it is false.
    @Published private(set) var windowVisible = true
    var visibilityHandlers: [(Bool) -> Void] = []

    private var activity: NSObjectProtocol?
    private var started = false

    init() {
        hideDock = d.object(forKey: "bg.hideDock") as? Bool ?? true
        startHidden = d.object(forKey: "bg.startHidden") as? Bool ?? true
        showPercent = d.object(forKey: "bg.showPercent") as? Bool ?? true
        refreshLogin()
    }

    // MARK: Launch at login

    func refreshLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: launchAtLogin = true; loginNote = ""
        case .requiresApproval:
            launchAtLogin = true
            loginNote = "Approve CleanSheet in System Settings › General › Login Items."
        default: launchAtLogin = false; loginNote = ""
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNote = ""
        } catch {
            loginNote = "Couldn't change the login item: \(error.localizedDescription). Move CleanSheet to /Applications and try again."
        }
        refreshLogin()
    }

    /// Was this launch started by the login item (or asked to stay hidden)?
    var launchedHidden: Bool {
        if CommandLine.arguments.contains("--background") { return true }
        guard startHidden, launchAtLogin else { return false }
        if let ev = NSAppleEventManager.shared().currentAppleEvent,
           ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(0x6C676974) { return true } // 'lgit'
        return ProcessInfo.processInfo.systemUptime < 240            // fallback: right after boot / login
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        // Memory watching must not be throttled by App Nap while the app is hidden.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                         reason: "CleanSheet watches memory in the background")
        ProcessInfo.processInfo.disableAutomaticTermination("CleanSheet runs in the background")
        let nc = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard let w = n.object as? NSWindow, Self.isOurs(w) else { return }
                DispatchQueue.main.async { Task { @MainActor in self?.evaluate() } }
            }
        }
    }

    nonisolated static func isOurs(_ w: NSWindow) -> Bool { w.title == "CleanSheet" || w.title == "About CleanSheet" }

    /// Window on screen → regular app with Dock icon. No window → menu bar only (if enabled).
    func evaluate() {
        let visible = NSApp.windows.contains { Self.isOurs($0) && ($0.isVisible || $0.isMiniaturized) }
        if visible != windowVisible { windowVisible = visible; visibilityHandlers.forEach { $0(visible) } }
        if visible { NSApp.setActivationPolicy(.regular) }
        else if hideDock { NSApp.setActivationPolicy(.accessory) }
    }

    func enterForeground() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Launched in the background: no Dock icon, and close the window SwiftUI opens by default.
    func hideAtLaunch() {
        NSApp.setActivationPolicy(.accessory)
        for delay in [0.0, 0.25, 0.7, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                NSApp.windows.filter { $0.title == "CleanSheet" }.forEach { $0.close() }
                self?.evaluate()
            }
        }
    }
}

/// Banner shown after an automatic clean-up that happened while the window was closed.
enum Notifier {
    private static var available: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    static func requestIfNeeded() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// Settings block shown in the Memory tab.
struct BackgroundPanel: View {
    @ObservedObject private var bg = BackgroundManager.shared

    var body: some View {
        Text("Background").font(.system(size: 15, weight: .bold))
        Toggle("Start at login", isOn: Binding(get: { bg.launchAtLogin }, set: { bg.setLaunchAtLogin($0) }))
            .toggleStyle(.switch).tint(Theme.accentA)
        Toggle("Start hidden (menu bar only)", isOn: $bg.startHidden).toggleStyle(.switch).tint(Theme.accentA)
        Toggle("Hide the Dock icon when the window is closed", isOn: $bg.hideDock).toggleStyle(.switch).tint(Theme.accentA)
        Toggle("Show memory % in the menu bar", isOn: $bg.showPercent).toggleStyle(.switch).tint(Theme.accentA)
        if !bg.loginNote.isEmpty {
            Text(bg.loginNote).font(.system(size: 11)).foregroundColor(Theme.accentB).fixedSize(horizontal: false, vertical: true)
        }
        Text("Closing the window doesn't quit CleanSheet: it keeps watching memory (and running Automatic mode) from the menu bar. Quit it from the menu bar icon.")
            .font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
    }
}

/// What appears in the menu bar: the icon plus (optionally) live memory use.
struct MenuBarLabel: View {
    @ObservedObject var mem: MemoryModel
    @ObservedObject private var bg = BackgroundManager.shared
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            if bg.showPercent { Text("\(Int(mem.snapshot.fraction * 100))%").monospacedDigit() }
        }
    }
}
