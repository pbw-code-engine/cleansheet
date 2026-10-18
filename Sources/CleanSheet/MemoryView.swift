import SwiftUI
import CleanSheetCore

struct MemoryView: View {
    @EnvironmentObject var mem: MemoryModel
    @State private var confirm = false

    private var pressureColor: Color {
        switch mem.snapshot.pressure { case .normal: return Theme.ok; case .warning: return Theme.accentA; case .critical: return Theme.danger }
    }
    private func risk(_ l: CloseLevel) -> Color {
        switch l { case .low: return Theme.ok; case .medium: return Theme.accentA; case .high: return Theme.accentB; case .sweep: return Theme.danger }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(spacing: 12) {
                        gauge
                        ForEach(CloseLevel.allCases) { l in levelCard(l) }
                        targetsList
                    }.padding(.leading, 16).padding(.vertical, 6)
                }
                Inspector { autoPanel }
            }
            ActionBar(summary: mem.lastResult.isEmpty
                      ? "\(Self.apps(mem.targets.count)) would close at \(mem.level.rawValue) · ~\(DiskSize.format(Int64(mem.targetBytes))) of memory"
                      : mem.lastResult) {
                Button("Free memory now") { confirm = true }.buttonStyle(PrimaryButton()).disabled(mem.targets.isEmpty || mem.closing)
            }
        }
        .confirmationDialog("Ask \(Self.apps(mem.targets.count)) to quit (\(mem.level.rawValue))? Apps with unsaved work will ask you to save first.", isPresented: $confirm) {
            Button("Quit \(Self.apps(mem.targets.count))", role: mem.level == .sweep ? .destructive : nil) { mem.freeNow() }
        }
    }

    static func apps(_ n: Int) -> String { n == 1 ? "1 app" : "\(n) apps" }

    var gauge: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 14)
                Circle().trim(from: 0, to: mem.snapshot.fraction).stroke(pressureColor, style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(mem.snapshot.fraction * 100))%").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("used").font(.system(size: 11)).foregroundColor(Theme.dim)
                }
            }.frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(DiskSize.format(Int64(mem.snapshot.used))) of \(DiskSize.format(Int64(mem.snapshot.total)))").font(.system(size: 18, weight: .bold, design: .rounded))
                HStack(spacing: 6) { Circle().fill(pressureColor).frame(width: 8, height: 8); Text("Memory pressure: \(mem.snapshot.pressure.label)").font(.system(size: 13)) }
                Text("Updates every 5 seconds.").font(.system(size: 11)).foregroundColor(Theme.dim)
            }
            Spacer()
        }.padding(18).card()
    }

    func levelCard(_ l: CloseLevel) -> some View {
        let on = mem.level == l
        return HStack(spacing: 12) {
            Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.dim)).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(l.rawValue).font(.system(size: 14, weight: .bold))
                    Circle().fill(risk(l)).frame(width: 7, height: 7)
                }
                Text(l.summary).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(Self.apps(l.select(mem.apps, neverClose: mem.neverClose).count)).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
        }
        .padding(12).card(highlighted: on).contentShape(Rectangle()).onTapGesture { mem.level = l }
    }

    var targetsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Would be closed at \(mem.level.rawValue)").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
            if mem.targets.isEmpty { Text("Nothing to close at this level.").font(.system(size: 12)).foregroundColor(Theme.dim) }
            ForEach(mem.targets) { a in
                HStack(spacing: 10) {
                    if let app = NSRunningApplication(processIdentifier: a.pid), let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                    Text(a.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button("Never close") { mem.neverCloseToggle(a.bundleID) }.buttonStyle(GhostButton())
                    SizeBadge(bytes: Int64(a.memoryBytes))
                }.padding(.horizontal, 10).padding(.vertical, 6).card()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder var autoPanel: some View {
        Text("Automatic").font(.system(size: 15, weight: .bold))
        Toggle("Close apps automatically when memory is high", isOn: $mem.autoEnabled).toggleStyle(.switch).tint(Theme.accentA)
        VStack(alignment: .leading, spacing: 4) {
            Text("Trigger at \(Int(mem.threshold))% used, or when macOS reports Critical pressure.").font(.system(size: 12)).foregroundColor(Theme.dim)
            Slider(value: $mem.threshold, in: 70...97, step: 1).tint(Theme.accentA)
        }
        kv("Level used", mem.level.rawValue)
        Text("Auto-close waits at least 2 minutes between runs and always asks apps to quit politely, so apps with unsaved work will prompt you instead of losing it. It never force-quits.")
            .font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
        if mem.autoEnabled && (mem.level == .high || mem.level == .sweep) {
            Label("\(mem.level.rawValue) is aggressive for automatic mode.", systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundColor(Theme.danger)
        }
        Divider().overlay(Theme.cardStroke)
        Text("Never closed").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
        Text("Finder, Dock, Terminal apps, Spotify, Music and CleanSheet are always protected.").font(.system(size: 11)).foregroundColor(Theme.dim)
        ForEach(Array(mem.neverClose).sorted(), id: \.self) { id in
            HStack { Text(id).font(Theme.path(10)).lineLimit(1); Spacer(); Button { mem.neverCloseToggle(id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundColor(Theme.dim) }
        }
    }
}
