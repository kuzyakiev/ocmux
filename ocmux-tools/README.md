# ocmux-tools

Session refresh for ocmux: reconnect every SSH/tmux pane after a network change,
without hunting through tabs.

## The problem

Panes are opened from zsh aliases (`h1t`, `a2h1t`, `poh1t`) that `ssh` to a host
and `tmux a -t <session>`. Switch networks and every one of them dies at once.
The tmux sessions survive on the remote; only the local clients are gone. So the
fix is mechanical: re-run each pane's alias and it lands back in its session.

The obstacle is identity — cmux has no idea a given pane "is `h1t`". Typing an
alias into a shell is invisible to the app.

## How it works

`ocmux-open <alias>` runs in the pane's LOCAL shell, before `ssh` takes over, so
`$CMUX_SURFACE_ID` still identifies the surface. It tags the surface with cmux's
own per-surface resume binding, then hands the pane to the alias:

    cmux surface resume set --surface "$CMUX_SURFACE_ID" --shell "ocmux-open h1t"
    zsh -ic "h1t"
    exec ${SHELL:-/bin/zsh} -l

The tag is `ocmux-open <alias>` — literally the command that produced it, so
replaying it re-tags the pane. Self-reproducing across any number of refreshes.

The alias deliberately does **not** run under `exec`, and the trailing login
shell is load-bearing. cmux closes any surface whose root process exits after
more than ~250ms of runtime (`TerminalChildExitPolicy`), and a closed surface
takes its resume binding with it — leaving the ⟳ controls nothing to respawn.

A pane opened from the "+" menu survives a dropped `ssh` anyway, because
`CmuxConfigExecutor` types the alias into an interactive shell as `initialInput`
rather than launching it as the pane's command, so a shell is already sitting
underneath. A *refreshed* pane is different: `surface.respawn` runs
`ocmux-open <alias>` as the pane's root process. Without the fallback shell the
first dropped connection after a refresh would also be the last one refresh
could repair — measured: the surface disappeared from `system.tree` entirely,
and a second ⟳ had nothing to act on.

`ocmux-refresh` then enumerates surfaces, keeps the ones whose resume binding
starts with `ocmux-open `, and replays each. Panes with no tag — plain shells,
editors, agent sessions — are never touched.

## Install

    ln -sf "$PWD/ocmux-open"        ~/.local/bin/ocmux-open
    ln -sf "$PWD/ocmux-refresh"     ~/.local/bin/ocmux-refresh
    ln -sf "$PWD/ocmux-sync-config" ~/.local/bin/ocmux-sync-config
    mkdir -p ~/.config/ocmux
    cp servers.jsonc ~/.config/ocmux/servers.jsonc

Edit `~/.config/ocmux/servers.jsonc`, then:

    ocmux-sync-config        # renders the registry into ~/.config/cmux/cmux.json
    cmux reload-config       # or Cmd+Shift+,

The aliases now appear in the "+" button menu. Picking one opens a tagged pane.

## Usage

    ocmux-refresh                      # replay every tagged pane
    ocmux-refresh --dry-run            # show what would happen
    ocmux-refresh --surface surface:11 # just one
    ocmux-refresh --force              # include panes that look busy

## Landmines (measured, not assumed)

These cost real time to find. Do not re-derive them.

**`scripts/reload.sh` exit codes are meaningless.** It exits 0 when it does not
build at all (missing `CMUX_DEV_BACKEND_MODE=local`, where it prints a note about
the shared GCP backend helper and quits), AND it exits 0 when the build genuinely
FAILS — the real status 65 is swallowed. Always grep the log for
`** BUILD SUCCEEDED **` / `** BUILD FAILED **`; the log path is printed as
`/tmp/cmux-reload-<tag>.log`.

**A full cold build takes ~1h40m**, not the ~10 minutes a failed build suggests.
A build that dies early at the Rust sidecar never reaches the ~9,400-file Swift
phase, so its duration tells you nothing. Do not run two builds concurrently —
separate derived-data dirs keep them correct but they compete for cores.

**`respawn-pane --command` does not respawn on the shipped CLI (0.64.11).**
Its help says "Send a command ... to a surface", and that is literal: the text
arrives as stdin. Measured with `sleep 999` in the foreground — the command
echoed into `sleep`, the PID survived, the tty did not change. `rpc
surface.respawn` returns `method_not_found` there. A real surface replacement
(`controlSurfaceRespawn` -> `Workspace.respawnTerminalSurface`) exists only in
newer sources. This is why `ocmux-refresh` guards on a busy tty: on a shipped
build it would otherwise type the alias straight into a live remote tmux.

**`rpc surface.list` reports only the SELECTED workspace.** It ignored every
`workspace` / `workspace_ref` / `all` parameter tried; 6 of 17 surfaces across 12
workspaces were visible. Enumerate with `rpc system.tree {"all":true}` instead.

**`--surface` resolves inside `$CMUX_WORKSPACE_ID`.** A surface in another
workspace fails with `invalid_params: Surface is not a terminal` even when
addressed by UUID, unless `--workspace` is also passed.

**`ui.newWorkspace.contextMenu` REPLACES the built-in "+" menu**, it does not
extend it (`configuredNewWorkspaceContextMenu ?? defaults`). Omit the built-ins
and you silently delete "New Workspace" from the button.

**cmux rewrites `cmux.json` itself.** It appended a `"terminal"` block between
two runs, so any generator must edit surgically — hence the delimited managed
block — and must not assume it owns the file.

**`newWorkspaceMenu` is inert on 0.64.11** (absent from its `CodingKeys`).
Unknown keys are ignored rather than rejected, so it is harmless to include for
newer builds.
