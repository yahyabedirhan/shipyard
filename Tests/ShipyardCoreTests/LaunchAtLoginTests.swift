import Foundation
@testable import ShipyardCore
import Testing

// `launch-at-login` registers shipyard as a login item (the default) or
// removes it, when shipyard starts and whenever the configuration changes.
@MainActor
@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test("with no configuration file, starting registers the login item")
    func defaultRegisters() async throws {
        let harness = try Harness()
        await harness.shipyard.start()
        #expect(harness.loginItem.settings == [true])
    }

    @Test("turning it off in the configuration removes the login item at once, and on again registers it")
    func liveChange() async throws {
        let harness = try Harness(config: "version = 1\n")
        await harness.shipyard.start()

        try harness.writeConfig("version = 1\nlaunch-at-login = false\n")
        await harness.shipyard.reloadConfiguration()
        #expect(harness.loginItem.settings == [true, false])

        try harness.writeConfig("version = 1\nlaunch-at-login = true\n")
        await harness.shipyard.reloadConfiguration()
        #expect(harness.loginItem.settings == [true, false, true])
    }

    @Test("a broken edit leaves the login item as the last valid configuration set it")
    func brokenEdit() async throws {
        let harness = try Harness(config: "version = 1\nlaunch-at-login = false\n")
        await harness.shipyard.start()

        try harness.writeConfig("version = 1\nlaunch-at-login = \"yes\"\n")
        await harness.shipyard.reloadConfiguration()
        #expect(harness.loginItem.settings == [false])
    }

    @Test("a file that's broken at launch leaves the login item alone, rather than applying the default")
    func brokenAtLaunch() async throws {
        // Written as false before it broke: registering (the default) would undo that.
        let harness = try Harness(config: "version = 1\nlaunch-at-login = false\nrefresh-interval-seconds = \"oops\"\n")
        await harness.shipyard.start()
        #expect(harness.shipyard.configError != nil)
        #expect(harness.loginItem.settings.isEmpty)

        try harness.writeConfig("version = 1\nlaunch-at-login = false\n")
        await harness.shipyard.reloadConfiguration()
        #expect(harness.loginItem.settings == [false])
    }
}
