import SwiftUI
import AppKit
import CleanSheetCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window keeps CleanSheet alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct CleanSheetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("CleanSheet", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands { AboutCommand() }

        MenuBarExtra("CleanSheet", systemImage: "sparkles") {
            TrayMenu().environmentObject(model)
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
    @Environment(\.openWindow) private var openWindow

    private var quarantineBytes: Int64 { m.quarantined.reduce(0) { $0 + $1.size } }

    var body: some View {
        Button("Open CleanSheet") { show() }
        Button("Scan Now") { show(); m.tab = .scan; m.scan() }
        Divider()
        Text(m.quarantined.isEmpty ? "Quarantine is empty" : "Quarantine: \(m.quarantined.count) items · \(DiskSize.format(quarantineBytes))")
        Button("Empty Quarantine…") { m.confirmAndPurgeAll() }.disabled(m.quarantined.isEmpty)
        Divider()
        Button("About CleanSheet") { openWindow(id: "about"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit CleanSheet") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "CleanSheet" }) { w.makeKeyAndOrderFront(nil) }
        else { openWindow(id: "main") }
    }
}
