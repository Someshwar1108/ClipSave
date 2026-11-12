# ClipSave

A clipboard manager that lives in your Mac's menu bar. Free, local, no account.

## Download

**[Download ClipSave for Mac](https://clipsave-mu.vercel.app/download/ClipSave-3.8.dmg)** (v3.8, notarized DMG, macOS 14+)

Open the DMG and drag ClipSave into **Applications**. Run it from Applications so it can update itself. Later versions install from **Check for Updates…** inside the app.

Website: https://clipsave-mu.vercel.app

## Features

- Captures text, rich text, images and files as you copy
- Temporary history plus pinned Permanent clips
- Global hotkey panel, paste-last shortcut, and ⌘1–⌘9 to copy by number
- Filter by Text, Images, Links or Files; search across clips
- Colour detection, text transforms, and image Quick Look
- Optional automatic capture of screenshots
- Opens at login and reopens itself if macOS stops it; Quit keeps it closed


## Build from source

```bash
xcodebuild -project ClipSave.xcodeproj -scheme ClipSave -configuration Debug build
```

## Releasing

`./release.sh <version>` builds, notarizes and publishes a new DMG into `site/` (served by Vercel). See [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE)
