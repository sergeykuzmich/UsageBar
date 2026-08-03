# UsageBar

A macOS menu bar app that shows how much of your Claude Code and Codex usage limits you have burned. Click the icon, see every window with a percentage and a reset time.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img src="docs/screenshot-light.png" width="320" alt="UsageBar popover showing Claude Code and Codex usage">
</picture>

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lucas-barake/usagebar/main/install.sh | bash
```

Run that on any Mac you want it on. It installs to `/Applications` (or `~/Applications` if that is not writable), launches, and works on both Apple silicon and Intel. Requires macOS 14 or newer, plus whichever CLIs you want to see, signed in on that machine.

macOS asks once for keychain access the first time it reads Claude's token. Click **Always Allow**.

**Use the script, not the browser.** The app is ad-hoc signed and not notarized, so `spctl` rejects it. The script works because `curl` does not attach a quarantine flag, and Gatekeeper only blocks quarantined apps. If you download `UsageBar.zip` from the releases page in a browser instead, macOS will refuse to open it, and you would have to clear the flag by hand:

```bash
xattr -dr com.apple.quarantine /Applications/UsageBar.app
```

## Updating

UsageBar checks for a new release every 6 hours and offers **⋯ → Update to vX.Y.Z**, which swaps the app and relaunches it. Nothing else to do.

Re-running the install command also works and is the way to get onto a build new enough to have the updater.

To remove it, quit the app and delete `UsageBar.app`.

## What it shows

Both CLIs are probed independently. Whichever ones answer get a section; if neither answers, the popover says why for each.

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
./scripts/install-app.sh
```

`./.build/release/usagebar --render-preview <dir>` writes PNGs of the popover in light and dark, with live and fixture data. That is how the screenshots above are made, and it is the only way to check the UI on a machine without Screen Recording permission.

## License

MIT
