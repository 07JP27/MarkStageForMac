# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Developers, technical speakers, and documentation authors who write in Markdown and want to preview and deliver the same source as a presentation on macOS.

## Product Purpose

MarkdStage turns Markdown into a presentation that can be previewed, navigated, presented on another display, refreshed when its source changes, and exported without moving content into a proprietary slide format.

## Positioning

MarkdStage keeps Markdown as the source of truth while supporting presentation-focused layouts, highlighted code, Mermaid, Architecture DSL diagrams, local assets, custom themes, and speaker notes through one renderer shared with the original Windows application.

## Operating Context

- The macOS app opens `.md` and `.markdown` decks from Finder, the Open panel, drag and drop, or a command-line path.
- The operator view shows the current slide, next slide, and speaker notes.
- A separate audience window can move to another display and enter native macOS full screen.
- Saved source changes refresh the active presentation without losing its current position.

## Capabilities and Constraints

- Slides use `---` separators and optional front matter.
- Deck files are limited to 2 MiB.
- Local assets and theme assets are served only from canonical, approved roots.
- The app is distributed outside the Mac App Store using Hardened Runtime signing and a DMG.
- The initial macOS release does not include the Windows-only Surface Pen bridge or Architecture DSL editing.

## Brand Commitments

- Product name: **MarkdStage**
- Pronunciation: **marked stage**
- Primary tagline: **Markdown, ready for the stage.**
- The identity combines a Markdown `#` with a stage spotlight.
- Midnight Ink, Paper, and Spotlight Amber belong to app chrome and empty states; deck themes remain author-controlled.

## Evidence on Hand

- The authorized Windows source is maintained at <https://github.com/runceel/markdstage>.
- `samples/demo.md` exercises the bundled renderer.
- No customer claims, usage metrics, or testimonials are available and none should be invented.

## Product Principles

1. Keep Markdown as the source of truth.
2. Make writing-to-presenting immediate.
3. Keep operator, audience, and exported output visually consistent.
4. Use native macOS behavior for app chrome while preserving deck rendering.
5. Never add unsolicited branding to an author's slides.

## Accessibility & Inclusion

Keyboard navigation, semantic slide output, visible focus, readable contrast, reduced-motion support, and native accessibility labels are release requirements.
