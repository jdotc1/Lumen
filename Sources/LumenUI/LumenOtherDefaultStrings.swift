import Foundation

/// Package-owned defaults remain localized without changing app-supplied String parameters.
@usableFromInline
internal enum LumenOtherDefaultStrings {
    @usableFromInline static var filter: String {
        lumenLocalized(String(localized: "Filter", bundle: .module, comment: "Default filter text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var next: String {
        lumenLocalized(String(localized: "Next", bundle: .module, comment: "Default next text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var color: String {
        lumenLocalized(String(localized: "Color", bundle: .module, comment: "Default color text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var cancel: String {
        lumenLocalized(String(localized: "Cancel", bundle: .module, comment: "Default cancel text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var tryAgain: String {
        lumenLocalized(String(localized: "Try again", bundle: .module, comment: "Default tryAgain text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var ready: String {
        lumenLocalized(String(localized: "Ready", bundle: .module, comment: "Default ready text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var done: String {
        lumenLocalized(String(localized: "Done", bundle: .module, comment: "Default done text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var new: String {
        lumenLocalized(String(localized: "New", bundle: .module, comment: "Default new text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var dockMessage: String {
        lumenLocalized(String(localized: "Drag a sidebar icon here to dock.", bundle: .module, comment: "Default dockMessage text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var newTab: String {
        lumenLocalized(String(localized: "New Tab", bundle: .module, comment: "Default newTab text supplied by Lumen when the app omits it."))
    }
    @usableFromInline static var nothingSelected: String {
        lumenLocalized(String(localized: "Nothing selected", bundle: .module, comment: "Default nothingSelected text supplied by Lumen when the app omits it."))
    }
}
