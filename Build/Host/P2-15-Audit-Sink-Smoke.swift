import Foundation

struct HelperPeerIdentity {
    let uid: UInt32; let gid: UInt32; let pid: Int32; let cdHashHex: String
}
enum HelperOperation: String, Codable { case test }
struct HelperAuditRecord: Codable {
    let eventID: UUID
    let timestamp: Date
    let requestID: UUID?
    let operation: HelperOperation?
    let peerUID: UInt32?
    let peerGID: UInt32?
    let peerPID: Int32?
    let peerCDHash: String?
    let outcome: String
    let reasonCode: String
    let changedRelativePaths: [String]
    let sourceSHA256: String?
    let output: String?
    init(requestID: UUID? = nil, operation: HelperOperation? = nil, peer: HelperPeerIdentity? = nil,
         outcome: String, reasonCode: String, changedRelativePaths: [String] = [],
         sourceSHA256: String? = nil, output: String? = nil, timestamp: Date = Date()) {
        eventID = UUID(); self.timestamp = timestamp; self.requestID = requestID; self.operation = operation
        peerUID = peer?.uid; peerGID = peer?.gid; peerPID = peer?.pid; peerCDHash = peer?.cdHashHex
        self.outcome = outcome; self.reasonCode = reasonCode; self.changedRelativePaths = changedRelativePaths
        self.sourceSHA256 = sourceSHA256; self.output = output
    }
}
protocol HelperAuditSink { func append(_ record: HelperAuditRecord) throws }

@main struct P215AuditSmoke {
    static func main() throws {
        let directory = "/tmp/filterkit-p215-audit-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let path = directory + "/audit.jsonl"
        let sink = HelperAuditFileSink(path: path, maximumBytes: 4096, retainedFiles: 2)
        for index in 0..<12 {
            try sink.append(HelperAuditRecord(outcome: "accepted", reasonCode: "p215_smoke_\(index)",
                                               output: String(repeating: "x", count: 700)))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory)
        guard names.contains("audit.jsonl"), names.filter({ $0.hasPrefix("audit.jsonl") }).count <= 3 else {
            throw NSError(domain: "P215", code: 1)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
            throw NSError(domain: "P215", code: 2)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard data.last == 0x0A else { throw NSError(domain: "P215", code: 3) }
        print("PASS: audit append is newline-complete, mode 0600, bounded rotation, fsync path exercised")
    }
}
