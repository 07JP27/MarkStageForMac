---
name: MarkdStage for macOS
description: "Markdown, ready for the stage."
colors:
  brand-midnight-ink: "#0B1020"
  brand-stage-navy: "#151B2F"
  brand-spotlight-amber: "#FFB547"
  brand-warm-light: "#FFD77A"
  brand-paper: "#F7F4ED"
  brand-cool-copy: "#C8CEDD"
  renderer-dark-background: "#0E1117"
  renderer-dark-foreground: "#F0F4FA"
  renderer-dark-body: "#C9D2DD"
  renderer-dark-muted: "#8B95A3"
  renderer-dark-accent: "#4EA8FF"
  renderer-dark-accent-strong: "#79C0FF"
  renderer-dark-surface: "#161B22"
  renderer-dark-code: "#1B2330"
  renderer-dark-border: "#2A313C"
  renderer-light-background: "#FFFFFF"
  renderer-light-foreground: "#15181F"
  renderer-light-body: "#333A44"
  renderer-light-muted: "#5B6470"
  renderer-light-accent: "#4F46E5"
  renderer-light-accent-strong: "#4338CA"
  renderer-light-code: "#F3F4F6"
  renderer-light-border: "#E5E7EB"
  renderer-microsoft-foreground: "#201F1E"
  renderer-microsoft-body: "#323130"
  renderer-microsoft-muted: "#605E5C"
  renderer-microsoft-accent: "#0078D4"
  renderer-microsoft-accent-strong: "#106EBE"
  renderer-microsoft-code: "#F3F2F1"
  renderer-microsoft-border: "#E1DFDD"
  renderer-error: "#D13438"
  renderer-warning: "#B26A00"
typography:
  display:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif'
    fontSize: "34px"
    fontWeight: 700
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'
    fontSize: "14px"
    fontWeight: 400
  file-label:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'
    fontSize: "13px"
    fontWeight: 500
  error:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'
    fontSize: "12px"
    fontWeight: 500
  counter:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'
    fontSize: "13px"
    fontWeight: 600
    fontFeature: "tabular-nums"
  status:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'
    fontSize: "11px"
    fontWeight: 400
  pane-label:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'
    fontSize: "10px"
    fontWeight: 600
  slide-heading:
    fontFamily: 'var(--ms-font, "Segoe UI Variable Text", "Segoe UI", "Hiragino Kaku Gothic ProN", "Yu Gothic UI", system-ui, sans-serif)'
    fontSize: "clamp(32px, 6.6vh, 72px)"
    fontWeight: 700
    lineHeight: 1.08
    letterSpacing: "-0.01em"
  slide-body:
    fontFamily: 'var(--ms-font, "Segoe UI Variable Text", "Segoe UI", "Hiragino Kaku Gothic ProN", "Yu Gothic UI", system-ui, sans-serif)'
    fontSize: "clamp(18px, 3vh, 30px)"
    lineHeight: 1.55
  slide-code:
    fontFamily: '"Cascadia Code", "Cascadia Mono", Consolas, monospace'
    fontSize: "clamp(14px, 2.1vh, 22px)"
    lineHeight: 1.5
rounded:
  inline-code: "5px"
  renderer-control: "7px"
  pane: "8px"
  media: "10px"
  overlay: "14px"
  pill: "999px"
spacing:
  control-gap: "8px"
  pane-content: "10px"
  rail-inset: "12px"
  preview-inset: "16px"
  window-edge: "20px"
  empty-copy-gap: "24px"
  empty-edge: "48px"
---

# Design System: MarkdStage for macOS

## Overview

**Creative North Star: "The Quiet Control Booth"**

MarkdStage preserves the upstream renderer as the visual authority for every presentation and wraps it in a compact, native macOS operator shell. The shell should feel like backstage equipment: calm, exact, and immediately legible under presentation pressure. It uses AppKit structure and system appearance rather than restyling the deck or imitating a web dashboard.

The Markdown `#` under a stage spotlight remains the product's signature. Its Midnight Ink, Paper, and Spotlight Amber world appears in the empty state, where the product needs an identity before an author's work is present. Once a deck is loaded, semantic macOS chrome recedes and the current slide dominates.

**Key Characteristics:**

- Native AppKit chrome around a fixed-ratio presentation canvas
- One large current slide with a narrower next-slide and notes rail
- Strong branding only before a deck is loaded
- Compact, stateful controls that remain usable during a talk
- Strict separation between host chrome and author-controlled deck themes
- Matching renderer output in operator preview, audience view, and PDF

## Colors

The product has two color authorities: fixed brand colors for the no-deck moment, and role-based renderer palettes for deck content. Routine macOS chrome is deliberately absent from the static token list because it uses dynamic AppKit colors.

### Primary

- **Spotlight Amber** (`colors.brand-spotlight-amber`) is the scarce brand action color: the empty-state Open action, spotlight, and branded renderer placeholder.
- **Warm Light** (`colors.brand-warm-light`) is the illuminated edge and oversized Markdown mark. It supports Spotlight Amber; it is not a second routine action color.

### Neutral

- **Midnight Ink** (`colors.brand-midnight-ink`) is the branded empty-state field.
- **Stage Navy** (`colors.brand-stage-navy`) supports the branded web placeholder and its empty navigation surface; it does not replace the loaded operator window's semantic system surfaces.
- **Paper** (`colors.brand-paper`) carries the empty-state promise and illuminated mark.
- **Cool Copy** (`colors.brand-cool-copy`) carries supporting brand copy.
- The loaded native shell uses `windowBackgroundColor`, `controlBackgroundColor`, `separatorColor`, `labelColor`, and `secondaryLabelColor`. Errors use `systemRed`, including a low-opacity red error-bar field.

### Renderer palettes

The bundled renderer exposes the same semantic roles in three built-in families:

| Family | Core tokens | Character |
| --- | --- | --- |
| Default / dark | `renderer-dark-background`, `renderer-dark-foreground`, `renderer-dark-body`, `renderer-dark-muted`, `renderer-dark-accent`, `renderer-dark-accent-strong`, `renderer-dark-surface`, `renderer-dark-code`, `renderer-dark-border` | Carbon-black stage with blue-to-violet energy |
| Light | `renderer-light-background`, `renderer-light-foreground`, `renderer-light-body`, `renderer-light-muted`, `renderer-light-accent`, `renderer-light-accent-strong`, `renderer-light-code`, `renderer-light-border` | White paper with an indigo accent |
| Microsoft | `renderer-light-background`, `renderer-microsoft-foreground`, `renderer-microsoft-body`, `renderer-microsoft-muted`, `renderer-microsoft-accent`, `renderer-microsoft-accent-strong`, `renderer-microsoft-code`, `renderer-microsoft-border` | Fluent neutral field, Microsoft blue, and the four-color top rule |

Renderer errors and non-fatal routing warnings use `renderer-error` and `renderer-warning` respectively, always with text, borders, or status messaging in addition to color. Syntax highlighting has theme-specific semantic colors in the renderer stylesheet and should remain there rather than becoming shell colors.

**The Chrome–Canvas Boundary Rule.** Use AppKit semantic colors for loaded application chrome and the selected renderer theme inside slides. Never borrow a deck accent for native shell controls.

**The Rare Amber Rule.** Spotlight Amber belongs to branded empty and opening moments, not every selected, enabled, or primary-looking control.

## Typography

The shell uses San Francisco through AppKit system fonts. It does not bundle or force a display face. The empty-state promise uses `typography.display`; body copy and speaker notes use `typography.body`; file, error, counter, status, and pane-caption roles use their corresponding frontmatter tokens. The counter uses tabular numerals. Native buttons and menus keep AppKit's own metrics.

Pane captions are short, uppercase strings such as “NEXT SLIDE” and “SPEAKER NOTES.” Hierarchy comes from compact size, semibold weight, and secondary-label color rather than decorative tracking. Paths and filenames truncate in the middle; transient status text does the same when space is constrained.

Deck typography is separate. The bundled defaults use `typography.slide-heading`, `typography.slide-body`, and `typography.slide-code`, with responsive clamps tied to viewport height. Second- and third-level headings step down from that scale; kickers are bold uppercase labels with a small gradient mark. A selected or custom theme may replace the renderer font through `--ms-font`.

**The Native Outside, Theme Inside Rule.** Use system type for every macOS control, status, sheet, and empty-state label. Preserve renderer typography and theme overrides inside the 16:9 canvas.

## Layout

The operator window opens at 1280 × 800 pt, cannot shrink below 960 × 640 pt, and uses a full-size content view beneath a transparent titlebar. Its vertical structure is fixed-height header (58 pt), optional error bar (32 pt), flexible content, and fixed-height footer (54 pt).

- **Header:** The filename sits at the leading edge with a 20 pt inset. Open, Slide List, Start/End Presentation, and Export PDF form a trailing command row with 8 pt gaps and a 16 pt trailing inset. Both groups sit 8 pt below the titlebar's geometric center.
- **Content:** A vertical `NSSplitView` holds the current-slide pane and the supporting rail. The divider position persists as `MarkdStageOperatorSplit`; its initial position is 850 pt. The current pane has a 560 pt minimum width. The rail has a 320 pt minimum width and resists compression.
- **Current slide:** The slide sits inside `spacing.preview-inset` on all sides. `AspectRatioView` fits a centered 16:9 rectangle and uses black letterboxing for remaining space.
- **Supporting rail:** `spacing.rail-inset` surrounds two equally tall panes separated by the same inset. The upper pane holds the next 16:9 preview; the lower pane holds scrolling speaker notes.
- **Footer:** Previous, a centered page counter, and Next occupy the visual center with 18 pt gaps. Live-reload, loading, update, export, and error status sits independently at the leading edge with an 18 pt inset.

The native shell has no alternate compact reflow below its minimum size; users resize the persistent split instead. The bundled web presenter view is separate and switches from a two-column preview/sidebar grid to one scrollable column at 800 CSS px.

The audience window opens on the first non-main display when available, otherwise on the main display. Its initial 16:9 frame is centered at 88% of the display's visible bounds and capped at 1280 × 720 pt. The window cannot shrink below 640 × 360 pt but remains freely resizable after opening. Native macOS full screen expands the audience view; no custom full-screen shell is added.

The renderer itself is one viewport-sized slide with no page scrolling. Standard deck padding scales between 30–68 px vertically and 40–104 px horizontally. Only content explicitly marked as overflowing becomes internally scrollable. PDF mode fixes each page to 13.333333 × 7.5 in (1280 × 720 CSS px) and removes navigation, animations, and editing controls.

## Elevation & Depth

The native operator shell is flat and tonal. The header uses the active AppKit header material, the footer uses menu material, and panes use semantic control backgrounds with a one-point semantic separator border. There are no custom shadows on loaded shell controls or panes.

The empty state creates depth with a translucent triangular amber spotlight rather than elevation. The bundled branded placeholder adds an angled light field and an offset shadow behind its large `#`, but this treatment does not continue into the loaded operator chrome.

Renderer shadows are restrained and functional:

- Code blocks: `0 2px 10px rgba(0,0,0,.06)`
- Tables: `0 1px 6px rgba(0,0,0,.05)`
- Images: `0 4px 16px rgba(0,0,0,.1)`
- Audience navigation: `0 6px 22px rgba(0,0,0,.22)`
- Presenter frames: `0 6px 24px rgba(0,0,0,.24)`
- Modal overview panel: `0 18px 60px rgba(0,0,0,.4)` over a dimmed, 2 px blurred backdrop

**The Flat Control Booth Rule.** In the macOS shell, use material, tone, and separators before shadow. Reserve stronger elevation for renderer overlays that must sit above a slide.

## Shapes

The dominant geometry is the 16:9 stage rectangle. Native pane shells use gently rounded corners (`rounded.pane`) and a thin border. Buttons use AppKit's rounded bezel and control sizes; their radius is system-owned and must not be replaced with a guessed fixed value.

The renderer uses a compact radius vocabulary: inline code uses `rounded.inline-code`, presenter buttons use `rounded.renderer-control`, common blocks and media use `rounded.pane` or `rounded.media`, overview panels use `rounded.overlay`, and navigation/counter capsules use `rounded.pill`. Cover backgrounds and author-supplied logos remain edge-to-edge and square.

SF Symbols are the native icon language. The oversized `#`, the spotlight wedge, and the renderer's short gradient top rule are the only recurring brand geometries.

## Components

### Operator header

The command row contains four native rounded buttons with leading SF Symbols: Open, Slide List, Start Presentation, and Export PDF. Open is always available. The other three are disabled until a deck exists. While an audience window is open, Start Presentation becomes End Presentation and swaps the play-rectangle symbol for a stop-rectangle symbol; its accessibility label changes with it.

The leading filename is medium-weight secondary text and truncates through the middle. The window title also changes to “[filename] — MarkdStage,” but remains visually hidden in the transparent titlebar.

### Current preview and supporting rail

The current-slide pane is intentionally unlabeled and receives the largest area. Supporting panes use compact captions above their content. Speaker notes are read-only but selectable, scroll vertically, and use ordinary label color when present. Empty notes read “No speaker notes” in secondary color. On the final slide, the next preview is hidden and replaced by centered secondary text reading “There is no next slide.”

### Footer navigation and status

Previous and Next are native rounded, labeled buttons with chevrons. Previous is disabled on the first slide; Next is disabled on the last. The counter reads “[current] / [total]” and uses tabular numerals. Before a deck is loaded it reads “0 / 0.”

The status line reports the current operation without blocking the operator: opening prompt, loading filename, live reload on or unavailable, update from disk, PDF preparation, saved filename, or load failure. It stays left-aligned while navigation stays centered.

### Empty state

With no rendered slides, the current pane becomes the strongly branded surface. A two-line promise and supporting sentence are left aligned with `spacing.empty-edge`; the stack uses `spacing.preview-inset`, then a 24 pt break before the large Open Markdown button. The button is a large native rounded control, tinted Spotlight Amber, and is the Return-key default.

An oversized, black-weight Warm Light `#` occupies roughly the rightmost 30% while a translucent spotlight cuts diagonally behind it. Maintain at least 24 pt between the copy and the mark. The header, footer, zero counter, and disabled deck actions remain visible around this state.

### Errors, sheets, and progress

A deck load error reveals a 32 pt bar directly under the header, with a low-opacity system-red background and medium system-red text. If a previous deck rendered successfully, it remains visible and the message says so. The footer simultaneously names the failed file.

Slide List is a native alert sheet containing a 440 × 30 pt pop-up and Go to Slide / Cancel actions. Open and Export PDF use native open/save sheets. PDF failures use a warning alert sheet titled “Couldn’t save the PDF.” Starting another export while one is active produces the system alert sound rather than another panel.

### Audience window and renderer controls

The audience window is a titled, closable, resizable, miniaturizable native window whose content is entirely the renderer. In presentation mode, its pill navigation is fully transparent at rest and becomes visible on hover or keyboard focus. Actions irrelevant to an audience window—presenter view, presentation launch, export, import, and source mode—are hidden. Operator preview web views hide renderer navigation and overview controls completely.

The audience window supports native full screen from the View menu. Closing it returns the operator button to Start Presentation. Audience controls never overlay the exported PDF.

### Renderer slide primitives

Every slide fills its canvas. A 6 px theme top rule anchors standard slides; title slides center their content and use a dedicated cover background; section slides center a left-aligned heading block over a diagonal theme field; back covers center white content on the theme's back-cover color. Footers remain pinned to the lower deck padding on centered layouts.

Headings, body, code, tables, blockquotes, images, Mermaid, and architecture diagrams use renderer theme roles rather than shell tokens. Code blocks add an accent-side rule, tables tint their header row, and images are centered and capped by viewport height. Theme cover and back-cover assets are shown only when explicitly supplied.

### Accessibility contract

- Native command buttons provide explicit accessibility labels, and each SF Symbol has a matching accessibility description. The presentation label updates with its state.
- Menus expose Open (⌘O), Export PDF (⇧⌘E), Slide List (⌘L), Start/End Presentation (⌘Return), audience full screen (⌃⌘F), arrow-key navigation, and Command-arrow first/last navigation.
- Keyboard slide-navigation menu items validate as unavailable while a sheet is attached or a text view owns focus, preventing accidental advancement while choosing a file or selecting notes.
- Renderer navigation, dialogs, presenter regions, counters, and statuses have accessible names or polite live regions. Overview/import surfaces are modal dialogs, and speaker notes are keyboard-focusable.
- Renderer controls use a visible 2 px theme-accent focus outline. Hover-revealed audience controls also reveal on focus.
- `prefers-reduced-motion: reduce` removes the deck entrance animation and navigation opacity transition. Forced-colors mode maps slides to Canvas, CanvasText, Highlight, and LinkText rather than preserving decorative theme colors.
- Color is never the sole error or state signal: controls also change label, icon, enabled state, border, or status text.

## Do's and Don'ts

### Do:

- **Do** keep loaded chrome native: AppKit controls, SF Symbols, semantic colors, header/menu materials, and system sheets.
- **Do** preserve the current-slide-first split, 16:9 fitting, 560 pt current-pane minimum, and 320 pt supporting-rail minimum.
- **Do** keep status visible at the footer's leading edge and navigation stable at its center.
- **Do** retain the last successfully rendered deck when a refresh fails and expose the failure in both the error bar and status line.
- **Do** preserve keyboard access, dynamic accessibility labels, focus visibility, forced-colors behavior, and reduced-motion behavior.
- **Do** treat renderer themes and custom theme assets as author content across preview, audience, and PDF.

### Don't:

- **Don't** spread Spotlight Amber across routine loaded controls, selection, or deck content.
- **Don't** recolor, retype, brand, or otherwise normalize an author's slides from the macOS shell.
- **Don't** replace the split view, native titlebar, menus, alerts, or full-screen behavior with web-shaped custom chrome.
- **Don't** make audience controls permanently visible; their rest state recedes, but hover and keyboard focus must reveal them.
- **Don't** add arbitrary shadows to native panes or buttons.
- **Don't** invent a compact shell reflow below the implemented minimum window size.
- **Don't** surface renderer-only editing controls as part of the macOS operator shell.
