import Foundation

/// Package-owned defaults usable by serialized public default arguments.
/// Computed values preserve localization lookup at the point an app omits an argument.
@usableFromInline
internal enum LumenCoreDefaultStrings {
    @usableFromInline static var recent: String {
        lumenLocalized(String(localized: "Recent", bundle: .module, comment: "Recent documents section title."))
    }
    @usableFromInline static var noItems: String {
        lumenLocalized(String(localized: "No items", bundle: .module, comment: "Empty table message."))
    }
    @usableFromInline static var noValues: String {
        lumenLocalized(String(localized: "No values", bundle: .module, comment: "Empty key and value editor message."))
    }
    @usableFromInline static var command: String {
        lumenLocalized(String(localized: "Command", bundle: .module, comment: "Console input placeholder."))
    }
    @usableFromInline static var addToken: String {
        lumenLocalized(String(localized: "Add a token", bundle: .module, comment: "Token field placeholder."))
    }
    @usableFromInline static var defaultLabel: String {
        lumenLocalized(String(localized: "Default", bundle: .module, comment: "Inherited value label."))
    }
    @usableFromInline static var add: String {
        lumenLocalized(String(localized: "Add", bundle: .module, comment: "List editor input placeholder."))
    }
}
