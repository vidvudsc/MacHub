# MacHub

MacHub is a native macOS utility dashboard built with SwiftUI. It combines live system monitoring, cleanup review, storage browsing, battery diagnostics, menu bar status, and quick window arrangement tools in one compact app.

## Features

- Live CPU, RAM, disk, network, and battery readings with compact sparklines.
- Menu bar panel with fast system snapshots, power flow, top power app estimate, and dashboard actions.
- Cleaner view for reviewing caches, logs, derived data, downloads, and Trash before opening or removing them.
- Storage explorer for scanning common folders and drilling into large items.
- Battery view with charge history, time remaining, watts in/out, health, cycles, voltage, current, and temperature.
- Window tools for resizing the frontmost app, including editable global shortcuts.
- Dock/menu bar behavior: the Dock icon is visible while the dashboard is open and hidden when the app is tucked into the menu bar.

## Requirements

- macOS 14 or later
- Swift 5.9 or later
- Accessibility permission for window arrangement shortcuts
- Full Disk Access for more complete cleanup and storage scans

## Build And Run

Build from the repository root:

```bash
swift build
```

Create and launch the local `.app` bundle:

```bash
script/build_and_run.sh
```

Verify that the app builds and launches:

```bash
script/build_and_run.sh --verify
```

## Notes

MacHub estimates the top power-hungry app from process CPU usage and current battery draw when available. macOS does not expose exact per-app watts through the lightweight APIs used here, so those values are intentionally labeled as estimates.

Reference screenshots copied from `~/Documents/screenshots/machub` are stored in `docs/screenshots/`.
