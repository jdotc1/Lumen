# Migrating an app with its own design system

Lumen owns shared visual roles, themes, metrics, components and conformance rules. An app owns
its domain roles and workflows. Migration should make that boundary explicit while keeping
users’ saved themes and familiar behavior stable.

## 1. Inventory the boundary

List colors, typography, spacing, window structure and component adapters. Classify each role
by meaning: reusable chrome and interaction roles belong in Lumen; domain concepts such as
listing kinds, evidence states or specialized graph edges belong in an app’s domain pack.
Record saved theme identifiers, serialized token keys, overrides and retired keys before changing
them. Capture the affected workflows and minimum window sizes as the migration’s acceptance criteria.

## 2. Establish a domain pack

Declare domain tokens and surfaces in the app and compose them with Lumen’s shared packs.
Use `Examples/InspectorPack` as an example of a pack with its own roles, themes and checks.
Avoid registering a shared token twice. When a shared pack supplies a role previously owned by
the app, migrate its definition and retain any required theme-key mapping at the app boundary.

## 3. Preserve themes and user choices

Keep existing theme identifiers stable in the migrating app. Preserve original saved theme files
and migrate a copy when the format changes. Translate keys explicitly, record keys with no
successor as retired, and retain user overrides wherever their meaning is unchanged. Compare
resolved colors and metrics for each supported appearance, including contrast variants. An app
can keep self-contained branded themes or inherit shared themes and override domain roles.
The example pack’s identifiers are sample data, not identifiers to copy into a shipping app.

## 4. Move in bounded phases

1. Adopt the token registry, validator and theme store behind existing adapters.
2. Replace shared roles and common controls with Lumen’s public API, keeping domain roles local.
3. Adopt the appropriate window scaffold and replace redundant adapters in one affected workflow
   at a time. Preserve panel state, shortcuts, minimum sizes and theme selection.
4. Remove unused legacy definitions only after their call sites and saved-data compatibility are
   accounted for. Document any remaining adapter’s purpose and removal condition.

At each phase, pin an exact Lumen commit and read the intervening CHANGELOG entries. Follow
[client versioning](clients.md) when reporting a missing shared behavior; Lumen’s plans and
release schedule remain independent of any app’s migration.

## 5. Ratchet the remaining work

Run app-owned `LumenCheck` implementations in the app’s tests. A source-style ratchet can count
remaining direct system styles against an explicit accepted budget. Lower that budget as uses
are replaced; new exceptions require an explanation. The example `InspectorStyleRatchet` shows
this mechanism without reading another checkout. A budget is migration accounting, not proof
that a rendered window behaves correctly.

Validate the changed boundary with theme validation, relevant layout checks and focused workflow
acceptance. Reuse valid evidence for unchanged inputs. Record unresolved behavior separately from
completed migration work, and move the app’s pin only when its affected workflows are ready.
