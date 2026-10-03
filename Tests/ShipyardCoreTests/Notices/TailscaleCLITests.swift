import Foundation
import ShipyardCommand
@testable import ShipyardCore
import Testing

/// How the app learns the Mac's own Tailscale login: `tailscale status
/// --json`, the platform contract the identity check stands on. The
/// outputs are cut down from Tailscale 1.102's, keeping the keys read.
@Suite("The Mac's own Tailscale login")
struct TailscaleCLITests {
    static func status(_ state: String, selfUser: Int64 = 5164670205920714, users: String = #""5164670205920714":{"ID":5164670205920714,"LoginName":"me@example.com","DisplayName":"Me"}"#) -> String {
        #"{"Version":"1.102.4","BackendState":"\#(state)","Self":{"ID":"n1","HostName":"my-mac","UserID":\#(selfUser),"Online":true},"#
            + #""Peer":{"k":{"HostName":"vps","UserID":1}},"User":{\#(users),"1":{"ID":1,"LoginName":"other@example.com"}}}"#
    }

    /// `TailscaleCLI` with `tailscale` at the first known place, printing `output`.
    func cli(_ output: CommandOutput?, installed: Bool = true) -> TailscaleCLI {
        TailscaleCLI(isExecutable: { installed && $0 == TailscaleCLI.knownPaths[0] }, pathEnvironment: nil) { executable, arguments in
            #expect(executable == "/usr/local/bin/tailscale")
            #expect(arguments == ["status", "--json"])
            return output
        }
    }

    @Test("running, it's the login of the user the Mac's own device belongs to, not a peer's")
    func running() async {
        #expect(await cli(CommandOutput(status: 0, standardOutput: Self.status("Running"))).ownLogin() == .success("me@example.com"))
    }

    @Test("stopped, logged out, missing or failing, it's unknown with why", arguments: [
        (CommandOutput(status: 0, standardOutput: status("Stopped")), "Tailscale is stopped"),
        (CommandOutput(status: 0, standardOutput: status("NeedsLogin")), "Tailscale needs you to log in"),
        (CommandOutput(status: 0, standardOutput: status("Running", selfUser: 99)), "`tailscale status` named no login for this Mac"),
        (CommandOutput(status: 0, standardOutput: "not json"), "`tailscale status --json` printed something it couldn't read"),
        (CommandOutput(status: 1, standardOutput: ""), "`tailscale status` failed (exit 1)"),
        (nil, "`tailscale status` didn't answer, or couldn't be run"),
    ] as [(CommandOutput?, String)])
    func unknown(output: CommandOutput?, reason: String) async {
        #expect(await cli(output).ownLogin() == .failure(TailnetLoginUnknown(reason)))
    }

    @Test("without the tailscale command anywhere, it's unknown")
    func notInstalled() async {
        #expect(await cli(nil, installed: false).ownLogin() == .failure(TailnetLoginUnknown("the tailscale command wasn't found")))
    }
}
