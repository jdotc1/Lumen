import SwiftUI
import LumenTokens

/// One action: a panel bar's button, a welcome window's tile or a hero's call to action.
///
/// `LumenBarAction` and `LumenWelcomeAction` are aliases for this type, so existing call sites keep
/// compiling. A value carries what any presentation can use: a title, an optional glyph, a hue,
/// an optional subtitle and shortcut, primary emphasis, enabled state, help and an accessibility
/// identifier. Each presentation reads the fields it draws and ignores the rest.
public struct LumenAction: Identifiable {
    /// Where an action is drawn. It is informational: presentations take the fields they need.
    public enum Role: Sendable, Hashable {
        /// A compact button in a panel bar or detail header.
        case bar
        /// A tile on the welcome window.
        case welcome
        /// A hero's primary or secondary call to action.
        case hero
    }

    public let id: String
    public let title: String
    public let subtitle: String?
    /// The SF Symbol name. Welcome tiles always have one; bar actions may not.
    public let systemImage: String?
    public let hue: LumenToken
    public let shortcut: KeyboardShortcut?
    /// Hovering the primary welcome action makes the starfield surge.
    public let isPrimary: Bool
    public let isEnabled: Bool
    public let role: Role
    public let perform: @MainActor () -> Void
    /// Set on the action's button, for UI tests.
    public var accessibilityIdentifier: String?
    /// The button's help tag, when it should say more than the title.
    public var help: String?

    /// A compact action (a panel bar's button).
    public init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, perform: @escaping @MainActor () -> Void) {
        id = title
        self.title = title
        subtitle = nil
        self.systemImage = systemImage
        hue = .accent
        shortcut = nil
        isPrimary = false
        self.isEnabled = isEnabled
        role = .bar
        self.perform = perform
    }

    /// - Parameter accessibilityIdentifier: set on the action's button, for UI tests.
    public init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, accessibilityIdentifier: String?,
                perform: @escaping @MainActor () -> Void) {
        self.init(title, systemImage: systemImage, isEnabled: isEnabled, perform: perform)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    /// - Parameters:
    ///   - help: the button's help tag, when it should say more than the title.
    ///   - accessibilityIdentifier: set on the action's button, for UI tests.
    public init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, help: String?,
                accessibilityIdentifier: String? = nil, perform: @escaping @MainActor () -> Void) {
        self.init(title, systemImage: systemImage, isEnabled: isEnabled, perform: perform)
        self.help = help
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    /// A welcome tile: New Project, Open…, Clone…
    public init(_ title: String, subtitle: String? = nil, systemImage: String, hue: LumenToken, shortcut: KeyboardShortcut? = nil,
                isPrimary: Bool = false, perform: @escaping @MainActor () -> Void) {
        id = title
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.hue = hue
        self.shortcut = shortcut
        self.isPrimary = isPrimary
        isEnabled = true
        role = .welcome
        self.perform = perform
    }

    /// The same action drawn in another role.
    public func with(role: Role) -> LumenAction {
        LumenAction(copying: self, role: role)
    }

    private init(copying other: LumenAction, role: Role) {
        id = other.id
        title = other.title
        subtitle = other.subtitle
        systemImage = other.systemImage
        hue = other.hue
        shortcut = other.shortcut
        isPrimary = other.isPrimary
        isEnabled = other.isEnabled
        self.role = role
        perform = other.perform
        accessibilityIdentifier = other.accessibilityIdentifier
        help = other.help
    }
}

/// A compact action in a panel bar. An alias for `LumenAction`.
public typealias LumenBarAction = LumenAction
/// One action on the welcome window: New Project, Open…, Clone… An alias for `LumenAction`.
public typealias LumenWelcomeAction = LumenAction
