import Foundation
import ShipyardCommand
import ShipyardCore

struct FakeGitRemote: GitRemoteLookup {
    private let origins: [String: String]

    init(_ origins: [URL: String] = [:]) {
        self.origins = Dictionary(origins.map { ($0.key.standardizedFileURL.path, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    func origin(in folder: URL) -> String? {
        origins[folder.standardizedFileURL.path]
    }
}
