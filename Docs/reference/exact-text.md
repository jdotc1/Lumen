# Exact text entry

`.lumenExactText()` makes every text field inside a view keep exactly what is typed or pasted. Use it
for entitlement keys, identifiers, hashes and hex.

```swift
LumenFieldRow("Entitlement key") {
    LumenTextField("com.apple.security.…", text: $key, monospaced: true)
}
.lumenExactText()
```

It turns off smart quotes and dashes, text replacement, spelling and grammar correction and checking,
link and data detection, text completion, inline prediction, Writing Tools rewriting and smart
insert/delete. macOS has no separate auto-capitalization switch; capitalization changes come from
automatic replacement and correction, which are off. Whitespace is never trimmed or normalized, and
the binding is neither read nor written. Pasted curly quotes and dashes stay as pasted.

It works with SwiftUI `TextField`, `LumenTextField`, `LumenInlineField` and `LumenFieldRow` content.
SwiftUI edits through the window's shared field editor, so the modifier configures that editor only
while a field in its view is being edited, re-applies on each change (Edit > Substitutions can be
toggled mid-edit) and restores the previous flags when focus leaves. Fields outside the view are
unaffected. `.lumenExactText(false)` is a passthrough. It adds no visual change, no layout, no
accessibility element and no strings, and does nothing in offscreen rendering.
