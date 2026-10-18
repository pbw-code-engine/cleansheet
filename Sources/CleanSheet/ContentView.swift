import SwiftUI
import CleanSheetCore

extension Tab {
    var symbol: String {
        switch self {
        case .scan: return "sparkles"
        case .map: return "chart.pie.fill"
        case .duplicates: return "square.on.square"
        case .apps: return "square.grid.2x2.fill"
        case .startup: return "power"
        case .quarantine: return "tray.full.fill"
        case .report: return "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch m.tab {
                case .scan: ScanView()
                case .map: MapView()
                case .duplicates: DuplicatesView()
                case .apps: AppsView()
                case .startup: StartupView()
                case .quarantine: QuarantineView()
                case .report: ReportView()
                }
            }
            statusBar
        }
        .background(Theme.background)
        .foregroundColor(Theme.text)
        .sheet(isPresented: $m.showPalette) { PaletteView() }
        .background(Button("") { m.showPalette = true }.keyboardShortcut("k", modifiers: .command).opacity(0))
    }

    var topBar: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 74)
            HStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                Text("CleanSheet").font(.system(size: 13, weight: .bold, design: .rounded))
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(Tab.allCases) { t in
                    Button { withAnimation(.easeInOut(duration: 0.15)) { m.tab = t } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.symbol).font(.system(size: 12, weight: .semibold))
                            if m.tab == t { Text(t.rawValue).font(.system(size: 12, weight: .semibold)) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundColor(m.tab == t ? .black.opacity(0.85) : Theme.dim)
                        .background(Capsule().fill(m.tab == t ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                    }.buttonStyle(.plain).help(t.rawValue)
                }
            }
            .padding(3).background(Capsule().fill(Color.white.opacity(0.06))).overlay(Capsule().stroke(Theme.cardStroke))
            Spacer()
            Button { m.showPalette = true } label: {
                HStack(spacing: 6) { Image(systemName: "magnifyingglass"); Text("⌘K") }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.dim)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    var statusBar: some View {
        HStack(spacing: 8) {
            if m.busy { ProgressView().controlSize(.small) } else { Circle().fill(Theme.ok).frame(width: 7, height: 7) }
            Text(m.status).font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(1)
            Spacer()
        }.padding(.horizontal, 18).padding(.vertical, 8).background(Color.black.opacity(0.18))
    }
}

struct PaletteView: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    var matches: [AppModel.Command] {
        query.isEmpty ? m.commands() : m.commands().filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "magnifyingglass").foregroundColor(Theme.dim)
                TextField("What do you want to do?", text: $query).textFieldStyle(.plain).font(.system(size: 16))
                    .onSubmit { if let c = matches.first { m.showPalette = false; c.run() } }
            }.padding(12).card()
            ForEach(matches) { c in
                Button { m.showPalette = false; c.run() } label: {
                    Text(c.title).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 7)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(18).frame(width: 460).background(Theme.background).foregroundColor(Theme.text)
    }
}

/// Floating action bar used by the tabs that move files.
struct ActionBar<Buttons: View>: View {
    let summary: String
    @ViewBuilder var buttons: Buttons
    var body: some View {
        HStack(spacing: 10) {
            Text(summary).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.dim).lineLimit(2)
            Spacer()
            buttons
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke))
        .padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 4)
    }
}

struct Inspector<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) { content }.padding(16).frame(maxWidth: .infinity, alignment: .leading) }
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardStroke))
            .padding(.trailing, 16).padding(.vertical, 6)
    }
}

func kv(_ k: String, _ v: String, mono: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(k).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim)
        Text(v).font(mono ? Theme.path(11) : .system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
}
