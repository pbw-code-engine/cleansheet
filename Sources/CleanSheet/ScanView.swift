import SwiftUI
import CleanSheetCore

struct ScanView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if m.items.isEmpty {
                    VStack(spacing: 22) {
                        Hero(symbol: "sparkles", title: "Find what's left behind", subtitle: "Scanning only lists things. Nothing moves until you review and confirm, and everything goes to Quarantine, not the Trash.")
                        Button("Start scan") { m.scan() }.buttonStyle(PrimaryButton()).disabled(m.busy)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(m.items) { item in row(item) }
                        }.padding(.leading, 16).padding(.vertical, 6)
                    }
                }
                Inspector {
                    if let f = m.focused {
                        HStack(spacing: 10) { IconBubble(symbol: categorySymbol(f.category)); VStack(alignment: .leading) {
                            Text(f.url.lastPathComponent).font(.system(size: 15, weight: .bold)).lineLimit(2)
                            Text(f.category).font(.system(size: 12)).foregroundColor(Theme.dim) } }
                        kv("Size", DiskSize.format(f.size))
                        kv("Why it is safe", f.reason)
                        kv("Confidence", f.confidence.rawValue)
                        kv("Path", f.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), mono: true)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(GhostButton())
                    } else {
                        Text("Select an item to see why it is safe.").font(.system(size: 13)).foregroundColor(Theme.dim)
                    }
                }
            }
            ActionBar(summary: m.items.isEmpty ? "Nothing selected" : "\(m.selected.count) items · \(DiskSize.format(m.selectedBytes)) ready for Quarantine") {
                Button("Scan again") { m.scan() }.buttonStyle(GhostButton()).disabled(m.busy)
                Button("Review and move") { m.confirmingMove = true }.buttonStyle(PrimaryButton()).disabled(m.selected.isEmpty)
            }
        }
        .sheet(isPresented: $m.confirmingMove) { SimulationSheet() }
    }

    func row(_ item: CleanItem) -> some View {
        let on = m.selected.contains(item.id)
        return HStack(spacing: 12) {
            Button {
                if on { m.selected.remove(item.id) } else { m.selected.insert(item.id) }
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                    .foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.dim))
            }.buttonStyle(.plain).disabled(item.skipReason != nil)
            IconBubble(symbol: categorySymbol(item.category), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.skipReason ?? item.category).font(.system(size: 11)).foregroundColor(item.skipReason == nil ? Theme.dim : Theme.danger)
            }
            Spacer()
            SizeBadge(bytes: item.size)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .card(highlighted: m.focused?.id == item.id)
        .contentShape(Rectangle())
        .onTapGesture { m.focused = item }
    }
}

struct SimulationSheet: View {
    @EnvironmentObject var m: AppModel
    var chosen: [CleanItem] { m.items.filter { m.selected.contains($0.id) && $0.skipReason == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) { IconBubble(symbol: "tray.and.arrow.down.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review before moving").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("\(chosen.count) items · \(DiskSize.format(chosen.reduce(0) { $0 + $1.size })). They go to Quarantine and can be restored for 30 days.")
                        .font(.system(size: 12)).foregroundColor(Theme.dim)
                } }
            ScrollView { LazyVStack(spacing: 6) { ForEach(chosen) { i in
                HStack { Text(i.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(Theme.path(10)).lineLimit(1).truncationMode(.middle); Spacer(); SizeBadge(bytes: i.size) }
                    .padding(.horizontal, 10).padding(.vertical, 6).card()
            } } }.frame(height: 260)
            HStack { Spacer()
                Button("Cancel") { m.confirmingMove = false }.buttonStyle(GhostButton())
                Button("Move to Quarantine") { m.confirmingMove = false; m.moveSelectedToQuarantine() }.buttonStyle(PrimaryButton())
            }
        }.padding(22).frame(width: 640).background(Theme.background).foregroundColor(Theme.text)
    }
}
