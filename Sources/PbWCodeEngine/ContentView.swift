import SwiftUI
import CodeEngineCore

struct ContentView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Theme.line)
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
            Divider().overlay(Theme.line)
            statusBar
        }
        .background(Theme.background)
        .foregroundColor(Theme.text)
        .sheet(isPresented: $m.showPalette) { PaletteView() }
        .background(
            Button("") { m.showPalette = true }.keyboardShortcut("k", modifiers: .command).opacity(0)
        )
    }

    var topBar: some View {
        HStack(spacing: 4) {
            Text("PbW").font(Theme.mono(13, .bold)).foregroundColor(Theme.amber)
            Text("Code Engine").font(Theme.mono(13)).padding(.trailing, 12)
            ForEach(Tab.allCases) { t in
                Button { m.tab = t } label: {
                    Text(t.rawValue).font(Theme.mono(12, m.tab == t ? .bold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundColor(m.tab == t ? .black : Theme.dim)
                        .background(m.tab == t ? Theme.amber : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain)
            }
            Spacer()
            Button { m.showPalette = true } label: {
                Text("⌘K  ação").font(Theme.mono(11)).foregroundColor(Theme.dim)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 10)
        .background(Theme.panel)
    }

    var statusBar: some View {
        HStack {
            if m.busy { ProgressView().controlSize(.small) }
            Text(m.status).font(Theme.mono(11)).foregroundColor(Theme.dim).lineLimit(1)
            Spacer()
        }.padding(.horizontal, 14).padding(.vertical, 6).background(Theme.panel)
    }
}

struct PaletteView: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    var matches: [AppModel.Command] {
        query.isEmpty ? m.commands() : m.commands().filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("O que você quer fazer?", text: $query)
                .textFieldStyle(.plain).font(Theme.mono(14)).padding(10)
                .background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit { if let c = matches.first { m.showPalette = false; c.run() } }
            ForEach(matches) { c in
                Button { m.showPalette = false; c.run() } label: {
                    Text(c.title).font(Theme.mono(12)).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }.buttonStyle(.plain)
            }
        }.padding(16).frame(width: 440).background(Theme.background).foregroundColor(Theme.text)
    }
}

/// Barra de ações fixa, usada por todas as abas que movem arquivos.
struct ActionBar<Buttons: View>: View {
    let summary: String
    @ViewBuilder var buttons: Buttons
    var body: some View {
        HStack {
            Text(summary).font(Theme.mono(12))
            Spacer()
            buttons
        }.padding(12).background(Theme.panel)
    }
}

struct Inspector<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 10) { content }.padding(14).frame(maxWidth: .infinity, alignment: .leading) }
            .frame(width: 300).background(Theme.panel)
    }
}

func kv(_ k: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(k.uppercased()).font(Theme.mono(9, .bold)).foregroundColor(Theme.dim)
        Text(v).font(Theme.mono(11)).textSelection(.enabled)
    }
}
