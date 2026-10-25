# Theme editor

The Colors and Metrics tabs share a window-local editing transaction. Edits preview through the
passed store without persisting its selection. Cancel restores that store; Save selects the saved
theme. Undo and Redo cover color changes, metric changes, resets, and each successful Fix.

Metrics left unspecified inherit from the parent and then the app's metrics. Reset removes the
local declaration. Packs can lock each metric; a locked field cannot be changed or reset. Explicit
metrics save as schema 2. An unchanged color-only v1 file retains its original bytes, and opening
the Metrics tab never writes defaults. Removing the last metric from an explicitly v2 file does
not downgrade its declared schema.

## Fix actions

The validator attaches `LumenThemeFix` metadata to supported `LumenIssue` findings. Existing
initializers remain available. `LumenValidator.fix(_:in:registry:)` returns a repaired copy or
throws `LumenThemeFixError`; failure applies no partial edit.

- Contrast moves the finding's foreground, including custom rules for dimmed labels, disabled
  toolbar items and keycaps. On raised grounds, a substituted foreground targets its raised token.
  The other token stays unchanged. Lightness moves in OKLCH toward the nearest passing value,
  preserving hue and chroma. Chromatic accent-family roles never reduce chroma; other tokens
  may reduce it only if no lightness at the original chroma passes.
  Repairs also have to pass in their saved hex representation.
- Visibility moves the rule's explicitly named adjustable token, such as a selection fill.
- Opacity sets the named foreground's alpha to 1.
- Numeric metrics clamp to their allowed range: type 0.9–1.3, spacing 1–1.25, uniform radius 0–12 pt.
  Locks and nonnumeric values cannot be repaired by clamping. Depth findings remain manual:
  their leaf ranges, radius-dependent offsets and menu/popover ordering require more than the
  current whole-metric clamp target. Existing depth declarations survive editor changes.

Findings refresh immediately after Fix. Increase Contrast edits are saved independently, and a
Fix is one undo operation. Unsupported findings stay visible for manual editing.

## New from seed

`LumenTheme.seeded(accentHue:ground:id:name:in:)` is a public throwing LumenTokens API. Hue uses the
HSV wheel from 0 through 360 degrees, with violet at 260 degrees by default. The two
`LumenSeedGround` preferences pair light and dark palettes:

| Preference | Light ground | Dark ground |
| --- | --- | --- |
| Paper / Graphite | Warm paper canvas, `#FBFAF7` | Standard lifted graphite grounds |
| Bright / Deep | Standard white canvas | Contrast's black canvas and lifted charcoal wells |

Both include the standard theme's light and dark Increase Contrast palettes. Existing system-accent
derivation supplies the role lightness. All chromatic accent roles (including explicit fallback
aliases, selections, focus, links and host-pack selection tokens) then take the original seed's
OKLCH hue. Neutral ink on colored fills is deliberately excluded. Role chroma is bounded to
0.025–0.10: the ceiling leaves room to adjust lightness across the hue wheel, and the floor keeps
quiet tints colored. Before fixing the baseline, gamut mapping tries nearest lightness, then
reduces role chroma by at most half (never below 0.025) if required to carry its ink. Filled roles
include dimmed and keycap ink; selection keeps primary text at 7:1. RGB is never clipped. There is one baseline,
from HSV saturation 0.72 and value 0.85; no global saturation retries.

Fix moves accent lightness at that same hue and chroma. Accent/status and tint/selection separation
participate in the lightness constraints; semantic statuses and syntax/category colors retain
their meanings. Contrast on a colored fill moves its ink; a rule explicitly naming the fill as
adjustable may move its lightness but cannot gray it. An impossible repair reports failure.

Every registered token is materialized in all four palettes; the registry defaults to core.
Supplying the app registry starts from its standard/Contrast pack palettes, including code syntax.
If the code current-line band collides with a derived selection or find tint, only that band moves
along black and white blend paths. The closest passing saved color by OKLab distance is chosen;
all readers must retain their required contrast. A band that already passes stays unchanged.
The candidate then runs supported Fix actions and must finish with zero validator findings,
including after hex serialization, before it is returned. Each repaired palette is rounded before
the next repair so every later constraint measures the eventual saved grounds. Seeds set no metrics. The sheet calls
this API off the main actor, supplies the host's registry and validates against its packs, and
saves and applies only a successful result.

The seed-theme test grid is exactly 0, 30, …, 330 degrees × both ground preferences: 24 themes and 96
appearances. DTCG import uses the shared theme model.

The same test grid also checks every chromatic accent-family token after JSON serialization:
OKLCH hue stays within 20° of the original HSV seed converted to OKLab, and chroma is at least
half its pre-Fix value and at least 0.0125. The pre-Fix baseline itself must have chroma ≥0.023
(the 0.025 derivation floor with 8-bit rounding tolerance), preventing a gray baseline from
making the relative assertion vacuous. The 50% allowance permits rounding and future bounded
gamut changes; today's Fix retains full chroma.

Seed miniatures show core color roles, including the derived link, rather than host syntax
numbers. Gallery miniatures retain host syntax previews. Their primary button uses
`accent.filled`/`accent.filledForeground` with a `border.focus` ring.
