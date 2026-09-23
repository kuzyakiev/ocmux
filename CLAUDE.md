# ocmux

Oleg's fork of [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux). Personal
tool, not a contribution stream. Work happens on `ocmux/session-refresh`; `main`
tracks upstream so rebases stay cheap.

## Upstream's contributor policy does NOT apply here

The original `CLAUDE.md` (kept at `ocmux-tools/UPSTREAM-CLAUDE.md.orig`) is
manaflow's process for people submitting PRs to cmux. None of it binds this
fork, and following it wastes time. Specifically **ignore**: the Mac mini
fleet / `cmux-ci` / HQ build contract, the localization audit and
`Localizable.xcstrings` requirement, `STYLE.md`, the two-commit regression
ceremony, the dogfood/notify handoff protocol, the PostHog feature-flag policy,
the remote-relay PR review gate, and the `ios/` `web/` `cmux-tui/` area rules.

Read it only when a question is genuinely about how the codebase works.

## Building

```bash
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
export CMUX_DEV_BACKEND_MODE=local          # mandatory, see below
./scripts/reload.sh --tag <tag> --build-only
```

**`reload.sh`'s exit code is meaningless.** Three separate ways it reports
something other than what happened:

| what happens | what it returns |
|---|---|
| `CMUX_DEV_BACKEND_MODE=local` unset → doesn't build at all | **exit 0** |
| build genuinely FAILS | **exit 0** (real status 65 is swallowed) |
| `--launch` without `~/.secrets/cmuxterm-dev.env` | exit 2, no build |

Always confirm by grepping `/tmp/cmux-reload-<tag>.log` for
`** BUILD SUCCEEDED **` / `** BUILD FAILED **`.

**A cold build takes ~2h**, not the ~10 min a *failed* build suggests (a build
that dies early at the Rust sidecar never reaches the ~9,400-file Swift phase).
Reuse the tag's warm DerivedData at
`~/Library/Developer/Xcode/DerivedData/cmux-<tag>`; a different path starts a
cold build. Never run two builds concurrently — it starved this box to load
average 333. For GhosttyKit, `./scripts/download-prebuilt-ghosttykit.sh` then
`CMUX_GHOSTTYKIT_PREPROVISIONED=1` avoids recompiling it.

Never run bare `xcodebuild` or open an untagged `cmux DEV.app` — untagged builds
share the default debug socket and bundle ID.

Prerequisites (all installed): Xcode, Metal toolchain
(`xcodebuild -downloadComponent MetalToolchain`), zig (version pinned by
`ghostty/build.zig.zon`), Rust (`Native/DiffSidecar/rust-toolchain.toml` pins
the channel), go, bun. `./scripts/setup.sh` checks them and fetches GhosttyKit.

## Driving a tagged build

```bash
CMUX_TAG=<tag> scripts/cmux-debug-cli.sh list-workspaces
CMUX_TAG=<tag> scripts/cmux-debug-cli.sh reload-config
```

Targets `/tmp/cmux-debug-<tag>.sock` and scrubs ambient cmux env so it cannot
hit the user's main app. Do **not** use `/tmp/cmux-cli` — it points at the most
recently reloaded build and can target the real app's socket. A tagged app also
refuses outside connections (`only processes started inside cmux can connect`),
so this helper is the way in.

## Tests

A `.swift` file in `cmuxTests/` without a `PBXFileReference` +
`PBXSourcesBuildPhase` entry is **silently skipped**, and `xcodebuild test`
still passes with "Executed 0 tests". Run `./scripts/sync-test-wiring` after
adding or renaming a test file.

Reading test output: the legacy XCTest block reports `Executed 0 tests` even on
success — swift-testing results are in the *second* block (`✔ Test run with N
tests`). Judging by the first block alone looks like a vacuous pass.

## Runtime landmines in this codebase

- **Typing-latency paths**: `WindowTerminalHostView.hitTest()`
  (`TerminalWindowPortal.swift`), `TabItemView` (`ContentView.swift`),
  `TerminalSurface.forceRefresh()` (`GhosttyTerminalView.swift`) run on every
  keystroke.
- **SwiftUI list boundaries**: no view below a `LazyVStack`/`List`/`ForEach`
  may hold an observable store reference, and no function called from `body`
  may write state — either reintroduces a 100% CPU spin loop (upstream #2586).
- **No app-level display link** or manual `ghostty_surface_draw` loop; rely on
  Ghostty's wakeups or typing lags.
- **ghostty submodule**: push the submodule commit to its remote before
  committing the pointer; never commit on a detached HEAD.
- **`surface.respawn` is denied over the `cmux ssh` relay** by design — the
  plain-SSH respawn path falls back to executing locally. Relevant if refresh
  ever needs to work against a remote cmux.

## The session-refresh feature

`ocmux-tools/` holds the shell side (registry, pane self-tagging, refresh,
config generator) and its **README documents the measured landmines** —
`respawn-pane`'s send-stdin behaviour on older CLIs, `surface.list` only
reporting the selected workspace, `ui.newWorkspace.contextMenu` replacing rather
than extending the built-in menu, and cmux rewriting `cmux.json` underneath you.
Read `ocmux-tools/README.md` before touching any of it.

Swift side: `Sources/OcmuxRefresh.swift` (pure target filter + AppDelegate
seam), the titlebar control in `Sources/Update/UpdateTitlebarAccessory.swift`,
and the per-row control in `Sources/ContentView.swift`.
