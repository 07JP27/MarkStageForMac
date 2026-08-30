<p align="center">
  <img src="assets/brand/markdstage-banner.svg" width="720" alt="MarkdStage — Markdown, ready for the stage.">
</p>

<p align="center">
  <a href=".github/workflows/ci.yml"><img src="https://img.shields.io/badge/CI-macOS-blue?style=flat" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat" alt="GPL-3.0"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat&logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat&logo=apple&logoColor=white" alt="macOS 14+">
</p>

<p align="center">English | <a href="README_ja.md">日本語</a></p>

---

**MarkdStage for macOS** turns a Markdown file into a presentation without changing the source format. It is a native AppKit port of [runceel/markdstage](https://github.com/runceel/markdstage), created with permission from the original project's owner. Build and distribution follow the patterns used by [SkimDown](https://github.com/07JP27/SkimDown).

## Highlights

- Open `.md` / `.markdown` from Finder, the Open panel, drag and drop, or a command-line path
- Close the current deck and return to the empty state without quitting the app
- Current slide, next slide, speaker notes, page counter, and slide list in one operator window
- Separate audience window with native macOS full screen and secondary-display placement
- Live reload after atomic or in-place Markdown saves while preserving the current position
- GFM, highlighted code, Mermaid, Architecture DSL, local images, speaker notes, and custom themes
- Built-in `dark`, `light`, and `microsoft` themes from the original renderer
- Local-only tokenized renderer server with CSP, same-origin checks, and canonical asset boundaries
- PDF export through WebKit's native PDF pipeline
- No telemetry and no runtime network dependency

Architecture DSL **rendering** is supported. The Windows Architecture editor and Surface Pen bridge are not available on macOS.

## Install

Download the latest DMG from Releases, open it, and drag **MarkdStage.app** to **Applications**.

CI release builds are ad-hoc signed. If Gatekeeper reports that Apple cannot verify the app, review the source and remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/MarkdStage.app
```

Developer ID signing and notarization are supported for maintainer builds.

## Use

1. Open MarkdStage.
2. Choose **File → Open…** or drag a Markdown deck into the window.
3. Navigate with the controls, Space, Page Up/Down, or Left/Right Arrow.
4. Choose **Presentation → Start or End Presentation** to open the audience window.
5. Move the audience window to the target display and choose **View → Toggle Audience Full Screen**.
6. Choose **File → Close Markdown** or the **Close** button to unload the deck.

Slides are separated by `---`. Optional front matter controls layout and theme:

```markdown
---
layout: title
theme: dark
---
# My talk

---

## Second slide

- Markdown remains the source of truth.

<!-- Speaker notes stay in the operator window. -->
```

See [`samples/demo.md`](samples/demo.md) for a working deck.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open Markdown | `⌘O` |
| Previous / next slide | `←` / `→`, `Page Up` / `Page Down`, `Space` for next |
| First / last slide | `⌘←` / `⌘→` |
| Slide list | `⌘L` |
| Start / end presentation | `⌘Return` |
| Audience full screen | `⌃⌘F` |
| Export PDF | `⇧⌘E` |

## Develop

### Prerequisites

- macOS 14+
- Xcode 16+ with Swift 6; Xcode 26 is used by CI
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Commands

```bash
make build
make test
make run
make run-cli MARKDSTAGE_TARGET=/path/to/deck.md
make launch-check
make cli-launch-check
make release VERSION=0.1.0
make dmg VERSION=0.1.0
make generate
make clean
```

`src/project.yml` is the project source of truth. `make generate` refreshes the committed Xcode project.

### Signing and notarization

Copy `.env.example` to `.env` and set `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, and `DEVELOPER_ID_APPLICATION` (the full certificate name reported by `security find-identity -v -p codesigning`). `.env` is ignored by Git.

```bash
make notarize VERSION=0.1.0
```

Notarization requires Apple Developer Program membership and an appropriate Developer ID signing setup.

## Security

The app binds its presentation server only to `127.0.0.1` on a random port and protects every route with a random per-process token. It rejects non-loopback Host headers and cross-origin POSTs, applies a restrictive Content Security Policy, blocks popups, and serves deck/theme assets only after canonical path containment checks.

The app follows SkimDown's non-sandboxed Hardened Runtime distribution posture so a selected deck can reference sibling and repository-level assets without persistent broad filesystem permissions.

## License

The macOS port is released under [GNU GPL v3.0](LICENSE). The original MarkdStage source and assets retain their MIT notice in [`src/MarkdStage/Resources/LICENSES/MarkdStage-MIT.txt`](src/MarkdStage/Resources/LICENSES/MarkdStage-MIT.txt). See [NOTICE.md](NOTICE.md) and the bundled third-party notices.
