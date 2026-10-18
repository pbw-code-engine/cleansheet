import Foundation

/// Local record of what the app did. Never leaves the Mac.
public final class ActivityLog {
    public static let shared = ActivityLog()

    public struct Line: Identifiable, Hashable {
        public let id = UUID()
        public let date: Date
        public let action: String
        public let detail: String
    }

    private let fileURL: URL
    private let lock = NSLock()

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CleanSheet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("activity.log")
    }

    public func record(_ action: String, _ detail: String) {
        lock.lock(); defer { lock.unlock() }
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(action)\t\(detail)\n"
        if let h = try? FileHandle(forWritingTo: fileURL) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    public func lines() -> [Line] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let f = ISO8601DateFormatter()
        return text.split(separator: "\n").compactMap { row in
            let p = row.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard p.count == 3, let d = f.date(from: String(p[0])) else { return nil }
            return Line(date: d, action: String(p[1]), detail: String(p[2]))
        }.reversed()
    }
}
