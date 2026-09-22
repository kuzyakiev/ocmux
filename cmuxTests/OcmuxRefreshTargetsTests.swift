import CmuxControlSocket
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Pins the "which panes may be refreshed" rule: the ⟳ controls respawn only
/// surfaces whose resume binding was written by `ocmux-open`, and never a plain
/// shell, editor or agent pane that happens to sit in the same workspace.
@Suite
struct OcmuxRefreshTargetsTests {
    @Test("An ocmux-tagged terminal surface is a refresh target")
    func taggedTerminalIsTarget() {
        let surfaceID = UUID()
        let targets = OcmuxRefresh.targets(in: [
            makeSummary(surfaceID: surfaceID, command: "ocmux-open h1t", cwd: "/Users/oleg")
        ])

        #expect(targets == [
            OcmuxRefresh.Target(
                surfaceID: surfaceID,
                command: "ocmux-open h1t",
                workingDirectory: "/Users/oleg"
            )
        ])
    }

    @Test("Untagged terminal surfaces are never refreshed")
    func untaggedTerminalsAreSkipped() {
        let targets = OcmuxRefresh.targets(in: [
            makeSummary(command: "exec ${SHELL:-/bin/zsh} -l"),
            makeSummary(command: "claude --resume"),
            makeSummary(command: "nvim ."),
            makeSummary(command: nil)
        ])

        #expect(targets.isEmpty)
    }

    @Test("The tag must be the exact ocmux-open prefix")
    func prefixMustMatchExactly() {
        #expect(OcmuxRefresh.isTaggedCommand("ocmux-open h1t"))
        #expect(OcmuxRefresh.isTaggedCommand("   ocmux-open h1t"))
        #expect(!OcmuxRefresh.isTaggedCommand("ocmux-opener h1t"))
        #expect(!OcmuxRefresh.isTaggedCommand("ocmux-open"))
        #expect(!OcmuxRefresh.isTaggedCommand("sudo ocmux-open h1t"))
        #expect(!OcmuxRefresh.isTaggedCommand(nil))
    }

    @Test("A non-terminal surface is never refreshed, tag or not")
    func nonTerminalSurfacesAreSkipped() {
        let targets = OcmuxRefresh.targets(in: [
            makeSummary(command: "ocmux-open h1t", isTerminal: false)
        ])

        #expect(targets.isEmpty)
    }

    @Test("Tagged surfaces are returned in snapshot order, untagged ones dropped")
    func mixedSnapshotKeepsOnlyTaggedSurfacesInOrder() {
        let first = UUID()
        let second = UUID()
        let targets = OcmuxRefresh.targets(in: [
            makeSummary(surfaceID: first, command: "ocmux-open h1t"),
            makeSummary(command: "exec /bin/zsh -l"),
            makeSummary(surfaceID: second, command: "ocmux-open po"),
            makeSummary(command: nil)
        ])

        #expect(targets.map(\.surfaceID) == [first, second])
        #expect(targets.map(\.command) == ["ocmux-open h1t", "ocmux-open po"])
    }

    // MARK: - Fixtures

    private func makeSummary(
        surfaceID: UUID = UUID(),
        command: String?,
        cwd: String? = nil,
        isTerminal: Bool = true
    ) -> ControlSurfaceSummary {
        ControlSurfaceSummary(
            surfaceID: surfaceID,
            typeRawValue: isTerminal ? "terminal" : "browser",
            title: "pane",
            isFocused: false,
            paneID: nil,
            indexInPane: nil,
            selectedInPane: nil,
            developerToolsVisible: nil,
            requestedWorkingDirectory: cwd,
            initialCommand: command,
            tmuxStartCommand: command,
            isTerminal: isTerminal,
            resumeBinding: command.map { makeBinding(command: $0, cwd: cwd) }
        )
    }

    private func makeBinding(command: String, cwd: String?) -> ControlSurfaceResumeBinding {
        ControlSurfaceResumeBinding(
            name: nil,
            kind: nil,
            command: command,
            cwd: cwd,
            checkpointID: nil,
            source: nil,
            environment: nil,
            launchCommand: nil,
            permissionMode: nil,
            autoResume: true,
            approvalPolicyRawValue: nil,
            approvalRecordID: nil,
            executionLocationRawValue: "local",
            remoteWorkspaceID: nil,
            remoteSurfaceID: nil,
            remotePTYSessionID: nil,
            updatedAt: 0
        )
    }
}
