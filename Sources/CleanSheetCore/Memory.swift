import Foundation
import Darwin

public enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    public var label: String {
        switch self { case .normal: return "Normal"; case .warning: return "Warning"; case .critical: return "Critical" }
    }
}

public struct MemorySnapshot {
    public let total: UInt64
    public let used: UInt64
    public let pressure: MemoryPressure
    public var fraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
}

public enum MemoryMonitor {
    /// "Memory used" the way Activity Monitor counts it: app memory + wired + compressed.
    public static func read() -> MemorySnapshot {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        var used = total / 2
        if kr == KERN_SUCCESS {
            let pages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
            used = UInt64(max(0, pages)) * UInt64(pageSize)
        }
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return MemorySnapshot(total: total, used: min(used, total), pressure: MemoryPressure(rawValue: Int(level)) ?? .normal)
    }
}

public struct ProcessRow: Equatable {
    public let pid: Int32, ppid: Int32, rssBytes: UInt64
}

public enum ProcessTable {
    /// Parses the output of `ps -axo pid=,ppid=,rss=` (rss in KB).
    public static func parse(_ text: String) -> [ProcessRow] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count == 3, let p = Int32(f[0]), let pp = Int32(f[1]), let kb = UInt64(f[2]) else { return nil }
            return ProcessRow(pid: p, ppid: pp, rssBytes: kb * 1024)
        }
    }

    public static func current() -> [ProcessRow] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,rss="]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Memory of each root pid plus all of its descendants (helpers, renderers…).
    public static func totals(for roots: [Int32], in rows: [ProcessRow]) -> [Int32: UInt64] {
        var children: [Int32: [ProcessRow]] = [:]
        var own: [Int32: UInt64] = [:]
        for r in rows { children[r.ppid, default: []].append(r); own[r.pid] = r.rssBytes }
        var out: [Int32: UInt64] = [:]
        for root in roots {
            var total = own[root] ?? 0
            var stack = children[root] ?? []
            var seen: Set<Int32> = [root]
            while let r = stack.popLast() {
                guard seen.insert(r.pid).inserted else { continue }
                total += r.rssBytes
                stack.append(contentsOf: children[r.pid] ?? [])
            }
            out[root] = total
        }
        return out
    }
}
