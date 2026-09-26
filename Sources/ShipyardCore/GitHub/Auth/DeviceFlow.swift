import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The GitHub OAuth App shipyard signs in through with the device flow.
public enum OAuthApp {
    /// The OAuth App's client ID, compiled in. Not a secret: the device flow
    /// has no client secret, so it's safe in a desktop app.
    ///
    /// The maintainer supplies it: register an OAuth App under the maintainer's
    /// GitHub account with device flow enabled, and put its client ID here.
    /// Forks put their own (the README says how). While it's the placeholder,
    /// the connect screen shows Sign in with GitHub as unavailable and `gh`
    /// stays the way in.
    public static let clientID = "REPLACE_WITH_OAUTH_APP_CLIENT_ID"

    /// Stands in for the client ID until the maintainer supplies it; the
    /// device flow refuses to start while it's still set.
    public static let placeholderClientID = "REPLACE_WITH_OAUTH_APP_CLIENT_ID"

    /// Whether `clientID` is a real client ID rather than the placeholder.
    public static func isSet(_ clientID: String) -> Bool {
        !clientID.isEmpty && clientID != placeholderClientID
    }

    /// Private repositories' pull requests and issues, and organisation repositories.
    public static let scopes = "repo read:org"
}

/// What GitHub's device flow asks the user to do: enter `userCode` at
/// `verificationURL` before `expiresAt`. Shown while shipyard is connecting.
public struct DeviceCode: Equatable, Sendable {
    public var userCode: String
    public var verificationURL: URL
    public var expiresAt: Date

    public init(userCode: String, verificationURL: URL, expiresAt: Date) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
    }
}

/// A requested device code: what the user sees, plus what polling needs.
public struct DeviceAuthorization: Equatable, Sendable {
    /// The secret half, sent back when polling; never shown.
    public var deviceCode: String
    public var code: DeviceCode
    /// Seconds between polls, as GitHub asked.
    public var interval: TimeInterval

    public init(deviceCode: String, code: DeviceCode, interval: TimeInterval) {
        self.deviceCode = deviceCode
        self.code = code
        self.interval = interval
    }
}

/// Why the device flow ended without a token.
public enum DeviceFlowError: Error, Equatable, Sendable {
    /// `OAuthApp.clientID` is still the placeholder.
    case clientIDMissing
    /// The code expired (15 minutes) before the user entered it; start over.
    case expired
    /// The user declined on github.com.
    case denied
    /// GitHub answered 401.
    case unauthorized
    /// GitHub answered with an error code the flow doesn't expect, for
    /// example `device_flow_disabled` or `incorrect_client_credentials`.
    case rejected(String)
    /// GitHub answered with an unexpected HTTP status.
    case http(Int)
    /// The request didn't reach GitHub.
    case network(String)
    /// GitHub's answer couldn't be read.
    case malformed
}

/// GitHub's OAuth device flow: request a code, let the user enter it on
/// github.com, poll for the token. See `docs/references/github-device-flow.md`.
public struct DeviceFlow: Sendable {
    public static let codeURL = URL(string: "https://github.com/login/device/code")!
    public static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    static let defaultVerificationURL = URL(string: "https://github.com/login/device")!
    /// GitHub's codes last 900 seconds; used when the answer doesn't say.
    static let defaultLifetime: TimeInterval = 900
    /// GitHub's minimum poll interval; used when the answer doesn't say.
    static let defaultInterval: TimeInterval = 5
    /// What a `slow_down` answer adds to the interval.
    static let slowDownStep: TimeInterval = 5

    private let clientID: String
    private let transport: any HTTPTransport
    private let clock: any WallClock
    private let sleep: Sleep

    public init(
        clientID: String = OAuthApp.clientID,
        transport: any HTTPTransport,
        clock: any WallClock = SystemClock(),
        sleep: @escaping Sleep = systemSleep
    ) {
        self.clientID = clientID
        self.transport = transport
        self.clock = clock
        self.sleep = sleep
    }

    /// Asks GitHub for a device code and the user code to show.
    public func requestCode() async throws -> DeviceAuthorization {
        guard OAuthApp.isSet(clientID) else { throw DeviceFlowError.clientIDMissing }
        let requestedAt = clock.now
        let answer: CodeAnswer = try await post(Self.codeURL, form: ["client_id": clientID, "scope": OAuthApp.scopes])
        if let error = answer.error { throw DeviceFlowError.rejected(error) }
        guard let deviceCode = answer.deviceCode, let userCode = answer.userCode else {
            throw DeviceFlowError.malformed
        }
        let verificationURL = answer.verificationUri.flatMap { URL(string: $0) } ?? Self.defaultVerificationURL
        return DeviceAuthorization(
            deviceCode: deviceCode,
            code: DeviceCode(
                userCode: userCode,
                verificationURL: verificationURL,
                expiresAt: requestedAt.addingTimeInterval(answer.expiresIn ?? Self.defaultLifetime)
            ),
            interval: answer.interval ?? Self.defaultInterval
        )
    }

    /// Polls until the user approves, waiting `interval` seconds before each
    /// poll and 5 more after every `slow_down`. Throws `.expired` once the
    /// code has expired, and `CancellationError` when the task is cancelled.
    public func waitForToken(_ authorization: DeviceAuthorization) async throws -> String {
        var interval = authorization.interval
        while true {
            try await sleep(interval)
            try Task.checkCancellation()
            guard clock.now < authorization.code.expiresAt else { throw DeviceFlowError.expired }

            let answer: TokenAnswer = try await post(Self.tokenURL, form: [
                "client_id": clientID,
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = answer.accessToken, !token.isEmpty { return token }
            switch answer.error {
            case "authorization_pending": continue
            case "slow_down": interval += Self.slowDownStep
            case "expired_token": throw DeviceFlowError.expired
            case "access_denied": throw DeviceFlowError.denied
            case let other?: throw DeviceFlowError.rejected(other)
            case nil: throw DeviceFlowError.malformed
            }
        }
    }

    // MARK: - Requests

    private struct CodeAnswer: Decodable {
        var deviceCode: String?
        var userCode: String?
        var verificationUri: String?
        var expiresIn: TimeInterval?
        var interval: TimeInterval?
        var error: String?
    }

    private struct TokenAnswer: Decodable {
        var accessToken: String?
        var error: String?
    }

    private func post<Answer: Decodable>(_ url: URL, form: [String: String]) async throws -> Answer {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncoded(form).utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw DeviceFlowError.network(error.localizedDescription)
        }
        switch response.statusCode {
        case 200: break
        case 401: throw DeviceFlowError.unauthorized
        default: throw DeviceFlowError.http(response.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let answer = try? decoder.decode(Answer.self, from: data) else {
            throw DeviceFlowError.malformed
        }
        return answer
    }

    /// `application/x-www-form-urlencoded`, keys sorted, escaping everything
    /// but RFC 3986's unreserved characters.
    static func formEncoded(_ form: [String: String]) -> String {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
        }
        return form.keys.sorted().map { "\(encode($0))=\(encode(form[$0]!))" }.joined(separator: "&")
    }
}
