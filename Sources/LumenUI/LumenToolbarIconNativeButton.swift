import AppKit
import SwiftUI
import LumenTokens

/// A toolbar icon (`LumenToolbarIcon`) that is a real `NSButton`, for toolbar items AppKit must see
/// as native buttons: Settings' Back and Forward, whose accessible names, enabled state and
/// ⌘[ / ⌘] key equivalents AppKit owns (design review 2026-11, note 24).
///
/// The button draws nothing of its own. A hosting view inside it draws the same vector icon as
/// every other top-bar button, so the rounded square, the light and the glyph stay one unit, and
/// it follows the button's hover, press and enabled state.
struct LumenToolbarIconNativeButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    var isEnabled: Bool = true
    var keyEquivalent: String = ""
    var modifiers: NSEvent.ModifierFlags = []
    /// When set, a click opens this menu under the icon instead of running `action`.
    var menu: [LumenToolbarIconMenu.Item]? = nil
    let action: () -> Void

    func makeNSView(context: Context) -> IconButton {
        let button = IconButton()
        button.update(from: self, environment: context.environment)
        return button
    }

    func updateNSView(_ button: IconButton, context: Context) {
        button.update(from: self, environment: context.environment)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IconButton, context: Context) -> CGSize? {
        let side = context.environment.lumenMetrics.layout.toolbarButton
        return CGSize(width: side, height: side)
    }

    /// Hover and press, observed by the hosted icon.
    @Observable final class Interaction {
        var isHovered = false
        var isPressed = false
    }

    /// The hosted drawing. It reads the interaction state, so hover and press redraw only the icon.
    struct Face: View {
        let systemImage: String
        let isEnabled: Bool
        let interaction: Interaction
        @Environment(\.lumenPalette) private var palette
        @Environment(\.lumenMetrics) private var metrics

        var body: some View {
            let hovered = isEnabled && interaction.isHovered
            LumenToolbarIcon(isHovered: hovered, isPressed: isEnabled && interaction.isPressed) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.layout.toolbarGlyphSize, weight: .regular))
                    .foregroundStyle(palette[.toolbarForeground].opacity(hovered ? 1 : 0.75))
            }
            .opacity(isEnabled ? 1 : metrics.layout.disabledOpacity)
            .accessibilityHidden(true)
        }
    }

    /// A hosting view that never takes the mouse, so clicks, hover and tracking stay the button's.
    final class PassThroughHost: NSHostingView<AnyView> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }
    }

    /// Reports the cell's highlight (the pressed state AppKit tracks during a click).
    final class Cell: NSButtonCell {
        var onHighlight: ((Bool) -> Void)?
        override var isHighlighted: Bool { didSet { if oldValue != isHighlighted { onHighlight?(isHighlighted) } } }
        // The hosted icon is the whole appearance: the cell draws no bezel, title or image.
        override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
    }

    final class IconButton: NSButton {
        let interaction = Interaction()
        private var host: PassThroughHost?
        private var tracking: NSTrackingArea?
        private var perform: () -> Void = {}
        private var menuItems: [LumenToolbarIconMenu.Item]?

        override class var cellClass: AnyClass? {
            get { Cell.self }
            set {}
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            cell = Cell()
            isBordered = false
            title = ""
            imagePosition = .imageOnly
            setButtonType(.momentaryChange)
            focusRingType = .default
            target = self
            action = #selector(fire)
            (cell as? Cell)?.onHighlight = { [weak self] pressed in self?.interaction.isPressed = pressed }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        @objc private func fire() {
            guard let menuItems else { perform(); return }
            let menu = NSMenu()
            for item in menuItems {
                let entry = NSMenuItem(title: item.title, action: #selector(choose(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = item
                entry.state = item.isOn ? .on : .off
                menu.addItem(entry)
            }
            interaction.isPressed = true
            // Opens under the icon, leading edges aligned, as a toolbar pull-down does.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4), in: self)
            interaction.isPressed = false
        }

        @objc private func choose(_ sender: NSMenuItem) { (sender.representedObject as? LumenToolbarIconMenu.Item)?.action() }

        func update(from spec: LumenToolbarIconNativeButton, environment: EnvironmentValues) {
            perform = spec.action
            menuItems = spec.menu
            // SwiftUI writes its environment's enabled state to a represented control, so both count.
            let enabled = spec.isEnabled && environment.isEnabled
            isEnabled = enabled
            if !enabled { interaction.isHovered = false; interaction.isPressed = false }
            keyEquivalent = spec.keyEquivalent
            keyEquivalentModifierMask = spec.modifiers
            toolTip = spec.title
            setAccessibilityLabel(spec.title)
            if spec.menu != nil { setAccessibilityRole(.popUpButton) }
            let face = Face(systemImage: spec.systemImage, isEnabled: enabled, interaction: interaction)
                .environment(\.colorScheme, environment.colorScheme)
                .environment(\._colorSchemeContrast, environment.colorSchemeContrast)
                .environment(\.layoutDirection, environment.layoutDirection)
                .environment(\.displayScale, environment.displayScale)
                .environment(\.lumenPalette, environment.lumenPalette)
                .environment(\.lumenMetrics, environment.lumenMetrics)
                .environment(\.lumenIconAppearance, environment.lumenIconAppearance)
            if let host {
                host.rootView = AnyView(face)
            } else {
                let made = PassThroughHost(rootView: AnyView(face))
                made.translatesAutoresizingMaskIntoConstraints = false
                addSubview(made)
                NSLayoutConstraint.activate([
                    made.leadingAnchor.constraint(equalTo: leadingAnchor), made.trailingAnchor.constraint(equalTo: trailingAnchor),
                    made.topAnchor.constraint(equalTo: topAnchor), made.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
                host = made
            }
            let side = environment.lumenMetrics.layout.toolbarButton
            if intrinsicSide != side { intrinsicSide = side; invalidateIntrinsicContentSize() }
        }

        private var intrinsicSide: CGFloat = 28
        override var intrinsicContentSize: NSSize { NSSize(width: intrinsicSide, height: intrinsicSide) }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) { if isEnabled { interaction.isHovered = true } }
        override func mouseExited(with event: NSEvent) { interaction.isHovered = false }

        // The focus ring follows the icon's rounded square, not the button's frame.
        override var focusRingMaskBounds: NSRect { bounds }
        override func drawFocusRingMask() {
            let face = LumenToolbarIconGeometry.faceRatio * min(bounds.width, bounds.height)
            let rect = NSRect(x: bounds.midX - face / 2, y: bounds.midY - face / 2, width: face, height: face)
            let radius = face * LumenToolbarIconGeometry.cornerRatio
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }
}

/// A toolbar pull-down drawn as a toolbar icon (design review 2026-11, note 24): the same one-unit
/// vector icon as every other top-bar button, with no chevron or capsule, opening a native menu
/// under it. Use it where a toolbar `Menu` would otherwise fall back to the system's menu item,
/// which ignores button styles.
public struct LumenToolbarIconMenu: View {
    /// One menu command; `isOn` shows a checkmark.
    public struct Item: Identifiable {
        public let id: String
        public let title: String
        public let isOn: Bool
        public let action: () -> Void
        public init(_ title: String, isOn: Bool = false, action: @escaping () -> Void) {
            self.id = title
            self.title = title
            self.isOn = isOn
            self.action = action
        }
    }

    private let title: String
    private let systemImage: String
    private let items: [Item]

    /// - Parameters:
    ///   - title: the accessible name and tooltip.
    ///   - systemImage: the SF Symbol drawn on the icon.
    ///   - items: the menu's commands, in order.
    public init(_ title: String, systemImage: String, items: [Item]) {
        self.title = title
        self.systemImage = systemImage
        self.items = items
    }

    public var body: some View {
        LumenToolbarIconNativeButton(title: title, systemImage: systemImage, menu: items) {}
            .fixedSize()
    }
}
