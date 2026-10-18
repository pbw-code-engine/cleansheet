import SwiftUI
import CodeEngineCore

struct ScanView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if m.items.isEmpty {
                    VStack(spacing: 14) {
                        Text("Nenhuma varredura ainda").font(Theme.mono(14, .bold))
                        Text("A varredura só lista. Nada é movido até você confirmar.").font(Theme.mono(11)).foregroundColor(Theme.dim)
                        Button("Varrer") { m.scan() }.buttonStyle(AmberButton()).disabled(m.busy)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(m.items, selection: Binding(get: { m.focused?.id }, set: { id in m.focused = m.items.first { $0.id == id } })) { item in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { m.selected.contains(item.id) },
                                set: { on in if on { m.selected.insert(item.id) } else { m.selected.remove(item.id) } }
                            )).labelsHidden().disabled(item.skipReason != nil)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.url.lastPathComponent).font(Theme.mono(12)).lineLimit(1)
                                Text(item.category + (item.skipReason.map { " · \($0)" } ?? "")).font(Theme.mono(10)).foregroundColor(item.skipReason == nil ? Theme.dim : Theme.danger)
                            }
                            Spacer()
                            Text(DiskSize.format(item.size)).font(Theme.mono(12))
                        }.tag(item.id).listRowBackground(Theme.background)
                    }.scrollContentBackground(.hidden)
                }
                Inspector {
                    if let f = m.focused {
                        kv("Caminho", f.url.path)
                        kv("Tamanho", DiskSize.format(f.size))
                        kv("Categoria", f.category)
                        kv("Confiança", f.confidence.rawValue)
                        kv("Por que é seguro", f.reason)
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }.buttonStyle(AmberButton(prominent: false))
                    } else {
                        Text("Selecione um item para ver o motivo.").font(Theme.mono(11)).foregroundColor(Theme.dim)
                    }
                }
            }
            ActionBar(summary: "Selecionado: \(DiskSize.format(m.selectedBytes)) em \(m.selected.count) itens") {
                Button("Varrer de novo") { m.scan() }.buttonStyle(AmberButton(prominent: false)).disabled(m.busy)
                Button("Simular") { m.confirmingMove = true }.buttonStyle(AmberButton()).disabled(m.selected.isEmpty)
            }
        }
        .sheet(isPresented: $m.confirmingMove) { SimulationSheet() }
    }
}

struct SimulationSheet: View {
    @EnvironmentObject var m: AppModel
    var chosen: [CleanItem] { m.items.filter { m.selected.contains($0.id) && $0.skipReason == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Simulação").font(Theme.mono(15, .bold)).foregroundColor(Theme.amber)
            Text("Estes \(chosen.count) itens (\(DiskSize.format(chosen.reduce(0) { $0 + $1.size }))) serão movidos para a Quarentena, não apagados. Você poderá restaurar por 30 dias.")
                .font(Theme.mono(11)).foregroundColor(Theme.dim)
            List(chosen) { i in
                HStack { Text(i.url.path).font(Theme.mono(10)).lineLimit(1).truncationMode(.middle); Spacer(); Text(DiskSize.format(i.size)).font(Theme.mono(10)) }
                    .listRowBackground(Theme.background)
            }.scrollContentBackground(.hidden).frame(height: 260)
            HStack {
                Spacer()
                Button("Cancelar") { m.confirmingMove = false }.buttonStyle(AmberButton(prominent: false))
                Button("Mover para Quarentena") { m.confirmingMove = false; m.moveSelectedToQuarantine() }.buttonStyle(AmberButton())
            }
        }.padding(18).frame(width: 640).background(Theme.background).foregroundColor(Theme.text)
    }
}
