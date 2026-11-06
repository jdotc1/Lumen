# Native settings form rows

Place each setting directly in a SwiftUI `Section` inside a grouped `Form`. Each row then keeps its
own separator and leading label/trailing control relationship. Use `LumenSettingsSidebarView` for
the Settings window root. The Catalog's Model server category demonstrates the complete pattern.

| Raw pattern | Replacement |
|---|---|
| A caption above a field whose placeholder becomes the setting name | `LumenSettingsNumberRow("Request timeout", value: $timeout, in: 1_000...9_999_999, unit: "ms")` |
| Monospacing applied to a whole labeled `TextField` | `LumenSettingsTextRow("Loopback endpoint", text: $endpoint, monospaced: true)` |
| A large hollow circle beside status prose | `LumenSettingsStatusRow("Connection", detail: "Service is available", tone: .success)` |
| `ContentUnavailableView` inside a lazy stack in a form section | `LumenSettingsEmptyRow("No models discovered", detail: "Start a service, then refresh.")` |
| Leading action buttons | `LumenSettingsButtonRow { Button("Refresh", action: refresh) }` |
| Several controls stacked inside one form row | Separate `LumenSettingsRow` values directly inside `Section` |

`LumenSettingsRow` owns the body-font primary label and an optional caption description. Put only
the control in its closure; the row supplies its label. Text-field monospacing is confined to the
value. Numeric rows reserve seven digits plus locale grouping and show the unit outside the field;
range and step behavior remains that of `LumenNumberField`. Its additive initializer takes
`minimumDigits:usesGrouping:` for other required widths without changing existing callers.

`LumenSettingsStatusRow` uses the existing tone foreground roles and their filled symbols. The
menu-bar `LumenStatusGlyph` produces a template status-item image and is not a settings row.
`LumenSettingsEmptyRow` always has visible text, including when its supplied title is empty. Its
`actionTitle:action:` initializer adds a trailing recovery button. Actions in `LumenSettingsButtonRow`
use native bordered push buttons at regular control size, aligned to the trailing edge. The row
does not designate a primary action; all actions receive the same plain bordered style. Explicit
styles on individual buttons remain the caller's choice.

`LumenFormSection` groups rich-pane and sheet content; it is not a native grouped-form section.
Do not put it, or a `VStack` of controls, inside a grouped `Form`: use SwiftUI `Section` there so
SwiftUI sees individual rows. Its title is section metadata, not a replacement for each row's label.
