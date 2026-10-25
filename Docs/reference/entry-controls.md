# Entry controls

`LumenDateField(selection:in:style:)` and `LumenTimeField(selection:in:style:)` bind to a `Date`.
The optional closed range constrains the complete date, including the day for a time field.
The default `.stepper` uses a borderless, background-free AppKit `NSDatePicker` in `.textField`
style beside the same arrow buttons as `LumenNumberField`. Its font resolves the actual Lumen body
font (including monospaced digits and text scale) through `Font.resolve(in:).ctFont`. Text uses the
palette; Lumen alone fades disabled editors, whose editing and focus are blocked separately.
The arrows step a calendar day for dates or a minute for times, clamped to the optional range.
AppKit exposes no public selected-component API. The environment calendar, locale and time zone
are preserved. `.graphicalPopover` retains SwiftUI's graphical picker inside `LumenPopoverContent`.
Both styles use the number field's chrome, focus border and resolved control height.

`LumenStepper(value:in:step:formatter:)` binds to a `Double`. Its positive finite step moves the
value and clamps at the closed range's ends. A formatter closure supplies the displayed string.
Pair it with `LumenNumberField` in `LumenFormRow` using the same binding. Invalid steps do not write.

`LumenTokenField(tokens:prompt:suggestions:)` binds to `[String]`. Return commits the input; commas
commit completed tokens while preserving the unfinished suffix. Whitespace is trimmed and blanks
and exact duplicates are ignored. The remove button deletes its chip; backspace in an empty input
removes the last chip. Matching suggestions appear below the field while it has focus.

Under PRINCIPLES §10, date/time and stepper controls use the one-line control height and body type.
Tokens use the shared chip tokens, small radius, caption-emphasized type and chip padding;
`LumenFlowLayout` wraps the chips. Filled chips use the filled-accent foreground/background family.
Text scale resolves through `lumenMetrics`, preserving the same heights as `LumenNumberField` at
every density. No separate density-specific field height is introduced.

`LumenSegmentedControl(selection:options:labelStyle:title:systemImage:)` binds a hashable value.
Use `.text`, `.glyph`, or `.glyphAndText`; a missing glyph retains the title. It falls back to a
menu when the segments cannot fit. PRINCIPLES §10 explicitly puts segmented controls in the
filled-accent family, matching `LumenModeSwitcher(style: .pill)` rather than its mode-tile plate.
The existing switcher has no explicit glyph-only presentation, so the sibling supplies that API.

## Adaptive layout

The compact fixture already supplied density. Token-field padding now consumes it: compact reduces
vertical field padding by 2 pt and chip padding to a 1 pt minimum; comfortable adds 2 pt. One-line
controls retain the shared 24 pt minimum (grown with text scale), matching the number field.
The flow fills its proposed width with leading alignment before drawing the field surface, so
caller frames no longer center a narrower field. Chip labels are horizontally fixed; the flow
wraps whole chips. The input has a 120 pt layout width, independent of text scale, so its ideal
measurement cannot consume an otherwise usable line. Longer input scrolls inside its text field.

API declarations consulted: the installed AppKit `NSDatePicker.h` / `NSDatePickerCell.h`, and the
selected macOS SDK's SwiftUICore `Font.resolve(in:)`, `Font.Resolved.ctFont` and
`EnvironmentValues.fontResolutionContext`. No private component-selection API is used.
