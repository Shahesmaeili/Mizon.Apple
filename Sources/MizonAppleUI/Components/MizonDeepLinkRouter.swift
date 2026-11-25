#if os(macOS) || os(iOS)
import Combine
import Foundation
import MizonAppleCore

@MainActor
public final class MizonDeepLinkRouter: ObservableObject {
    public static let shared = MizonDeepLinkRouter()

    struct Request: Equatable, Identifiable {
        let id: UUID
        let route: MizonDeepLink
        let expectsResult: Bool
    }

    struct AuthorizedLink: Equatable {
        let id: UUID
        let route: MizonDeepLink
        let sessionID: UUID
    }

    private struct ActiveRequest {
        let request: Request
        let responseID: UUID
        let reply: CheckedContinuation<MizonDeepLinkResult, Never>?
    }

    @Published private(set) var pending: Request?
    @Published private(set) var authorized: AuthorizedLink?
    public var activateMainWindow: (() -> Void)?
    private var active: ActiveRequest?
    private var timeout: Task<Void, Never>?
    private let testTimeout: Duration?

    init(timeout: Duration? = nil) { testTimeout = timeout }

    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let route = MizonDeepLink(url: url) else { return false }
        begin(route, id: UUID(), responseID: UUID(), reply: nil)
        return true
    }

    public func result(for rawValue: String, requestID: UUID = UUID(),
                       version: Int = MizonDeepLinkResult.protocolVersion) async -> MizonDeepLinkResult {
        guard version == MizonDeepLinkResult.protocolVersion else {
            return .failure(requestID: requestID, code: "unsupported_version", message: "The deep-link response version is not supported.")
        }
        guard let route = MizonDeepLink(rawValue: rawValue) else {
            return .failure(requestID: requestID, code: "invalid_uri", message: "The URI is not a supported Mizon destination.")
        }
        activateMainWindow?()
        return await result(for: route, requestID: requestID)
    }

    func result(for route: MizonDeepLink, requestID: UUID = UUID()) async -> MizonDeepLinkResult {
        let id = UUID()
        return await withTaskCancellationHandler {
            if Task.isCancelled {
                return .failure(requestID: requestID, code: "cancelled", message: "Navigation was cancelled before it started.")
            }
            return await withCheckedContinuation { reply in
                begin(route, id: id, responseID: requestID, reply: reply)
            }
        } onCancel: {
            Task { @MainActor in
                self.fail(id: id, code: "cancelled", message: "Navigation was cancelled before it completed.")
            }
        }
    }

    func dispatch(_ request: Request) {
        guard active?.request == request else { return }
        pending = nil
        if timeout == nil { armTimeout(for: request) }
    }

    func dispatch(_ request: Request, sessionID: UUID) {
        guard active?.request == request else { return }
        dispatch(request)
        authorized = AuthorizedLink(id: request.id, route: request.route, sessionID: sessionID)
    }

    func isActive(_ request: AuthorizedLink) -> Bool {
        active?.request.id == request.id && authorized == request
    }

    func complete(_ request: AuthorizedLink, stage: MizonDeepLinkResult.Stage) {
        guard isActive(request) else { return }
        complete(id: request.id, stage: stage)
    }

    func fail(_ request: AuthorizedLink, code: String, message: String) {
        guard isActive(request) else { return }
        fail(id: request.id, code: code, message: message)
    }

    func complete(id: UUID, stage: MizonDeepLinkResult.Stage) {
        guard let active, active.request.id == id else { return }
        finish(.success(requestID: active.responseID, route: active.request.route, stage: stage))
    }

    func fail(id: UUID, code: String, message: String) {
        guard let active, active.request.id == id else { return }
        finish(.failure(requestID: active.responseID, code: code, message: message))
    }

    func finishShowingAccount(id: UUID) {
        guard let request = active?.request, request.id == id,
              request.route == .login || request.route == .register else { return }
        complete(id: id, stage: .opened)
    }

    func cancelActive(code: String, message: String) {
        if let id = active?.request.id { fail(id: id, code: code, message: message) }
    }

    func cancelDispatched() {
        guard pending == nil else { return }
        cancelActive(code: "page_changed", message: "The Mizon window closed before the destination finished.")
    }

    public func applicationWillClose() {
        cancelActive(code: "app_closed", message: "Mizon closed before the destination finished.")
    }

    private func begin(_ route: MizonDeepLink, id: UUID, responseID: UUID,
                       reply: CheckedContinuation<MizonDeepLinkResult, Never>?) {
        cancelActive(code: "superseded", message: "A newer navigation request replaced this request.")
        let request = Request(id: id, route: route, expectsResult: reply != nil)
        active = ActiveRequest(request: request, responseID: responseID, reply: reply)
        if request.expectsResult { armTimeout(for: request) }
        pending = request
    }

    private func armTimeout(for request: Request) {
        let duration = testTimeout ?? request.route.responseTimeout
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.fail(id: request.id, code: "timed_out", message: "The destination did not finish before the response deadline.")
        }
    }

    private func finish(_ result: MizonDeepLinkResult) {
        let reply = active?.reply
        active = nil
        timeout?.cancel()
        timeout = nil
        pending = nil
        authorized = nil
        reply?.resume(returning: result)
    }
}
#endif
