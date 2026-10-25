import Foundation

/// A rule's repair target. Contrast always adjusts its foreground; visibility adjusts the token
/// explicitly named by that rule. Neither repair changes the other palette entry.
public enum LumenThemeFix: Hashable, Sendable {
    case contrast(foreground: LumenToken, ground: LumenToken, minimum: Double,
                  raised: Bool = false, foregroundOpacity: Double = 1, groundOverlayOpacity: Double = 0)
    case visibility(token: LumenToken, ground: LumenToken, minimumContrast: Double?, minimumDistance: Double?)
    case opacity(token: LumenToken)
    case metric(key: LumenThemeMetrics.Key, minimum: Double, maximum: Double)
}

/// A failed repair leaves the input theme untouched.
public struct LumenThemeFixError: Error, LocalizedError, Equatable, Sendable, CustomStringConvertible {
    public let description: String
    public var errorDescription: String? { description }
    public init(_ description: String) { self.description = description }
}

public extension LumenValidator {
    /// Repairs one finding in a copy, suitable for one editor undo operation. Pass a flattened
    /// theme so inherited colors and metrics participate in the same checks as validation.
    ///
    /// Color repairs seek the nearest passing OKLCH lightness, in either direction, preserving
    /// hue, chroma and alpha. Chromatic accent roles never lose chroma; other roles may
    /// reduce it only if no in-gamut lightness passes. The result
    /// must also pass after hex serialization; an impossible repair throws without a partial edit.
    static func fix(_ issue: LumenIssue, in theme: LumenTheme, registry: LumenRegistry) throws -> LumenTheme {
        guard let repair = issue.fix else { throw LumenThemeFixError("This finding needs a manual change.") }
        var result = theme
        let appearance = theme.normalized(issue.appearance)
        switch repair {
        case .metric(let key, let minimum, let maximum):
            guard !registry.lockedMetrics.contains(key) else {
                throw LumenThemeFixError("This metric is locked by the app's packs.")
            }
            guard var metrics = theme.metrics else { throw LumenThemeFixError("This metric is inherited; resolve its parent first.") }
            func clamped(_ value: Double?) throws -> Double {
                guard let value, !value.isNaN else { throw LumenThemeFixError("This metric has no numeric value to clamp.") }
                return min(maximum, max(minimum, value))
            }
            switch key {
            case .typeScale: metrics.typeScale = try clamped(metrics.typeScale)
            case .spacingScale: metrics.spacingScale = try clamped(metrics.spacingScale)
            case .radiusProfile:
                guard case .uniform(let value)? = metrics.radiusProfile else { throw LumenThemeFixError("This radius is not a numeric value.") }
                metrics.radiusProfile = .uniform(try clamped(value))
            case .depth: throw LumenThemeFixError("Depth has coupled leaf ranges; edit its declaration manually.")
            case .motion: throw LumenThemeFixError("Motion has no numeric range to clamp.")
            }
            result.metrics = metrics
            guard !metricIssues(in: result, registry: registry).contains(where: { $0.fix == repair }) else {
                throw LumenThemeFixError("The clamped metric still fails its rule.")
            }
        case .opacity(let token):
            var color = theme.color(token, for: appearance, in: registry)
            color.alpha = 1
            set(color, for: token, appearance: appearance, in: &result)
        case .contrast, .visibility:
            let token: LumenToken
            switch repair {
            case .contrast(let foreground, _, _, let raised, _, _):
                token = raised ? LumenTheme.raisedSubstitutions[foreground] ?? foreground : foreground
            case .visibility(let adjustable, _, _, _): token = adjustable
            default: preconditionFailure("Color repair expected")
            }
            let original = theme.color(token, for: appearance, in: registry)
            let constraints = fixConstraints(for: token, repair: repair, theme: theme, appearance: appearance, registry: registry)
            let customRules = registry.rules.compactMap { $0 as? LumenCustomRule }
            func passes(_ color: LumenColor) -> Bool {
                guard constraints.allSatisfy({ $0.passes(color, space: theme.colorSpace) }) else { return false }
                var candidate = theme
                set(color, for: token, appearance: appearance, in: &candidate)
                // A fallback can make a foreground supply its ground. Such a dependency is not a
                // license to move both sides of a contrast pair.
                guard constraints.allSatisfy({ constraint in
                    opaqueGrounds(constraint.ground, in: candidate, appearance: appearance, registry: registry,
                                  resolution: constraint.resolution) == constraint.grounds
                }) else { return false }
                return customRules.allSatisfy { rule in
                    !rule.issues(in: candidate, appearance: appearance, registry: registry).contains { $0.token == token && $0.fix != nil }
                }
            }
            guard let color = nearestFixColor(original, space: theme.colorSpace, constraints: constraints,
                                              preservesChroma: registry.seedAccentTokens.contains(token), passes: passes) else {
                throw LumenThemeFixError("No lightness or permitted chroma makes \(token.rawValue) pass without changing its ground.")
            }
            set(color, for: token, appearance: appearance, in: &result)
            // Match the structured rule, not its changing ratio in the human-readable message.
            guard !issues(for: result, in: registry).contains(where: { $0.appearance == appearance && $0.fix == repair }) else {
                throw LumenThemeFixError("The proposed color still fails this rule; no change was applied.")
            }
        }
        return result
    }

    private static func set(_ color: LumenColor, for token: LumenToken, appearance: LumenAppearance, in theme: inout LumenTheme) {
        if appearance.isHighContrast {
            if appearance.isDark {
                var palette = theme.darkHighContrast ?? LumenPalette(); palette[token] = color; theme.darkHighContrast = palette
            } else {
                var palette = theme.lightHighContrast ?? LumenPalette(); palette[token] = color; theme.lightHighContrast = palette
            }
        } else if appearance.isDark {
            var palette = theme.dark ?? LumenPalette(); palette[token] = color; theme.dark = palette
        } else {
            var palette = theme.light ?? LumenPalette(); palette[token] = color; theme.light = palette
        }
    }

    private struct FixConstraint {
        var ground: LumenToken
        var grounds: [LumenColor]
        var resolution: LumenResolution
        var minimum: Double?
        var distance: Double?
        var inkOpacity: Double = 1
        var overlayOpacity: Double = 0

        func passes(_ color: LumenColor, space: LumenColorSpace) -> Bool {
            grounds.allSatisfy { base in
                let ground = overlayOpacity > 0 ? color.composited(alpha: overlayOpacity, over: base) : base
                let ink = color.composited(alpha: inkOpacity, over: ground)
                return (minimum.map { ink.contrastRatio(against: ground, in: space) >= $0 } ?? true)
                    && (distance.map { ink.perceptualDistance(to: ground, in: space) >= $0 } ?? true)
            }
        }
    }

    private static func fixConstraints(for token: LumenToken, repair: LumenThemeFix, theme: LumenTheme,
                                       appearance: LumenAppearance, registry: LumenRegistry) -> [FixConstraint] {
        var result: [FixConstraint] = []
        func append(_ ground: LumenToken, minimum: Double?, distance: Double? = nil,
                    raised: Bool = false, opacity: Double = 1, overlay: Double = 0) {
            let resolution = LumenResolution(substitutions: raised ? LumenTheme.raisedSubstitutions : [:])
            result.append(FixConstraint(ground: ground,
                grounds: opaqueGrounds(ground, in: theme, appearance: appearance, registry: registry, resolution: resolution),
                resolution: resolution, minimum: minimum, distance: distance, inkOpacity: opacity, overlayOpacity: overlay))
        }
        switch repair {
        case .contrast(_, let ground, let minimum, let raised, let opacity, let overlay):
            append(ground, minimum: minimum, raised: raised, opacity: opacity, overlay: overlay)
        case .visibility(_, let ground, let minimum, let distance): append(ground, minimum: minimum, distance: distance)
        default: break
        }
        for requirement in registry.contrastRequirements(of: token) {
            append(requirement.ground, minimum: requirement.minimum)
            if LumenTheme.raisedSubstitutions[token] == nil {
                append(requirement.ground, minimum: requirement.minimum, raised: true)
            }
        }
        for rule in registry.rules.compactMap({ $0 as? LumenVisibilityRule }) where rule.token == token {
            append(rule.ground, minimum: rule.minimumContrast, distance: rule.minimumDistance)
        }
        // Keep accent/status and tint/selection distinctness while moving lightness. A seed
        // must not need a global saturation reduction merely to escape a status collision.
        if registry.seedAccentTokens.contains(token) {
            for rule in registry.rules.compactMap({ $0 as? LumenDistinctRule }) where rule.tokens.contains(token) {
                for other in rule.tokens where other != token {
                    append(other, minimum: nil, distance: rule.minimumDistance)
                }
            }
        }
        // Custom rules expose their constraints through findings. Ask at both luminance
        // extremes as well as the current color so a presently passing custom pair stays in
        // the intersection (dimmed toolbar glyphs and text on filled-accent keycaps).
        var customRepairs: Set<LumenThemeFix> = []
        let customRules = registry.rules.compactMap { $0 as? LumenCustomRule }
        for ink in [theme.color(token, for: appearance, in: registry), LumenColor(red: 0, green: 0, blue: 0),
                    LumenColor(red: 1, green: 1, blue: 1)] {
            var probe = theme
            set(ink, for: token, appearance: appearance, in: &probe)
            for rule in customRules {
                for finding in rule.issues(in: probe, appearance: appearance, registry: registry) where finding.token == token {
                    if let fix = finding.fix { customRepairs.insert(fix) }
                }
            }
        }
        for fix in customRepairs {
            if case .contrast(_, let ground, let minimum, let raised, let opacity, let overlay) = fix {
                append(ground, minimum: minimum, raised: raised, opacity: opacity, overlay: overlay)
            }
        }
        return result
    }

    private static func nearestFixColor(_ original: LumenColor, space: LumenColorSpace, constraints: [FixConstraint],
                                        preservesChroma: Bool, passes: (LumenColor) -> Bool) -> LumenColor? {
        let lab = original.oklab(in: space)
        let chroma = hypot(lab.a, lab.b)
        let hue = atan2(lab.b, lab.a)
        func atChroma(_ c: Double) -> LumenColor? {
            func color(_ lightness: Double) -> LumenColor? {
                oklchColor(lightness: lightness, chroma: c, hue: hue, alpha: original.alpha, space: space)
            }
            func passing(_ lightness: Double) -> LumenColor? {
                guard let candidate = color(lightness), passes(candidate),
                      let encoded = LumenColor(hex: candidate.hexString), passes(encoded) else { return nil }
                return candidate
            }
            if let candidate = passing(lab.l) { return candidate }
            // Locate the full in-gamut interval before searching. At fixed hue/chroma, the two
            // endpoints are its darkest and lightest representable colors, not clipped RGB.
            guard color(lab.l) != nil else { return nil }
            func boundary(toward endpoint: Double) -> Double {
                if color(endpoint) != nil { return endpoint }
                var good = lab.l, bad = endpoint
                for _ in 0..<40 {
                    let middle = (good + bad) / 2
                    if color(middle) != nil { good = middle } else { bad = middle }
                }
                return good
            }
            let lower = boundary(toward: 0), upper = boundary(toward: 1)
            var intervals: [(Double, Double)] = [(lower, upper)]
            // Each contrast requirement excludes an interval around its ground's luminance.
            // Intersect their passing intervals instead of sampling L: opposite grounds can
            // leave a very narrow passing band which a fixed grid would miss.
            for constraint in constraints {
                for base in constraint.grounds {
                    for quantized in [false, true] {
                        func measures(_ lightness: Double) -> (ratio: Double, distance: Double) {
                            guard var ink = color(lightness) else { return (0, 0) }
                            if quantized { ink = LumenColor(hex: ink.hexString)! }
                            let ground = constraint.overlayOpacity > 0
                                ? ink.composited(alpha: constraint.overlayOpacity, over: base) : base
                            ink = ink.composited(alpha: constraint.inkOpacity, over: ground)
                            return (ink.contrastRatio(against: ground, in: space), ink.perceptualDistance(to: ground, in: space))
                        }
                        var metrics: [(Double, (Double) -> Double)] = []
                        if let minimum = constraint.minimum { metrics.append((minimum, { measures($0).ratio })) }
                        if let distance = constraint.distance { metrics.append((distance, { measures($0).distance })) }
                        for (minimum, measure) in metrics {
                            var lo = lower, hi = upper
                            for _ in 0..<48 {
                                let left = lo + (hi - lo) / 3, right = hi - (hi - lo) / 3
                                if measure(left) < measure(right) { hi = right } else { lo = left }
                            }
                            let bottom = (lo + hi) / 2
                            guard measure(bottom) < minimum else { continue }
                            var allowed: [(Double, Double)] = []
                            if measure(lower) >= minimum {
                                var good = lower, bad = bottom
                                for _ in 0..<48 {
                                    let middle = (good + bad) / 2
                                    if measure(middle) >= minimum { good = middle } else { bad = middle }
                                }
                                allowed.append((lower, good))
                            }
                            if measure(upper) >= minimum {
                                var bad = bottom, good = upper
                                for _ in 0..<48 {
                                    let middle = (good + bad) / 2
                                    if measure(middle) >= minimum { good = middle } else { bad = middle }
                                }
                                allowed.append((good, upper))
                            }
                            intervals = intervals.flatMap { interval in
                                allowed.compactMap { permitted in
                                    let start = max(interval.0, permitted.0), end = min(interval.1, permitted.1)
                                    return start <= end ? (start, end) : nil
                                }
                            }
                            if intervals.isEmpty { return nil }
                        }
                    }
                }
            }
            var best: (lightness: Double, color: LumenColor)?
            for interval in intervals {
                let nearest = min(interval.1, max(interval.0, lab.l))
                let middle = (interval.0 + interval.1) / 2
                // The midpoint also protects a boundary from floating-point roundoff.
                for position in [nearest, middle, interval.0, interval.1] {
                    guard let candidate = passing(position) else { continue }
                    var good = position, bad = lab.l, found = candidate
                    for _ in 0..<28 {
                        let midpoint = (good + bad) / 2
                        if let value = passing(midpoint) { good = midpoint; found = value } else { bad = midpoint }
                    }
                    if best == nil || abs(good - lab.l) < abs(best!.lightness - lab.l) { best = (good, found) }
                }
            }
            return best?.color
        }
        if let candidate = atChroma(chroma) { return candidate }
        guard !preservesChroma, chroma > 0 else { return nil }
        // Chroma is reduced only after exhausting lightness at the original chroma. Prefer the
        // greatest passing chroma, then the nearest lightness at that chroma.
        var failing = chroma
        for step in 1...32 {
            let c = chroma * (1 - Double(step) / 32)
            if var candidate = atChroma(c) {
                var good = c
                for _ in 0..<12 {
                    let middle = (failing + good) / 2
                    if let found = atChroma(middle) { good = middle; candidate = found } else { failing = middle }
                }
                return candidate
            }
            failing = c
        }
        return nil
    }

    /// OKLab's inverse, converted to the theme's RGB space before checking gamut. No channel
    /// clipping: it would silently change hue/chroma and defeat the lightness-only contract.
    internal static func oklchColor(lightness: Double, chroma: Double, hue: Double, alpha: Double,
                                   space: LumenColorSpace) -> LumenColor? {
        let a = chroma * cos(hue), b = chroma * sin(hue)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        var r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        var g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        var blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        if space == .displayP3 {
            // Invert precisely the matrix used by LumenColor.oklab(in:), including its
            // rounded coefficients, so P3 white and gamut-edge colors round-trip.
            let determinant = 1.2249401763 * 1.0420569547 - 0.2249401763 * 0.0420569547
            let red = (1.0420569547 * r + 0.2249401763 * g) / determinant
            let green = (0.0420569547 * r + 1.2249401763 * g) / determinant
            blue = (blue + 0.0196375546 * red + 0.0786360456 * green) / 1.0982736002
            r = red; g = green
        }
        let tolerance = 0.0000002
        guard [r, g, blue].allSatisfy({ $0.isFinite && $0 >= -tolerance && $0 <= 1 + tolerance }) else { return nil }
        func encoded(_ value: Double) -> Double {
            let value = min(1, max(0, value)) // Only inverse-matrix floating-point roundoff.
            return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        }
        return LumenColor(red: encoded(r), green: encoded(g), blue: encoded(blue), alpha: alpha)
    }
}
