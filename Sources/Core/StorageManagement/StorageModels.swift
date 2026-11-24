import Foundation

enum StorageCategory: String, CaseIterable, Codable {
    case scanCache
    case temporaryExtraction
    case importStaging
    case backupRestoreTemporary
}

struct StorageUsage: Codable, Equatable {
    let scanCacheBytes: Int64
    let temporaryBytes: Int64
    let backupRestoreTemporaryBytes: Int64
    let protectedPluginBytes: Int64
    let userBackupBytes: Int64

    var cleanableBytes: Int64 {
        scanCacheBytes + temporaryBytes + backupRestoreTemporaryBytes
    }
}

struct StorageCleanupReceipt: Codable {
    let removedBytes: Int64
    let removedFileCount: Int
    let skippedActiveTaskCount: Int
}
