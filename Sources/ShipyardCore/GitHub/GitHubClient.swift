import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in GitHub account.
public struct Viewer: Equatable, Sendable, Decodable {
    public var login: String
    public var id: Int

    public init(login: String, id: Int) {
        self.login = login
        self.id = id
    }
}

/// Why a request to GitHub's API failed.
public enum GitHubError: Error, Equatable, Sendable {
    /// 401: the token is missing, revoked or expired. Shipyard signs out.
    case unauthorized
    /// Any other unexpected HTTP status.
    case http(Int)
    /// The request didn't reach GitHub.
    case network(String)
    /// GitHub's answer couldn't be read.
    case malformed
}

/// Talks to GitHub's API with one token. Every request goes through `send`,
/// which authorises it and turns a 401 into `GitHubError.unauthorized`.
public struct GitHubClient: Sendable {
    public static let apiURL = URL(string: "https://api.github.com")!

    private let token: String
    private let transport: any HTTPTransport

    public init(token: String, transport: any HTTPTransport) {
        self.token = token
        self.transport = transport
    }

    /// The account the token belongs to.
    public func viewer() async throws -> Viewer {
        let request = URLRequest(url: Self.apiURL.appendingPathComponent("user"))
        let (data, _) = try await send(request)
        guard let viewer = try? JSONDecoder().decode(Viewer.self, from: data) else { throw GitHubError.malformed }
        return viewer
    }

    /// Sends `request` with the token and GitHub's headers. A 401 throws
    /// `.unauthorized`; other non-2xx statuses throw `.http`; transport
    /// failures throw `.network`; cancellation throws `CancellationError`.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("shipyard/\(ShipyardVersion.current)", forHTTPHeaderField: "User-Agent")
        if request.timeoutInterval > 30 { request.timeoutInterval = 30 }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw GitHubError.network(error.localizedDescription)
        }
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 401: throw GitHubError.unauthorized
        default: throw GitHubError.http(response.statusCode)
        }
    }
}
