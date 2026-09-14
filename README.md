# UsageBar

A macOS menu bar app that shows how much of your Claude Code and Codex usage limits you have burned. Click the icon, see every window with a percentage and a reset time.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img src="docs/screenshot-light.png" width="320" alt="UsageBar popover showing Claude Code and Codex usage">
</picture>

## Install

The install script is the fastest option:

```bash
curl -fsSL https://raw.githubusercontent.com/sergeykuzmich/UsageBar/main/install.sh | bash
```

It installs to `/Applications` (or `~/Applications` if that is not writable) and launches. Browser users can instead download `UsageBar.dmg` from the [latest release](https://github.com/sergeykuzmich/UsageBar/releases/latest), open it, and copy `UsageBar.app` to Applications normally. Published releases are signed with Developer ID and notarized by Apple.

UsageBar requires macOS 14 or newer on Apple silicon, plus whichever CLIs you want to see, signed in on that machine. macOS asks once for keychain access the first time it reads Claude's token; click **Always Allow**.

## Updating

UsageBar checks for a new release every 6 hours and offers **⋯ → Update to vX.Y.Z**, which swaps the app and relaunches it. Nothing else to do.

Re-running the install command also works and is the way to get onto a build new enough to have the updater.

To remove it, quit the app and delete `UsageBar.app`.

## What it shows

Both CLIs are enabled and probed independently by default. Under **⋯ → Providers**, disable either Claude Code or Codex to stop probing and hide it from the popover; at least one stays enabled. Whichever enabled providers answer get a section, and the popover explains why an enabled provider is unavailable.

- **Claude Code** — the 5-hour and weekly windows of your Claude.ai subscription.
- **Codex** — whichever windows your ChatGPT plan reports. Paid plans have a 5-hour and a weekly window; free accounts have a single monthly one.

Usage refreshes every 5 minutes and whenever you press refresh.

Under **⋯ → Show in Menu Bar**, pick whether the menu bar number tracks Claude Code, Codex, or whichever of the two is highest. A single number always reports the long window — weekly, or monthly on a free Codex plan — so it never changes meaning under you. To see the short window too, pin one provider and turn on **Show Both Windows**, which reads `11 / 24`: short window, then long. A provider with only one window just shows `24`. When either is spent the whole label turns red. Both choices are remembered across restarts.

## How it reads the numbers

- **Codex** exposes usage over its app-server protocol. UsageBar runs `codex app-server` and calls `account/rateLimits/read`.
- **Claude Code** has no non-interactive usage command, so UsageBar does what the `/usage` screen does: it reads the OAuth token Claude Code already stored in your keychain and calls `GET /api/oauth/usage`. The token is only ever sent to `api.anthropic.com`, and it is never written back or refreshed. If it has expired, run `claude` once and it refreshes itself.

That endpoint rate-limits, and Claude Code itself mostly avoids it: it reads live limits off the `anthropic-ratelimit-unified-*` headers of API calls it is already making, and only fetches `/api/oauth/usage` for the `/usage` screen behind a cache. UsageBar has no API traffic to piggyback on, so it fetches — at most once every 5 minutes per provider, retrying on a 429 and falling back to the last reading (for up to an hour) rather than blanking out. Readings are cached to disk so a relaunch does not trigger a fetch.

Nothing is uploaded anywhere else, and there is no config file.

## Build from source

```bash
make install
```

This builds an arm64 release app, installs it in `/Applications`, and launches it. Run `make help` to see the other development commands for testing, linting, formatting, and building. Local `make build` app bundles are ad-hoc signed; Developer ID signing and Apple notarization happen only in the published-release workflow.

`./.build/release/usagebar --render-preview <dir>` writes PNGs of the popover in light and dark, with live and fixture data. That is how the screenshots above are made, and it is the only way to check the UI on a machine without Screen Recording permission.

## License

MIT
