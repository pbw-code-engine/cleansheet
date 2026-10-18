import Foundation
import CodeEngineCore

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print(ok ? "PASS  \(name)" : "FAIL  \(name)")
    if !ok { failures += 1 }
}

let fm = FileManager.default
let guardian = SafetyGuard()
let home = guardian.home

func denied(_ u: URL, _ s: SafetyGuard.Scope = .automatic) -> Bool {
    if case .denied = guardian.check(u, scope: s) { return true }
    return false
}

// Proteção
check("nega /System", denied(URL(fileURLWithPath: "/System/Library")))
check("nega /", denied(URL(fileURLWithPath: "/")))
check("nega home", denied(home))
check("nega ~/Library", denied(home.appendingPathComponent("Library")))
check("nega ~/Downloads (pasta de topo)", denied(home.appendingPathComponent("Downloads")))
check("nega ~/.ssh/id_rsa", denied(home.appendingPathComponent(".ssh/id_rsa"), .userSelected))
check("nega ~/Library/Keychains", denied(home.appendingPathComponent("Library/Keychains/x"), .userSelected))
check("nega ancestral de Keychains", denied(home.appendingPathComponent("Library")))
check("nega ~/Documents/x no modo automático", denied(home.appendingPathComponent("Documents/x.txt")))
check("permite ~/Documents/x se o usuário escolheu", !denied(home.appendingPathComponent("Documents/x.txt"), .userSelected))
check("nega .photoslibrary mesmo escolhido", denied(home.appendingPathComponent("Pictures/a.photoslibrary/b"), .userSelected))
check("permite ~/Library/Caches/foo", !denied(home.appendingPathComponent("Library/Caches/foo")))

// Quarentena
let work = home.appendingPathComponent("Library/Caches/pbw-selfcheck-\(UUID().uuidString.prefix(8))")
let qroot = fm.temporaryDirectory.appendingPathComponent("pbw-q-\(UUID().uuidString.prefix(8))")
defer { try? fm.removeItem(at: work); try? fm.removeItem(at: qroot) }
try fm.createDirectory(at: work, withIntermediateDirectories: true)
let q = Quarantine(root: qroot, guardian: guardian)

let a = work.appendingPathComponent("a.bin")
try Data(repeating: 7, count: 2_000_000).write(to: a)
let entry = try q.add(a, size: 2_000_000, scope: .automatic, source: "selfcheck")
check("quarentena move o arquivo", !fm.fileExists(atPath: a.path) && q.entries().count == 1)
try q.restore(entry)
check("restaura ao local original", fm.fileExists(atPath: a.path) && q.entries().isEmpty)

do {
    _ = try q.add(home.appendingPathComponent(".ssh"), size: 0, scope: .userSelected, source: "selfcheck")
    check("recusa mover ~/.ssh", false)
} catch { check("recusa mover ~/.ssh", true) }

let e2 = try q.add(a, size: 2_000_000, scope: .automatic, source: "selfcheck")
try Data("novo".utf8).write(to: a)
do { try q.restore(e2); check("restauração não sobrescreve", false) } catch { check("restauração não sobrescreve", true) }
try q.purge(e2)
check("exclusão definitiva remove da quarentena", q.entries().isEmpty)

let old = try { () -> QuarantineEntry in
    let f = work.appendingPathComponent("old.bin"); try Data(count: 10).write(to: f)
    return try q.add(f, size: 10, scope: .automatic, source: "selfcheck")
}()
q.purgeExpired(now: old.date.addingTimeInterval(31 * 86_400))
check("expira após 30 dias", q.entries().isEmpty)

// Symlink apontando para pasta protegida não pode ser movido
let link = work.appendingPathComponent("link-ssh")
try fm.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent(".ssh"))
check("symlink para ~/.ssh é bloqueado", denied(link, .userSelected))

// Duplicatas
let d1 = work.appendingPathComponent("d1.dat"), d2 = work.appendingPathComponent("d2.dat"), d3 = work.appendingPathComponent("d3.dat")
let blob = Data((0..<1_500_000).map { UInt8($0 % 251) })
try blob.write(to: d1); try blob.write(to: d2)
var other = blob; other[other.count - 1] ^= 0xFF; try other.write(to: d3)
let groups = Duplicates.find(in: work)
check("acha 1 grupo de duplicatas idênticas", groups.count == 1 && groups[0].files.count == 2)
check("não agrupa arquivo com 1 byte diferente", !(groups.first?.files.contains(d3) ?? false))

// Scanner: item em uso é marcado e não removido
let appCache = home.appendingPathComponent("Library/Caches/com.pbw.selfcheck.running")
try fm.createDirectory(at: appCache, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: appCache) }
try Data(repeating: 1, count: 100_000).write(to: appCache.appendingPathComponent("c"))
let found = Scanner(guardian: guardian, runningBundleIDs: ["com.pbw.selfcheck.running"]).scan()
check("cache de app aberto é sinalizado", found.first { $0.url.path == appCache.path }?.skipReason != nil)

print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
exit(failures == 0 ? 0 : 1)
