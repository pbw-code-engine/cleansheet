import SwiftUI
import CleanSheetCore

private func listScroll<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    ScrollView { LazyVStack(spacing: 8) { content() }.padding(.horizontal, 16).padding(.vertical, 6) }
}

private func short(_ p: String) -> String { p.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

// MARK: Disk Map
struct MapView: View {
    @EnvironmentObject var m: AppModel
    var maxSize: Int64 { max(m.mapNodes.first?.size ?? 1, 1) }
    var body: some View {
        VStack(spacing: 0) {
            if m.mapPath.isEmpty {
                VStack(spacing: 22) {
                    Hero(symbol: "chart.pie.fill", title: "Where did the space go?", subtitle: "Pick a folder and see what takes the most room. This module is read-only.")
                    Button("Choose folder") { m.mapPickRoot() }.buttonStyle(PrimaryButton())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    Button { m.mapBack() } label: { Image(systemName: "chevron.left") }.buttonStyle(GhostButton()).disabled(m.mapPath.count < 2)
                    Text(short(m.mapPath.last!.path)).font(Theme.path(12)).foregroundColor(Theme.dim).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button("Another folder") { m.mapPickRoot() }.buttonStyle(GhostButton())
                }.padding(.horizontal, 16).padding(.vertical, 8)
                listScroll {
                    ForEach(m.mapNodes) { n in
                        Button { if n.isDirectory { m.openMap(n.url) } } label: {
                            HStack(spacing: 12) {
                                appIcon(n.url.path).resizable().frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(n.url.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); SizeBadge(bytes: n.size) }
                                    GeometryReader { g in
                                        Capsule().fill(Theme.accent).frame(width: max(4, g.size.width * CGFloat(n.size) / CGFloat(maxSize)), height: 6)
                                    }.frame(height: 6)
                                }
                                if n.isDirectory { Image(systemName: "chevron.right").foregroundColor(Theme.dim) }
                            }.padding(12).card().contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            ActionBar(summary: "Read-only: Disk Map never deletes or moves anything.") { EmptyView() }
        }
    }
}

// MARK: Duplicates
struct DuplicatesView: View {
    @EnvironmentObject var m: AppModel
    var selectedBytes: Int64 { m.groups.reduce(0) { $0 + $1.size * Int64($1.files.filter { m.dupSelected.contains($0) }.count) } }
    var body: some View {
        VStack(spacing: 0) {
            if m.groups.isEmpty {
                VStack(spacing: 22) {
                    Hero(symbol: "square.on.square", title: m.dupFolder == nil ? "Repeated files" : "No duplicates in \(m.dupFolder!.lastPathComponent)",
                         subtitle: "Compares files of 1 MB or more by content, not by name. At least one copy is always kept.")
                    Button("Choose folder") { m.pickFolderAndFindDuplicates() }.buttonStyle(PrimaryButton()).disabled(m.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listScroll {
                    ForEach(m.groups) { g in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { IconBubble(symbol: "doc.on.doc.fill", size: 30)
                                Text("\(g.files.count) copies").font(.system(size: 13, weight: .semibold)); Spacer(); SizeBadge(bytes: g.size) }
                            ForEach(Array(g.files.enumerated()), id: \.element) { idx, f in
                                let on = m.dupSelected.contains(f)
                                HStack(spacing: 8) {
                                    Button { if on { m.dupSelected.remove(f) } else { m.dupSelected.insert(f) } } label: {
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.dim))
                                    }.buttonStyle(.plain)
                                    Text(short(f.path)).font(Theme.path(10)).lineLimit(1).truncationMode(.middle)
                                    if idx == 0 { Text("keep").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.ok) }
                                }
                            }
                        }.padding(12).card()
                    }
                }
            }
            ActionBar(summary: "\(DiskSize.format(selectedBytes)) selected. At least one copy of each group is always kept.") {
                Button("Another folder") { m.pickFolderAndFindDuplicates() }.buttonStyle(GhostButton()).disabled(m.busy)
                Button("Move to Quarantine") { m.moveSelectedDuplicates() }.buttonStyle(PrimaryButton()).disabled(m.dupSelected.isEmpty)
            }
        }
    }
}

// MARK: Apps
struct AppsView: View {
    @EnvironmentObject var m: AppModel
    @State private var confirm = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                listScroll {
                    ForEach(m.apps) { a in
                        HStack(spacing: 12) {
                            appIcon(a.url.path).resizable().frame(width: 36, height: 36)
                            Text(a.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Spacer(); SizeBadge(bytes: a.size)
                        }.padding(10).card(highlighted: m.focusedApp?.id == a.id).contentShape(Rectangle())
                        .onTapGesture { m.focus(app: a) }
                    }
                }
                Inspector {
                    if let a = m.focusedApp {
                        HStack(spacing: 12) { appIcon(a.url.path).resizable().frame(width: 52, height: 52)
                            VStack(alignment: .leading) { Text(a.name).font(.system(size: 16, weight: .bold)); Text(DiskSize.format(a.size)).font(.system(size: 12)).foregroundColor(Theme.dim) } }
                        kv("Bundle ID", a.bundleID ?? "—", mono: true)
                        Text("Related files").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim)
                        if m.leftovers.isEmpty { Text("None found.").font(.system(size: 12)).foregroundColor(Theme.dim) }
                        ForEach(m.leftovers) { l in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(short(l.url.path)).font(Theme.path(10)); Text(DiskSize.format(l.size)).font(.system(size: 11)).foregroundColor(Theme.dim)
                            }
                        }
                    } else { Text("Select an app.").font(.system(size: 13)).foregroundColor(Theme.dim) }
                }
            }
            ActionBar(summary: "The app and its related files go to Quarantine.") {
                Button("Refresh") { m.loadApps() }.buttonStyle(GhostButton())
                Button("Uninstall…") { confirm = true }.buttonStyle(PrimaryButton()).disabled(m.focusedApp == nil)
            }
        }
        .onAppear { if m.apps.isEmpty { m.loadApps() } }
        .confirmationDialog("Move \(m.focusedApp?.name ?? "") and \(m.leftovers.count) related files to Quarantine?", isPresented: $confirm) {
            Button("Move to Quarantine") { m.uninstallFocusedApp() }
        }
    }
}

// MARK: Startup
struct StartupView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if m.agents.isEmpty {
                Hero(symbol: "power", title: "Nothing launches by itself", subtitle: "No startup agents in ~/Library/LaunchAgents.").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listScroll {
                    ForEach(m.agents) { a in
                        HStack(spacing: 12) {
                            IconBubble(symbol: "power", size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(short(a.program)).font(Theme.path(10)).foregroundColor(Theme.dim).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button("Disable") { m.disable(a) }.buttonStyle(GhostButton())
                        }.padding(12).card()
                    }
                }
            }
            ActionBar(summary: "\(m.agents.count) agents. Disabling moves the file to Quarantine; it takes effect at next login.") { EmptyView() }
        }.onAppear { m.loadAgents() }
    }
}

// MARK: Quarantine
struct QuarantineView: View {
    @EnvironmentObject var m: AppModel
    @State private var confirmPurge = false
    var body: some View {
        VStack(spacing: 0) {
            if m.quarantined.isEmpty {
                Hero(symbol: "tray.full.fill", title: "Quarantine is empty", subtitle: "Anything you move shows up here and can go back to its original place for 30 days.").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listScroll {
                    ForEach(m.quarantined) { e in
                        let left = max(0, Quarantine.retentionDays - (Calendar.current.dateComponents([.day], from: e.date, to: Date()).day ?? 0))
                        HStack(spacing: 12) {
                            IconBubble(symbol: "clock.arrow.circlepath", size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: e.originalPath).lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text("\(short(e.originalPath))").font(Theme.path(10)).foregroundColor(Theme.dim).lineLimit(1).truncationMode(.middle)
                                Text("\(e.source) · expires in \(left) days").font(.system(size: 11)).foregroundColor(Theme.dim)
                            }
                            Spacer(); SizeBadge(bytes: e.size)
                            Button("Restore") { m.restore(e) }.buttonStyle(PrimaryButton())
                            Button { m.purge(e) } label: { Image(systemName: "trash") }.buttonStyle(GhostButton()).help("Delete permanently")
                        }.padding(12).card()
                    }
                }
            }
            ActionBar(summary: "Total: \(DiskSize.format(m.quarantined.reduce(0) { $0 + $1.size })). Items older than 30 days are deleted automatically.") {
                Button { confirmPurge = true } label: { Label("Empty Quarantine", systemImage: "trash.fill") }
                    .buttonStyle(PrimaryButton()).disabled(m.quarantined.isEmpty)
            }
        }
        .onAppear { m.refreshQuarantine() }
        .confirmationDialog("Permanently delete \(m.quarantined.count) items (\(DiskSize.format(m.quarantined.reduce(0) { $0 + $1.size })))? This cannot be undone.", isPresented: $confirmPurge) {
            Button("Delete permanently", role: .destructive) { m.purgeAll() }
        }
    }
}

// MARK: Activity
struct ReportView: View {
    @EnvironmentObject var m: AppModel
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"; return f }()
    var body: some View {
        VStack(spacing: 0) {
            if m.log.isEmpty {
                Hero(symbol: "clock.arrow.circlepath", title: "No activity yet", subtitle: "Every action the app takes is logged here, on your Mac only.").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listScroll {
                    ForEach(m.log) { l in
                        HStack(alignment: .top, spacing: 12) {
                            Text(Self.fmt.string(from: l.date)).font(.system(size: 11)).monospacedDigit().foregroundColor(Theme.dim).frame(width: 80, alignment: .leading)
                            Text(l.action).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 120, alignment: .leading)
                            Text(short(l.detail)).font(Theme.path(10)).lineLimit(2)
                            Spacer()
                        }.padding(.horizontal, 12).padding(.vertical, 9).card()
                    }
                }
            }
            ActionBar(summary: "Log stored in ~/Library/Application Support/CleanSheet. Nothing is sent anywhere.") { EmptyView() }
        }.onAppear { m.refreshQuarantine() }
    }
}
