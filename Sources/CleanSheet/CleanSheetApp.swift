import SwiftUI
import AppKit
import CleanSheetCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window keeps CleanSheet alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let bg = BackgroundManager.shared
        bg.start()
        if bg.launchedHidden { bg.hideAtLaunch() }
        else { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    }

    /// Clicking the app in Finder / Spotlight while it runs in the background brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        BackgroundManager.shared.enterForeground()
        if !flag { _ = NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil) }
        return true
    }
}

@main
struct CleanSheetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var memory = MemoryModel()

    var body: some Scene {
        WindowGroup("CleanSheet", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(memory)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands { AboutCommand() }

        MenuBarExtra {
            TrayMenu().environmentObject(model).environmentObject(memory)
        } label: {
            MenuBarLabel(mem: memory)
        }

        Window("About CleanSheet", id: "about") {
            AboutView().preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CleanSheet") { openWindow(id: "about") }
        }
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 120, height: 120)
            Text("CleanSheet").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Version \(version)").font(.system(size: 12)).foregroundColor(Theme.dim)
            Text("A free, open-source Mac cleaner. No account, no tracking, nothing leaves your Mac. Everything you remove goes to Quarantine first.")
                .font(.system(size: 13)).multilineTextAlignment(.center).foregroundColor(Theme.dim).frame(maxWidth: 340)
            Divider().overlay(Theme.cardStroke).padding(.vertical, 4)
            VStack(spacing: 4) {
                Text("Developed by").font(.system(size: 11)).foregroundColor(Theme.dim)
                Text("PbW Code Engine").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
            }
            Text("Licensed under GPL-3.0").font(.system(size: 11)).foregroundColor(Theme.dim)
        }
        .padding(32).frame(width: 420)
        .background(Theme.background).foregroundColor(Theme.text)
    }
}

struct TrayMenu: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var mem: MemoryModel
    @ObservedObject private var bg = BackgroundManager.shared
    @Environment(\.openWindow) private var openWindow

    private var quarantineBytes: Int64 { m.quarantined.reduce(0) { $0 + $1.size } }

    var body: some View {
        Text("Memory: \(Int(mem.snapshot.fraction * 100))% used · \(mem.snapshot.pressure.label)")
        Button("Free Memory (\(mem.level.rawValue))") { mem.freeNow() }.disabled(mem.targets.isEmpty || mem.closing)
        Divider()
        Button("Open CleanSheet") { show() }
        Button("Scan Now") { show(); m.tab = .scan; m.scan() }
        Divider()
        Toggle("Start at login", isOn: Binding(get: { bg.launchAtLogin }, set: { bg.setLaunchAtLogin($0) }))
        Toggle("Hide Dock icon when window is closed", isOn: $bg.hideDock)
        Divider()
        Text(m.quarantined.isEmpty ? "Quarantine is empty" : "Quarantine: \(m.quarantined.count) items · \(DiskSize.format(quarantineBytes))")
        Button("Empty Quarantine…") { m.confirmAndPurgeAll() }.disabled(m.quarantined.isEmpty)
        Divider()
        Button("About CleanSheet") { openWindow(id: "about"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit CleanSheet") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show() {
        BackgroundManager.shared.enterForeground()
        if let w = NSApp.windows.first(where: { $0.title == "CleanSheet" }) { w.makeKeyAndOrderFront(nil) }
        else { openWindow(id: "main") }
    }
}
