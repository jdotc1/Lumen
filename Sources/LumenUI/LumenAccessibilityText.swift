import AppKit

/// Reads accessibility strings without trusting the Swift overlay's `String?` return type.
///
/// SwiftUI on macOS 27 can answer `accessibilityLabel`, `accessibilityTitle` and
/// `accessibilityValue` with an `NSAttributedString`. Calling `accessibilityLabel()` through
/// `NSAccessibilityProtocol` then bridges that object to `String`, which raises
/// `-[NSConcreteAttributedString _fastCStringContents:]: unrecognized selector`. Swift code
/// cannot catch an Objective-C exception, and one that unwinds through an async task leaves the
/// main actor's executor state broken. These helpers send the selector untyped and accept
/// either a string or an attributed string.
package enum LumenAccessibilityText {
    package static func label(of object: AnyObject) -> String? { read(object, "accessibilityLabel") }
    package static func title(of object: AnyObject) -> String? { read(object, "accessibilityTitle") }
    package static func value(of object: AnyObject) -> String? { read(object, "accessibilityValue") }

    /// Label, title and value, in that order, skipping the ones that are missing.
    package static func candidates(of object: AnyObject) -> [String] {
        [label(of: object), title(of: object), value(of: object)].compactMap { $0 }
    }

    private static func read(_ object: AnyObject, _ name: String) -> String? {
        let selector = NSSelectorFromString(name)
        guard let object = object as? NSObject, object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return value as? String
    }
}
