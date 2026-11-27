import Foundation

/// Bounded, local-only runtime diagnostics. This store observes existing work; it never starts scans.
enum RuntimeDiagnosticsStore {
    private static let ioQueue = DispatchQueue(label: "cn.yfen.filterkit.runtime-diagnostics", qos: .utility)
    private static let directoryName = "FilterKit/Logs"
    private static let currentName = "FilterKit.log"
    private static let previousName = "FilterKit.previous.log"
    private static let maximumFileBytes = 1_048_576

    static var logDirectoryURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var currentLogURL: URL? { logDirectoryURL?.appendingPathComponent(currentName) }

    static func append(_ message: String) {
        ioQueue.async {
            guard let directory = logDirectoryURL else { return }
            do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let safeMessage = message.replacingOccurrences(of: "\n", with: " ")
            let data = Data("\(timestamp) \(safeMessage)\n".utf8)
            let current = directory.appendingPathComponent(currentName)
            let existingSize = ((try? FileManager.default.attributesOfItem(atPath: current.path)[.size]) as? NSNumber)?.intValue ?? 0
            if existingSize + data.count > maximumFileBytes {
                let previous = directory.appendingPathComponent(previousName)
                try? FileManager.default.removeItem(at: previous)
                if FileManager.default.fileExists(atPath: current.path) {
                    try FileManager.default.moveItem(at: current, to: previous)
                }
            }
            if FileManager.default.fileExists(atPath: current.path) {
                let handle = try FileHandle(forWritingTo: current)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: current, options: .atomic)
            }
            } catch {
                // Diagnostics must never interfere with application behavior.
            }
        }
    }

    static func exportText() -> String {
        ioQueue.sync {
            guard let directory = logDirectoryURL else { return "FilterKit diagnostics unavailable." }
            let files = [directory.appendingPathComponent(previousName), directory.appendingPathComponent(currentName)]
            return files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        }
    }

    static func clear() {
        ioQueue.sync {
            guard let directory = logDirectoryURL else { return }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(currentName))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(previousName))
        }
    }
}
