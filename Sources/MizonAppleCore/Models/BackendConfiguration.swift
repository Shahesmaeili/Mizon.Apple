import Foundation

public struct BackendConfiguration: Sendable, Equatable {
    public static let defaultAddress = "https://localhost:5128"
    public let baseURL: URL
    public init(address: String) throws {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else { throw LoginFailure.invalidServer }
        baseURL = url
    }
}

public struct AuthSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let sessionPublicId: UUID
    public let clientPublicId: UUID
    public let identifier: String
    public let server: URL
    public init(accessToken: String, refreshToken: String, sessionPublicId: UUID, clientPublicId: UUID, identifier: String, server: URL) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.sessionPublicId = sessionPublicId; self.clientPublicId = clientPublicId
        self.identifier = identifier; self.server = server
    }
}

public enum LoginFailure: Error, LocalizedError, Sendable, Equatable {
    case invalidServer, invalidResponse, storage(Int32)
    case api(code: Int, title: String, details: String, closeButton: String?)
    public var errorDescription: String? {
        switch self {
        case .invalidServer: "آدرس سرور معتبر نیست"
        case .invalidResponse: "پاسخ سرور کامل نیست"
        case .storage: "ذخیرهٔ امن نشست انجام نشد"
        case .api(let code, let title, _, _):
            switch code {
            case 101, 102, 107: "اتصال به سرور برقرار نشد"
            case 104, 106: "زمان انتظار به پایان رسید"
            case 103: "پاسخ سرور قابل خواندن نیست"
            default: title
            }
        }
    }
    public var details: String {
        switch self {
        case .invalidServer: return "یک آدرس HTTPS بدون نام کاربری، رمز یا پارامتر وارد کنید."
        case .invalidResponse: return "سرور توکن معتبری برنگرداند. لطفاً دوباره تلاش کنید."
        case .storage: return "دسترسی به Keychain را بررسی کنید و دوباره تلاش کنید."
        case .api(let code, _, let details, _):
            if [101, 102, 104, 106, 107].contains(code) { return "اتصال به سرور برقرار نشد. آدرس سرور و اتصال اینترنت را بررسی کنید." }
            return details
        }
    }
    public var closeButtonText: String {
        if case .api(_, _, _, let close) = self, let close, !close.isEmpty { return close }
        return "متوجه شدم"
    }
}
