import SwiftUI
import CodeEngineCore

// MARK: Mapa
struct MapView: View {
    @EnvironmentObject var m: AppModel
    var maxSize: Int64 { max(m.mapNodes.first?.size ?? 1, 1) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← Voltar") { m.mapBack() }.buttonStyle(AmberButton(prominent: false)).disabled(m.mapPath.count < 2)
                Text(m.mapPath.last?.path ?? "Escolha uma pasta para medir").font(Theme.mono(11)).foregroundColor(Theme.dim).lineLimit(1).truncationMode(.head)
                Spacer()
                Button("Escolher pasta…") { m.mapPickRoot() }.buttonStyle(AmberButton())
            }.padding(12)
            List(m.mapNodes) { n in
                Button { if n.isDirectory { m.openMap(n.url) } } label: {
                    HStack {
                        Text(n.isDirectory ? "▸" : " ").font(Theme.mono(12)).foregroundColor(Theme.amber)
                        Text(n.url.lastPathComponent).font(Theme.mono(12)).frame(width: 220, alignment: .leading).lineLimit(1)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3).fill(Theme.amber.opacity(0.75))
                                .frame(width: max(2, g.size.width * CGFloat(n.size) / CGFloat(maxSize)), height: 10)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        Text(DiskSize.format(n.size)).font(Theme.mono(12)).frame(width: 80, alignment: .trailing)
                    }.frame(height: 24)
                }.buttonStyle(.plain).listRowBackground(Theme.background)
            }.scrollContentBackground(.hidden)
            ActionBar(summary: "Só leitura: o Mapa não apaga nada.") { EmptyView() }
        }
    }
}

// MARK: Duplicatas
struct DuplicatesView: View {
    @EnvironmentObject var m: AppModel
    var selectedBytes: Int64 { m.groups.reduce(0) { $0 + $1.size * Int64($1.files.filter { m.dupSelected.contains($0) }.count) } }
    var body: some View {
        VStack(spacing: 0) {
            if m.groups.isEmpty {
                VStack(spacing: 14) {
                    Text(m.dupFolder == nil ? "Escolha uma pasta" : "Nenhuma duplicata em \(m.dupFolder!.lastPathComponent)").font(Theme.mono(14, .bold))
                    Text("Compara arquivos de 1 MB ou mais pelo conteúdo (SHA-256).").font(Theme.mono(11)).foregroundColor(Theme.dim)
                    Button("Escolher pasta…") { m.pickFolderAndFindDuplicates() }.buttonStyle(AmberButton()).disabled(m.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(m.groups) { g in
                        Section("\(DiskSize.format(g.size)) × \(g.files.count)") {
                            ForEach(g.files, id: \.self) { f in
                                Toggle(isOn: Binding(get: { m.dupSelected.contains(f) }, set: { on in if on { m.dupSelected.insert(f) } else { m.dupSelected.remove(f) } })) {
                                    Text(f.path).font(Theme.mono(10)).lineLimit(1).truncationMode(.middle)
                                }
                            }
                        }
                    }
                }.scrollContentBackground(.hidden)
            }
            ActionBar(summary: "Selecionado: \(DiskSize.format(selectedBytes)). Pelo menos uma cópia de cada grupo é sempre mantida.") {
                Button("Escolher pasta…") { m.pickFolderAndFindDuplicates() }.buttonStyle(AmberButton(prominent: false)).disabled(m.busy)
                Button("Mover para Quarentena") { m.moveSelectedDuplicates() }.buttonStyle(AmberButton()).disabled(m.dupSelected.isEmpty)
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
            HStack(spacing: 0) {
                List(m.apps, selection: Binding(get: { m.focusedApp?.id }, set: { id in if let a = m.apps.first(where: { $0.id == id }) { m.focus(app: a) } })) { a in
                    HStack { Text(a.name).font(Theme.mono(12)); Spacer(); Text(DiskSize.format(a.size)).font(Theme.mono(12)) }
                        .tag(a.id).listRowBackground(Theme.background)
                }.scrollContentBackground(.hidden)
                Inspector {
                    if let a = m.focusedApp {
                        kv("App", a.name); kv("Bundle ID", a.bundleID ?? "—"); kv("Tamanho", DiskSize.format(a.size))
                        Text("ARQUIVOS RELACIONADOS").font(Theme.mono(9, .bold)).foregroundColor(Theme.dim)
                        if m.leftovers.isEmpty { Text("Nenhum encontrado.").font(Theme.mono(11)).foregroundColor(Theme.dim) }
                        ForEach(m.leftovers) { l in
                            Text("\(l.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) · \(DiskSize.format(l.size))").font(Theme.mono(10))
                        }
                    } else { Text("Selecione um app.").font(Theme.mono(11)).foregroundColor(Theme.dim) }
                }
            }
            ActionBar(summary: "O app e seus arquivos vão para a Quarentena.") {
                Button("Atualizar lista") { m.loadApps() }.buttonStyle(AmberButton(prominent: false))
                Button("Desinstalar…") { confirm = true }.buttonStyle(AmberButton()).disabled(m.focusedApp == nil)
            }
        }
        .onAppear { if m.apps.isEmpty { m.loadApps() } }
        .confirmationDialog("Mover \(m.focusedApp?.name ?? "") e \(m.leftovers.count) arquivos relacionados para a Quarentena?", isPresented: $confirm) {
            Button("Mover para Quarentena") { m.uninstallFocusedApp() }
        }
    }
}

// MARK: Inicialização
struct StartupView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 0) {
            List(m.agents) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.label).font(Theme.mono(12))
                        Text(a.program).font(Theme.mono(10)).foregroundColor(Theme.dim).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Desativar") { m.disable(a) }.buttonStyle(AmberButton(prominent: false))
                }.listRowBackground(Theme.background)
            }.scrollContentBackground(.hidden)
            ActionBar(summary: "\(m.agents.count) agentes de ~/Library/LaunchAgents. Desativar move o arquivo para a Quarentena.") { EmptyView() }
        }.onAppear { m.loadAgents() }
    }
}

// MARK: Quarentena
struct QuarantineView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if m.quarantined.isEmpty {
                Text("A Quarentena está vazia.").font(Theme.mono(13)).foregroundColor(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(m.quarantined) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.originalPath).font(Theme.mono(11)).lineLimit(1).truncationMode(.middle)
                            let left = max(0, Quarantine.retentionDays - Calendar.current.dateComponents([.day], from: e.date, to: Date()).day!)
                            Text("\(e.source) · \(DiskSize.format(e.size)) · expira em \(left) dias").font(Theme.mono(10)).foregroundColor(Theme.dim)
                        }
                        Spacer()
                        Button("Restaurar") { m.restore(e) }.buttonStyle(AmberButton())
                        Button("Excluir") { m.purge(e) }.buttonStyle(AmberButton(prominent: false))
                    }.listRowBackground(Theme.background)
                }.scrollContentBackground(.hidden)
            }
            ActionBar(summary: "Total: \(DiskSize.format(m.quarantined.reduce(0) { $0 + $1.size })). Itens com mais de 30 dias são apagados sozinhos.") { EmptyView() }
        }.onAppear { m.refreshQuarantine() }
    }
}

// MARK: Relatório
struct ReportView: View {
    @EnvironmentObject var m: AppModel
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"; return f }()
    var body: some View {
        VStack(spacing: 0) {
            List(m.log) { l in
                HStack(alignment: .top) {
                    Text(Self.fmt.string(from: l.date)).font(Theme.mono(10)).foregroundColor(Theme.dim).frame(width: 90, alignment: .leading)
                    Text(l.action).font(Theme.mono(10, .bold)).foregroundColor(Theme.amber).frame(width: 130, alignment: .leading)
                    Text(l.detail).font(Theme.mono(10)).lineLimit(2)
                }.listRowBackground(Theme.background)
            }.scrollContentBackground(.hidden)
            ActionBar(summary: "Histórico local em ~/Library/Application Support/PbWCodeEngine. Nada é enviado.") { EmptyView() }
        }.onAppear { m.refreshQuarantine() }
    }
}
