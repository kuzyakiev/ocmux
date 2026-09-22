import CmuxControlSocket
import Foundation

/// ocmux session refresh: respawning the server panes this fork opens through
/// `ocmux-open`, and only those.
///
/// A surface is ocmux-tagged when its resume binding command starts with the
/// literal `ocmux-open ` prefix. The tag is written by `ocmux-tools/ocmux-open`
/// (through `cmux surface resume set`), so it reproduces itself across every
/// refresh. Refreshing a tagged surface respawns it with that same command.
/// Untagged surfaces — plain shells, editors, agent panes — are never touched.
enum OcmuxRefresh {
    /// The literal resume-command prefix that marks a surface as ocmux-owned.
    static let taggedCommandPrefix = "ocmux-open "

    /// One refreshable surface: the pane plus the command that re-opens it.
    struct Target: Equatable {
        let surfaceID: UUID
        let command: String
        let workingDirectory: String?
    }

    /// Whether a resume command marks its surface as ocmux-owned.
    ///
    /// Leading whitespace is tolerated so a hand-edited binding still matches;
    /// everything else must be the literal prefix.
    static func isTaggedCommand(_ command: String?) -> Bool {
        guard let command else { return false }
        return command.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(taggedCommandPrefix)
    }

    /// The ocmux-tagged terminal surfaces inside a `surface.list`-shaped snapshot.
    ///
    /// This is the whole "which panes may be refreshed" rule: a pure filter, so
    /// the never-respawn-an-untagged-pane guarantee is testable without a window.
    static func targets(in surfaces: [ControlSurfaceSummary]) -> [Target] {
        surfaces.compactMap { summary in
            guard summary.isTerminal,
                  let binding = summary.resumeBinding,
                  isTaggedCommand(binding.command) else { return nil }
            return Target(
                surfaceID: summary.surfaceID,
                command: binding.command,
                workingDirectory: binding.cwd
            )
        }
    }
}

@MainActor
extension AppDelegate {
    /// Respawns every ocmux-tagged surface in every open main window.
    ///
    /// - Returns: How many surfaces respawned.
    @discardableResult
    func ocmuxRefreshAllTaggedSurfaces() -> Int {
        var refreshed = 0
        for context in mainWindowContexts.values {
            for workspace in context.tabManager.tabs {
                refreshed += ocmuxRefreshTaggedSurfaces(in: workspace)
            }
        }
        return refreshed
    }

    /// Respawns the ocmux-tagged surfaces owned by one workspace row.
    ///
    /// - Returns: How many surfaces respawned.
    @discardableResult
    func ocmuxRefreshTaggedSurfaces(workspaceId: UUID) -> Int {
        guard let tabManager = tabManagerFor(tabId: workspaceId),
              let workspace = tabManager.workspacesById[workspaceId] else {
            return 0
        }
        return ocmuxRefreshTaggedSurfaces(in: workspace)
    }

    private func ocmuxRefreshTaggedSurfaces(in workspace: Workspace) -> Int {
        let summaries = TerminalController.shared.controlSurfaceSummaries(workspace: workspace)
        var refreshed = 0
        for target in OcmuxRefresh.targets(in: summaries) {
            let routing = ControlRoutingSelectors(
                hasWindowIDParam: false,
                windowID: nil,
                groupID: nil,
                workspaceID: workspace.id,
                surfaceID: target.surfaceID,
                paneID: nil
            )
            let inputs = ControlSurfaceRespawnInputs(
                command: target.command,
                tmuxStartCommand: target.command,
                workingDirectory: target.workingDirectory,
                hasSurfaceIDParam: true,
                requestedSurfaceID: target.surfaceID,
                hasFocusParam: false,
                requestedFocus: false
            )
            if case .respawned = TerminalController.shared.controlSurfaceRespawn(
                routing: routing,
                inputs: inputs
            ) {
                refreshed += 1
            }
        }
        return refreshed
    }
}
