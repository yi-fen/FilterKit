import Foundation

enum FilterKitOperation: String, Codable {
    case inspectImport
    case installPlugin
    case updatePlugin
    case setPluginEnabled
    case uninstallPlugin
    case verifyDeployment
    case exportBackup
    case restoreBackup
    case cleanTemporaryFiles
}

struct OperationReceipt: Codable {
    let operationID: UUID
    let succeeded: Bool
    let messageCode: String
    let completedAt: Date
}
