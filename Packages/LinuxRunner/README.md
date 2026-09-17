# PokeIDE — Linux Runner (`PokeIDELinux`)

A Linux testing/rendering path for PokeIDE. It reuses the shared
[`EditorCore`](../EditorCore) package — JS tokenizer, highlight themes,
console/diagnostic models, document model, and the `JSEvaluating` engine
protocol — and renders the IDE's layout with
[SwiftCrossUI](https://github.com/stackotter/swift-cross-ui) (a community
SwiftUI-compatible framework) on its GTK backend.

This is a **testing/CI aid, not a shipping target**. The real product remains
the SwiftUI app in `App/` for macOS and iPadOS.

## Requirements

- Swift **6.2+** (SwiftCrossUI's dependencies require it; the Apple targets
  only need the toolchain bundled with Xcode 16)
- GTK 4 development files: `sudo apt install libgtk-4-dev` (Ubuntu/Debian)
- `node` on `PATH` for script execution (optional — the UI still renders
  without it, but Run and the startup console seeding produce no output)
- A display: `X11`/`Xvfb`/Wayland for interactive runs or screenshots

## Build & run

```bash
cd Packages/LinuxRunner
swift build --product PokeIDELinux
.build/debug/PokeIDELinux            # needs DISPLAY set (e.g. :0 or a Wayland session)
```

Headless screenshot loop (CI-friendly):

```bash
Xvfb :99 -screen 0 1400x900x24 &
DISPLAY=:99 .build/debug/PokeIDELinux &
sleep 5
DISPLAY=:99 import -window root pokeide-linux.png   # ImageMagick
```

Useful env vars:

| Variable | Effect |
|---|---|
| `POKEIDE_SOURCE` | Path to a `.js` file to open instead of `App/Resources/demo.js` |

## What it exercises

- `JSTokenizer` + `ThemePalette` → per-token colored spans with a line-number
  gutter (`HighlightedCodeView`)
- `JSEvaluating` conformance via `NodeEngine` — a `node` subprocess that
  streams stdout→console, stderr→problems, and parses `file:line` diagnostics
- `ScriptDocument`/`ConsoleEntry`/`JSDiagnostic` shared models
- Sidebar, tab bar, toolbar (Run/Stop/Clear), console + problems panel —
  mirroring the SwiftUI layout

## Limitations vs the Apple app

- **Rendering only.** SwiftCrossUI is API-compatible, not pixel-compatible;
  colors/metrics differ slightly from the SwiftUI app.
- **Read-mostly editor.** The highlighted view is display-only; a plain
  `TextEditor` is available via the Edit toggle, but there's no gutter,
  no real-time re-highlight, and no auto-indent.
- **Runtime differs.** Apple targets use JavaScriptCore (`JSContext`);
  the Linux runner uses `node`. Console formatting and error text differ
  (e.g. JSC's `=> value` result line isn't emitted by node).
- **No file dialogs / workspace tree** — the sidebar lists open documents
  only; no import/export.
- **Stop semantics differ in a good way:** SIGTERM kills runaway scripts
  on Linux, whereas JavaScriptCore can't interrupt `while(true)` loops.
- GtkBackend needs a real display; under `Xvfb` it works headlessly.

## Why this approach

1. **Native SwiftUI on Linux:** not feasible — Apple doesn't ship it.
2. **Tokamak:** WASM/DOM-targeted; heavier to wire for desktop snapshots.
3. **SwiftCrossUI (chosen):** real GTK windows, real input handling, shares
   `EditorCore` unchanged, runs on `Xvfb` for CI screenshots.
4. **C harness fallback:** considered but unnecessary — SwiftCrossUI
   rendered successfully on the first integration pass.
