import Foundation

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
