# Changelog

Public releases of the Lumen design system and Catalog.

## 0.62.0 (2026-10-26)

- Settings windows match macOS System Settings with one unified toolbar row, a full-height sidebar, and accent selection.
- Shared window chrome guarantees consistent native geometry for app-built windows.
- Icon tiles follow the system icon appearance.
- Framed symbols use sizing that preserves their artwork within icon tiles.
- New settings form rows provide labeled text and numeric fields, status, empty states, and trailing actions.

## 0.61.0 (2026-10-24)

- Theme tokens, scoped stores, editable color and depth metrics, validated theme files, and command-line theme exchange.
- Consistent controls, rich text, tables, charts, source lists, inspectors, developer tools, and feedback surfaces.
- Workspace, document, utility, library, welcome, wizard, settings, and menu-bar window compositions with native macOS 27 chrome.
- Shared text scale, density, container-relative corners, window activity, and drawn or glass appearance.
- Layout conformance checks identify clipped text, overlapping content, insufficient margins, and drawing outside native boundaries. Offscreen test hosting preserves the embedding application's activation policy.
- The Catalog demonstrates components and complete sample windows using synthetic data.

## 0.60.0 (2026-10-23)

- Added application text scaling and density-aware control sizing.
- Added themed bar and line charts, histograms computed from observations, legends, and empty states.
- Added utility-window composition with responsive sidebars and inspectors, plus window-structure checks.

## 0.59.0 (2026-10-23)

- Added theme schema 2 with inherited metrics, depth, and configurable locks.
- Added theme editing with undo, contrast fixes, seed generation, DTCG exchange, CSS export, and command-line comparisons.
- Added window-owned toast notifications and searchable keyboard shortcuts.

## 0.58.0 (2026-10-23)

- Raised the minimum deployment target to macOS 27.
- Added complete settings-window composition, native activity handling, and container-relative corners.
- Added configurable native menu image visibility.

## 0.57.0 (2026-10-23)

- Added scoped theme stores, extensible conformance checks, and drawn or glass chrome.
- Improved toolbar sizing, sidebar toggles, and command-palette scrolling.
- Deprecated global color lookup in favor of the current environment or an explicit store.

## 0.56.2 (2026-10-18)

- Improved quiet-button sizing and hex-dump scrolling.
- Improved native split-view sizing on supported systems.

## 0.56.1 (2026-10-17)

- Corrected hidden-region appearance checks and accent derivation naming.

## 0.56.0 (2026-10-16)

- Added an optional maximum height for bottom panels.
- Improved inspector sizing during split-view measurement.
