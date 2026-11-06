/// Optional schema-2 shadow and glow declarations. Every leaf inherits independently.
public struct LumenThemeDepth: Hashable, Sendable, Codable {
    public struct Opacity: Hashable, Sendable, Codable {
        public var light: Double?
        public var dark: Double?

        public init(light: Double? = nil, dark: Double? = nil) {
            self.light = light
            self.dark = dark
        }

        public func merging(_ overrides: Self?) -> Self {
            Self(light: overrides?.light ?? light, dark: overrides?.dark ?? dark)
        }
    }

    public struct Shadow: Hashable, Sendable, Codable {
        public var opacity: Opacity?
        public var radius: Double?
        public var y: Double?

        public init(opacity: Opacity? = nil, radius: Double? = nil, y: Double? = nil) {
            self.opacity = opacity
            self.radius = radius
            self.y = y
        }

        public func merging(_ overrides: Self?) -> Self {
            Self(opacity: opacity.map { $0.merging(overrides?.opacity) } ?? overrides?.opacity,
                 radius: overrides?.radius ?? radius, y: overrides?.y ?? y)
        }
    }

    public struct Halo: Hashable, Sendable, Codable {
        public var opacity: Double?
        public var radius: Double?
        public var y: Double?

        public init(opacity: Double? = nil, radius: Double? = nil, y: Double? = nil) {
            self.opacity = opacity
            self.radius = radius
            self.y = y
        }

        public func merging(_ overrides: Self?) -> Self {
            Self(opacity: overrides?.opacity ?? opacity,
                 radius: overrides?.radius ?? radius, y: overrides?.y ?? y)
        }
    }

    public struct Glow: Hashable, Sendable, Codable {
        public var hero: Halo?
        public var selection: Halo?

        public init(hero: Halo? = nil, selection: Halo? = nil) {
            self.hero = hero
            self.selection = selection
        }

        public func merging(_ overrides: Self?) -> Self {
            Self(hero: hero.map { $0.merging(overrides?.hero) } ?? overrides?.hero,
                 selection: selection.map { $0.merging(overrides?.selection) } ?? overrides?.selection)
        }
    }

    public var menu: Shadow?
    public var popover: Shadow?
    public var glow: Glow?

    public init(menu: Shadow? = nil, popover: Shadow? = nil, glow: Glow? = nil) {
        self.menu = menu
        self.popover = popover
        self.glow = glow
    }

    public func merging(_ overrides: Self?) -> Self {
        Self(menu: menu.map { $0.merging(overrides?.menu) } ?? overrides?.menu,
             popover: popover.map { $0.merging(overrides?.popover) } ?? overrides?.popover,
             glow: glow.map { $0.merging(overrides?.glow) } ?? overrides?.glow)
    }
}

/// Fully resolved depth, shared by the validator and UI. Defaults match Lumen's original shadows.
public struct LumenDepth: Hashable, Sendable {
    public struct Opacity: Hashable, Sendable {
        public var light: Double
        public var dark: Double

        public init(light: Double, dark: Double) {
            self.light = light
            self.dark = dark
        }
    }

    public struct Shadow: Hashable, Sendable {
        public var opacity: Opacity
        public var radius: Double
        public var y: Double

        public init(opacity: Opacity, radius: Double, y: Double) {
            self.opacity = opacity
            self.radius = radius
            self.y = y
        }

        fileprivate func applying(_ theme: LumenThemeDepth.Shadow?) -> Self {
            Self(opacity: Opacity(light: theme?.opacity?.light ?? opacity.light,
                                  dark: theme?.opacity?.dark ?? opacity.dark),
                 radius: theme?.radius ?? radius, y: theme?.y ?? y)
        }
    }

    public struct Halo: Hashable, Sendable {
        public var opacity: Double
        public var radius: Double
        public var y: Double

        public init(opacity: Double, radius: Double, y: Double) {
            self.opacity = opacity
            self.radius = radius
            self.y = y
        }

        fileprivate func applying(_ theme: LumenThemeDepth.Halo?) -> Self {
            Self(opacity: theme?.opacity ?? opacity, radius: theme?.radius ?? radius, y: theme?.y ?? y)
        }
    }

    public struct Glow: Hashable, Sendable {
        public var hero: Halo
        public var selection: Halo

        public init(hero: Halo = .init(opacity: 0.4, radius: 20, y: 4),
                    selection: Halo = .init(opacity: 0.45, radius: 8, y: 0)) {
            self.hero = hero
            self.selection = selection
        }
    }

    public var menu: Shadow
    public var popover: Shadow
    public var glow: Glow

    public init(menu: Shadow = .init(opacity: .init(light: 0.12, dark: 0.40), radius: 10, y: 4),
                popover: Shadow = .init(opacity: .init(light: 0.14, dark: 0.45), radius: 16, y: 6),
                glow: Glow = .init()) {
        self.menu = menu
        self.popover = popover
        self.glow = glow
    }

    public static let standard = LumenDepth()

    /// Resolves leaves only after inheritance. Validation reports invalid values without clamping.
    public static func resolving(_ theme: LumenThemeDepth?) -> Self {
        let base = Self.standard
        return Self(menu: base.menu.applying(theme?.menu), popover: base.popover.applying(theme?.popover),
                    glow: Glow(hero: base.glow.hero.applying(theme?.glow?.hero),
                               selection: base.glow.selection.applying(theme?.glow?.selection)))
    }
}
