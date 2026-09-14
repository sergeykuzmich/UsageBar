# AGENTS.md

Repository-wide guidance for coding agents working on UsageBar.

## Stack and platform

- UsageBar is a macOS 14+ menu-bar application built with Swift 6 and Swift Package Manager.
- The UI uses SwiftUI with AppKit where macOS-specific APIs are needed.
- `make build` produces an Apple-silicon (`arm64`) application bundle at `dist/UsageBar.app` and ad-hoc signs it.
- The package has no third-party Swift dependencies. Prefer platform APIs and the standard library before adding one.

## Repository layout

- `Sources/UsageBarCore/` contains models, Claude and Codex probes, caching and rate-limit behavior, menu-bar presentation helpers, shell integration, and update metadata.
- `Sources/UsageBarApp/` contains the application entry point, popover UI, login-item integration, preview renderer, and updater UI.
- `Tests/UsageBarCoreTests/` contains the Swift Testing suites for core behavior.
- `Support/Info.plist` contains bundle metadata. The Makefile copies it into the built app and may replace version fields during a build.
- `.github/workflows/` contains pull-request validation and the reusable application build workflow.
- `.build/` and `dist/` are generated outputs; do not edit or commit them.

## Development commands

Use the Makefile as the canonical interface:

- `make help` — list available commands.
- `make test` — run `swift test`.
- `make lint` — build while treating Swift compiler warnings as errors.
- `make format-check` — run strict recursive `swift format` checks over `Sources`, `Tests`, and `Package.swift`.
- `make format` — apply `swift format` to those paths.
- `make build` — build the arm64 release binary, assemble `dist/UsageBar.app`, copy bundle metadata, and ad-hoc sign it.
- `make install` — build, replace `/Applications/UsageBar.app`, and launch it. Do not run this unless installation is explicitly required.

For a focused test during development, use `swift test --filter <test-name>` before running the full suite.

After `make build`, render popover previews with:

```bash
./.build/release/usagebar --render-preview <output-directory>
```

This writes light and dark PNGs and is the preferred visual check when Screen Recording permission is unavailable.

## Implementation conventions

- Follow the existing Swift 6 concurrency model. Preserve `@MainActor` ownership of observable UI state and move blocking work off the main actor.
- Keep provider-specific transport and parsing in `ClaudeProbe.swift` and `CodexProbe.swift`. Keep shared refresh, cache, and provider-selection policy in `UsageStore.swift`.
- Preserve these safeguards unless the task explicitly changes them: a five-minute fetch floor, a one-hour stale-reading fallback, persisted server-directed backoff, independent provider enablement, and at least one enabled provider.
- Claude credentials normally come from the user's Keychain, with `~/.claude/.credentials.json` as a fallback. Never log, persist, refresh, or send the OAuth token anywhere except `api.anthropic.com`. Codex usage must continue through `codex app-server`.
- Add or update focused tests in `Tests/UsageBarCoreTests/` for core behavior. Use preview rendering to inspect visual changes.
- Match existing naming and file boundaries. Avoid speculative abstractions and new dependencies.
- Use `make format`; do not manually fight the repository's `swift format` output.

## CI/CD

Pull requests run `.github/workflows/pr-check.yml` on `macos-latest`:

1. `make test`
2. `make lint`
3. `make format-check`
4. the reusable `.github/workflows/build.yml` workflow

The reusable build workflow creates the arm64 app, packages it as `dist/UsageBar.dmg` with `hdiutil`, and uploads a seven-day artifact. New commits cancel obsolete runs for the same pull request. For same-repository pull requests not opened by Dependabot, the PR workflow creates or updates one marker-based comment linking to the latest run's artifacts.

Dependabot checks GitHub Actions dependencies monthly. The release workflow invokes the reusable build workflow with Developer ID signing and Apple notarization enabled, then attaches `UsageBar.dmg` to each published GitHub release.

## Validation

- Swift behavior changes: run the smallest relevant test first, then `make test`, `make lint`, and `make format-check`.
- UI changes: complete the Swift checks and inspect generated previews.
- Packaging or bundle changes: complete the Swift checks, run `make build`, and inspect `dist/UsageBar.app`.
- Documentation-only changes: verify commands, paths, and workflow descriptions against the checked-in files; a build is not required.
- Before finishing any change, run `git diff --check` and review the complete diff for unrelated edits or generated files.
