# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClipSave is a macOS menu-bar clipboard manager (`LSUIElement`, no Dock icon, no main window). It lives in an `NSStatusItem`/`MenuBarExtra` popover, plus a separate floating `NSPanel` summoned by a global hotkey. Distributed outside the App Store via Sparkle auto-update; not sandboxed (`ENABLE_APP_SANDBOX = NO`).

## Build, test, run

This is an Xcode project (`ClipSave.xcodeproj`), not SPM — build via `xcodebuild` or Xcode, not `swift build`.

```bash
# Build
xcodebuild -project ClipSave.xcodeproj -scheme ClipSave -configuration Debug build

# Run all tests (Swift Testing framework, target: ClipSaveTests)
xcodebuild -project ClipSave.xcodeproj -scheme ClipSave -configuration Debug test

# Run a single test / suite (XCTestIdentifier form: Suite/testMethod())
xcodebuild -project ClipSave.xcodeproj -scheme ClipSave -configuration Debug \
  test -only-testing:ClipSaveTests/ColorDetectionTests

# Release build + notarize + Sparkle-sign (interactive; needs Developer ID cert,
# notarytool keychain profile "AC_PASSWORD", and the Sparkle private key in Keychain)
./release.sh <version>   # e.g. ./release.sh 3.7
```

The app only runs meaningfully as a GUI process — there is no headless mode. `ClipSaveUITestsLaunchTests` is the stock Xcode template test and isn't meaningful for this app (no real window to launch into); it's occasionally flaky in CI-less environments for unrelated reasons (interference from other menu-bar/update-service processes).

`DEVELOPMENT_TEAM = 6U39FF46MG`, bundle ID `som.ClipSave`. `MACOSX_DEPLOYMENT_TARGET` is pinned high (26.4) in the project but `RECOMMENDED_MACOSX_DEPLOYMENT_TARGET` is 14.0 — the app doesn't actually require the newer OS, that's just an unadjusted Xcode default.

## Architecture

### The one file to know: `ContentView.swift` (~1900 lines)

This single file contains most of the app's core, in this order:

- `AppSettings` — the `UserDefaults`-backed settings store (`ObservableObject`, `.shared`)
- `PanelRouter` — lets a global hotkey tell the panel which tab to open on
- `AutoPaste` — tracks the previously-frontmost app and simulates ⌘V into it
- `ClipContent` / `Clip` — the data model (text, richText, image, file), `nonisolated` (see below)
- `ClipboardManager` — the clipboard-polling engine and clip store (`ObservableObject`, `.shared`)
- `ContentView` — the actual popover/panel UI
- `TabBtn`, `ClipRow`, `ImagePreview` — row-level UI
- `SettingsView` — the full Settings window (General / Content / Advanced / Shortcuts tabs)
- `VisualEffect` — the `NSVisualEffectView` background wrapper

Everything else in the repo is a feature carved out into its own file that plugs into `ContentView`/`ClipboardManager`: `ClipFilter`, `ColorDetection`, `TextTransform`, `ThumbnailCache`, `QuickLookOverlay`, `EmptyStateView`, `TempHistoryStore`, `DesktopScreenshotWatcher`, `KeyCombo`, `PanelShortcuts`, `HotKeyCenter`, `LoginItem`. When fixing a bug, check whether it belongs in one of these smaller files before diving into `ContentView.swift`.

### No dependency injection — everything is `.shared`

There's no DI container. Cross-cutting state is a plain singleton, constructed once and read everywhere: `AppSettings.shared`, `ClipboardManager.shared`, `HotKeyCenter.shared`, `TempHistoryStore.shared`, `ThumbnailCache.shared`, `PanelRouter.shared`, `AutoPaste.shared`, `UpdaterModel.shared`.

**Do not route through `AppDelegate.shared`** to reach app state (e.g. `AppDelegate.shared?.manager`). That reference has proven unreliable under `@NSApplicationDelegateAdaptor` — SwiftUI can reconstruct the adaptor's backing instance, and code that captured a stale reference silently no-ops. Reach `ClipboardManager`, hotkeys, etc. via their own `.shared`, not through the delegate. `AppDelegate.shared` exists only for delegate-specific things (the hotkey panel, Dock/foreground lifecycle, Sparkle's `updaterController`).

### Actor isolation: value types must stay `nonisolated`

The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type is `@MainActor` by default — including plain value types. Left alone, that gives `Codable`/`Equatable`/`Hashable` conformances on data types a main-actor-isolated implementation, which is unusable from background code (e.g. encoding clips off the main thread in `TempHistoryStore`) and is a hard error under the Swift 6 language mode, not just a warning.

Because of this, data-only types (`Clip`, `ClipContent`, `DetectedColor`, `KeyCombo`, `LocalShortcut`, `ClipFilter`, `TextTransform`, `PanelAction`) are explicitly marked `nonisolated`, including their extensions and any hand-written `Codable` methods (the `nonisolated` type modifier does *not* propagate to extensions or to hand-written `init(from:)`/`encode(to:)` — those need it stated again). Keep this pattern for new value types; it's easy to reintroduce the bug by adding an extension without the modifier.

### Global hotkeys go through `HotKeyCenter`, not ad hoc Carbon calls

`HotKeyCenter` (Carbon `RegisterEventHotKey`/`InstallEventHandler`) is the single dispatcher for every global shortcut, keyed by `HotKeyCenter.Action`. One shared Carbon event handler exists; it looks up the fired hotkey's ID and calls the registered closure. (An earlier version installed a separate handler per hotkey, which meant every action fired on every keypress once there was more than one binding — don't reintroduce that shape.)

`RegisterEventHotKey` failing *is* the conflict check (it refuses combinations already claimed by the system or another app) — there's no attempt to enumerate system shortcuts separately. `rebind(_:to:)` unregisters before re-registering (registering a duplicate of your own current binding otherwise looks like a conflict) and rolls back to the previous combo on failure, so a rejected edit never leaves an action unbound.

In-panel shortcuts (arrow keys, Space, Delete, etc.) are a different mechanism: `LocalShortcut` + SwiftUI's `.keyboardShortcut`, configured via `PanelShortcuts.swift`, because those only need to work while the panel has focus and can be bare keys (no ⌘/⌃/⌥ required) — unlike global hotkeys, where a bare key would be swallowed system-wide.

### Screenshot capture is event-driven, not polled

`DesktopScreenshotWatcher` watches for new screenshot files using `DispatchSourceFileSystemObject` on `O_EVTONLY` file descriptors — one `open()` per watched folder for the whole session, not a repeating scan. This is deliberate: reading a TCC-protected folder (e.g. the Desktop) triggers a permission check *per read*, so a naive 1-second polling loop asks for permission every second, and any tick that lands while the consent dialog is already open queues another dialog behind it. Don't reintroduce polling here.

It watches **two** locations at once — whatever `com.apple.screencapture`'s `location` preference points to, plus the Desktop — because macOS doesn't always honor a changed screenshot location immediately, so relying on just the configured folder can silently miss captures. It also recreates a missing configured folder on `start()` (once, at launch/enable — not on every filesystem event, or deleting the folder in Finder would look like the app fighting the user).

Screenshot files are read with a poll-until-size-stable loop before being ingested, not a fixed delay — large captures (multi-MB, common on Retina displays) can still be mid-write when the filesystem event fires.

### Clip identity is a content hash, not object identity

`Clip.contentHash` (SHA-256 of the full content, via `ContentHash`) is computed once at construction and is what de-duplication, thumbnail cache keys, and image sidecar filenames all key off. Do not use byte-count-plus-prefix or any partial-content heuristic for identity — same-size images with similar headers (e.g. two screenshots of the same resolution) can collide on a partial hash, which has been a real bug here before.

### Thumbnails: cache the decode, don't decode in `body`

`ThumbnailCache` decodes images once via ImageIO (`CGImageSourceCreateThumbnailAtIndex`) and caches both the row-sized thumbnail and a separate mid-size hover-preview image, keyed by `contentHash`. SwiftUI view `body` computed properties re-run on every redraw, so calling `NSImage(data:)` directly inside a `View` for an image clip re-decodes the full-resolution bitmap on every frame — go through the cache instead.

### Staying in the menu bar: login item + keep-alive agent

`LoginItem` registers `SMAppService.mainApp` (starts ClipSave at login) and `KeepAlive` registers a bundled launchd agent (`Support/som.ClipSave.keepalive.plist`, copied to `Contents/Library/LaunchAgents/` by the "Install Keep-Alive Agent" copy-files phase). The agent runs a small `/bin/sh` script every 20 s: if ClipSave isn't running and the user didn't choose Quit *this boot*, it reopens `/Applications/ClipSave.app`. The menu's Quit writes `~/Library/Application Support/ClipSave/user-quit` containing the boot time (`kern.boottime` seconds); the file means "stay closed" only while it matches the current boot, so a Quit never survives a restart. Every launch clears it. Launch-at-login defaults to on, once, for copies running from `/Applications` (`enableByDefaultOnce`); a user who turns it off, or disabled it in System Settings, is respected. `applicationDidFinishLaunching` exits immediately if another copy from the same bundle path is already running.

Gotchas: the script's boot-time `sed` must anchor on `{ sec =` — `usec = ` also matches `sec = ` (this was a real bug caught by `KeepAliveTests`). `KeepAliveTests` runs the plist's actual script with `open` stubbed. Registering the agent for real (status `.enabled` vs `.requiresApproval`, the "Background Items" notification) can only be checked on an installed, signed copy — not in unit tests.

### Persistence

- **Permanent clips**: plain JSON at `~/Documents/perm-clips-native.json` (with a one-time migration path from the old sandboxed container location, for installs that predate sandbox removal).
- **Temporary clips**: opt-in (`AppSettings.persistTempClips`, off by default). When enabled, `TempHistoryStore` writes a small JSON index plus image data as separate sidecar files under Application Support, rather than inlining image bytes into the JSON — keeps the index cheap to encode/decode and lets identical images de-dupe on disk for free. Saves are debounced (~600ms) except on quit, which flushes synchronously.
- **Full-disk handling**: all writes are atomic (a failed write leaves the previous file intact), failures are reported through `ClipboardManager.noteSave`, which shows an orange footer warning (`diskWarning`) and retries every 30 s until the save succeeds. Clips keep working from memory meanwhile. Sidecar-image cleanup is skipped after a failed save so the old index never points at deleted files.

## Release process

Distribution is a Developer ID notarized **DMG hosted on Vercel**, not GitHub Releases. The Vercel project serves `site/` (set Root Directory to `site`): `site/index.html` is the landing page, `site/download/ClipSave-X.Y.dmg` the current build, `site/appcast.xml` the update feed.

`release.sh <version>` archives, exports with `developer-id` signing, notarizes + staples the app, builds the DMG, signs/notarizes/staples the DMG, Sparkle-signs it, copies it into `site/download/` (deleting older DMGs), repoints the landing-page download links, and inserts the new `<item>` into **both** feeds. Optional release notes: `release-notes/<version>.html`. `SITE_URL` at the top of the script must be set. It does **not** commit or push; pushing publishes the site and updates every installed copy, so install the DMG yourself first. Because the DMG lives in the same commit as the appcast, there is no "asset before appcast" ordering problem anymore.

Two feeds exist on purpose: builds up to 3.6 have `SUFeedURL` pointing at the root `appcast.xml` on GitHub (`raw.githubusercontent.com`), which can never change for those installs. Keep that file updated with each release (its newest items point at the website DMG); `site/appcast.xml` is the feed for builds from 3.7 on.

A distributed build only receives Sparkle updates if the user actually installs it in `/Applications` (or otherwise off quarantine). An app run in place from a DMG/`~/Downloads` gets Gatekeeper-translocated to a randomized read-only path — Sparkle can detect an update but can't write the replacement, so "Check for Updates" degrades to a dead end. This has bitten real installs; if you're diagnosing "updates don't work," check whether the running binary's path contains `AppTranslocation` before looking anywhere else.
