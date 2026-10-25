# DockPeek

DockPeek brings the Windows 11 taskbar thumbnail preview to macOS. Rest the mouse on a running
app's Dock icon and a panel shows a live thumbnail of each of its windows.

It is a small menu-bar app (no Dock icon of its own) written in Swift with AppKit and ScreenCaptureKit.

## Features

- **Hover previews:** after about 0.35 s on a Dock icon, a blurred panel opens next to it (above a bottom Dock, beside a left or right one) with one card per window: app icon, title and thumbnail.
- **Live thumbnails:** thumbnails refresh about twice a second while the panel is open, and the panel notices windows opening and closing. Nothing runs while it is closed.
- **Click to raise:** clicking a card brings that window to the front and un-minimizes it if needed.
- **Close buttons:** an **x** appears on the hovered card. Middle-click also closes the window.
- **Peek:** rest on a card for about 0.45 s and the screen dims and shows that window at full size in its real position (an approximation of Windows' Aero Peek).
- **List layout:** with many windows, or when the cards would not fit the screen, the panel becomes a vertical list.
- **Minimized badge:** minimized windows are dimmed and labelled.
- **Keyboard control:** while the panel is open, arrow keys move the highlight, Return raises, Delete or Cmd+W closes, Esc dismisses.
- **Launch at Login:** toggle from the menu-bar icon.

## Requirements

- macOS 14 or later, Xcode command line tools (Swift 5.9+)
- **Accessibility** permission: to find which Dock icon is hovered, raise and close windows, and handle keys.
- **Screen Recording** permission: for thumbnails. Without it you get a title list only.

## Build and run

```bash
./build.sh
open DockPeek.app
```

`build.sh` builds the Swift package, assembles `DockPeek.app` and signs it. For macOS to keep the
permissions between builds the app needs a stable signing identity: the script uses a certificate
named `DockPeek Local Signing` if it exists in your login keychain and falls back to an ad-hoc
signature otherwise (macOS then asks for the permissions again after each rebuild).
Copy the app to `/Applications` before enabling **Launch at Login**.

Log file: `~/Library/Logs/DockPeek.log`.

## How it works

| File | Role |
| --- | --- |
| `AppDelegate.swift` | Mouse-move monitoring (event driven, no polling), Dock hit-testing via the Accessibility API, timers, peek and keyboard wiring |
| `WindowInfo.swift` | Lists an app's windows (ScreenCaptureKit, filtered through Accessibility), captures thumbnails, raises and closes windows |
| `PreviewPanel.swift` | The preview panel: cards, list rows, close buttons, selection |
| `PeekOverlay.swift` | Click-through dimming overlay used for peek |
| `KeyboardTap.swift` | Key listener that exists only while the panel is open |
| `tools/make_icon.swift` | Generates the app icon |

## License

MIT, see [LICENSE](LICENSE).
