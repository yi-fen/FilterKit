import Foundation
protocol HelperIPCTransport { func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope }
