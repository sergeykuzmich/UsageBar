import Foundation

/// Probes drive `Process` and pipes, which block. Keep that off the main actor so the
/// menu bar stays responsive while a CLI starts up.
func offMainActor<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: Result { try body() })
        }
    }
}
