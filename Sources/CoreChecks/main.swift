import Foundation
import CleanSheetCore

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
check("denies /System", denied(URL(fileURLWithPath: "/System/Library")))
check("denies /", denied(URL(fileURLWithPath: "/")))
check("denies home", denied(home))
check("denies ~/Library", denied(home.appendingPathComponent("Library")))
check("denies ~/Downloads (top-level folder)", denied(home.appendingPathComponent("Downloads")))
check("denies ~/.ssh/id_rsa", denied(home.appendingPathComponent(".ssh/id_rsa"), .userSelected))
check("denies ~/Library/Keychains", denied(home.appendingPathComponent("Library/Keychains/x"), .userSelected))
check("denies ancestor of Keychains", denied(home.appendingPathComponent("Library")))
check("denies ~/Documents/x in automatic mode", denied(home.appendingPathComponent("Documents/x.txt")))
check("allows ~/Documents/x if the user chose it", !denied(home.appendingPathComponent("Documents/x.txt"), .userSelected))
check("denies .photoslibrary even if chosen", denied(home.appendingPathComponent("Pictures/a.photoslibrary/b"), .userSelected))
check("allows ~/Library/Caches/foo", !denied(home.appendingPathComponent("Library/Caches/foo")))

// Quarentena
let work = home.appendingPathComponent("Library/Caches/pbw-selfcheck-\(UUID().uuidString.prefix(8))")
let qroot = fm.temporaryDirectory.appendingPathComponent("pbw-q-\(UUID().uuidString.prefix(8))")
defer { try? fm.removeItem(at: work); try? fm.removeItem(at: qroot) }
try fm.createDirectory(at: work, withIntermediateDirectories: true)
let q = Quarantine(root: qroot, guardian: guardian)

let a = work.appendingPathComponent("a.bin")
try Data(repeating: 7, count: 2_000_000).write(to: a)
let entry = try q.add(a, size: 2_000_000, scope: .automatic, source: "selfcheck")
check("quarantine moves the file", !fm.fileExists(atPath: a.path) && q.entries().count == 1)
try q.restore(entry)
check("restores to the original place", fm.fileExists(atPath: a.path) && q.entries().isEmpty)

do {
    _ = try q.add(home.appendingPathComponent(".ssh"), size: 0, scope: .userSelected, source: "selfcheck")
    check("refuses to move ~/.ssh", false)
} catch { check("refuses to move ~/.ssh", true) }

let e2 = try q.add(a, size: 2_000_000, scope: .automatic, source: "selfcheck")
try Data("novo".utf8).write(to: a)
do { try q.restore(e2); check("restore does not overwrite", false) } catch { check("restore does not overwrite", true) }
try q.purge(e2)
check("permanent delete removes from quarantine", q.entries().isEmpty)

let old = try { () -> QuarantineEntry in
    let f = work.appendingPathComponent("old.bin"); try Data(count: 10).write(to: f)
    return try q.add(f, size: 10, scope: .automatic, source: "selfcheck")
}()
q.purgeExpired(now: old.date.addingTimeInterval(31 * 86_400))
check("expires after 30 days", q.entries().isEmpty)

// Symlink apontando para pasta protegida não pode ser movido
let link = work.appendingPathComponent("link-ssh")
try fm.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent(".ssh"))
check("symlink to ~/.ssh is blocked", denied(link, .userSelected))

// Duplicatas
let d1 = work.appendingPathComponent("d1.dat"), d2 = work.appendingPathComponent("d2.dat"), d3 = work.appendingPathComponent("d3.dat")
let blob = Data((0..<1_500_000).map { UInt8($0 % 251) })
try blob.write(to: d1); try blob.write(to: d2)
var other = blob; other[other.count - 1] ^= 0xFF; try other.write(to: d3)
let groups = Duplicates.find(in: work)
check("finds 1 group of identical duplicates", groups.count == 1 && groups[0].files.count == 2)
check("does not group a file that differs by 1 byte", !(groups.first?.files.contains(d3) ?? false))

// Scanner: item em uso é marcado e não removido
let appCache = home.appendingPathComponent("Library/Caches/com.pbw.selfcheck.running")
try fm.createDirectory(at: appCache, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: appCache) }
try Data(repeating: 1, count: 100_000).write(to: appCache.appendingPathComponent("c"))
let found = Scanner(guardian: guardian, runningBundleIDs: ["com.pbw.selfcheck.running"]).scan()
check("cache of an open app is flagged", found.first { $0.url.path == appCache.path }?.skipReason != nil)

print(failures == 0 ? "\nAll good." : "\n\(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
