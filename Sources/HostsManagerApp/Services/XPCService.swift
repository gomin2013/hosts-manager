import Foundation
import Shared

/// Async client for the root helper. An actor so the cached connection is safe to touch from any task.
actor XPCService {
    /// `endpoint` connects to an in-process anonymous listener instead of the launchd Mach service
    /// (integration tests run the real `HelperService` over real XPC that way).
    init(endpoint: NSXPCListenerEndpoint? = nil) {
        self.endpoint = endpoint
    }

    private let endpoint: NSXPCListenerEndpoint?
    private var connection: NSXPCConnection?
    /// Writes + DNS flush take well under a second; anything near this means the helper is stuck.
    static let timeout = Duration.seconds(30)

    func version() async throws -> String {
        try await call { helper, done in helper.version { done(.success($0)) } }
    }

    /// Throws `HelperError` (`.staleFile` when /etc/hosts changed since `expectedSHA256` was computed).
    func writeHosts(_ content: String, expectedSHA256: String) async throws {
        try await call { helper, done in
            helper.writeHosts(content, expectedSHA256: expectedSHA256) { error in
                done(error.map { .failure(HelperError($0) ?? .writeFailed) } ?? .success(()))
            }
        }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Private

    /// Runs one request; a broken connection fails it with `.connectionFailed` (helper not installed/approved).
    private func call<T: Sendable>(
        _ body: @escaping (any HelperProtocol, @escaping @Sendable (Result<T, HelperError>) -> Void) -> Void
    ) async throws -> T {
        let conn = connectIfNeeded()
        do {
            return try await send(on: conn, body)
        } catch HelperError.connectionFailed {
            // Invalidated (helper not approved / crashed / rejected us): drop it so the next call reconnects.
            // ponytail: no invalidation handlers — their closures aren't Sendable under Swift 6.1 (Xcode 16)
            conn.invalidate()
            if connection === conn { connection = nil }
            throw HelperError.connectionFailed
        }
    }

    private func send<T: Sendable>(
        on conn: NSXPCConnection,
        _ body: @escaping (any HelperProtocol, @escaping @Sendable (Result<T, HelperError>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            // A registered-but-silent helper would otherwise leave the UI saving forever.
            Task {
                try? await Task.sleep(for: Self.timeout)
                once.resume(.failure(.connectionFailed))
            }
            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in once.resume(.failure(.connectionFailed)) }
            guard let helper = proxy as? any HelperProtocol else {
                return once.resume(.failure(.connectionFailed))
            }
            body(helper) { once.resume($0) }
        }
    }

    private func connectIfNeeded() -> NSXPCConnection {
        if let connection { return connection }
        let conn = endpoint.map(NSXPCConnection.init(listenerEndpoint:))
            ?? NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.resume()
        connection = conn
        return conn
    }

}

/// XPC may call both the error handler and (never, in practice) the reply; resume the continuation once.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resume(_ result: Result<T, HelperError>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result.mapError { $0 })
    }
}
