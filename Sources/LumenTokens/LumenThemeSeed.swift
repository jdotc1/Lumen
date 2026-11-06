import Foundation

/// Paired ground preferences: every seed still follows both Light and Dark appearance.
public enum LumenSeedGround: String, CaseIterable, Sendable, Codable {
    /// Warm paper in light, the standard theme's lifted graphite grounds in dark.
    case paperGraphite
    /// White in light, the Contrast theme's black canvas and lifted charcoal wells in dark.
    case brightDeep

    public var name: String {
        switch self {
        case .paperGraphite: "Paper / Graphite"
        case .brightDeep: "Bright / Deep"
        }
    }

    public var summary: String {
        switch self {
        case .paperGraphite: "Soft paper in Light; graphite in Dark."
        case .brightDeep: "Bright white in Light; deep black in Dark."
        }
    }
}

/// A seed is returned only when its complete, serializable palettes pass every supplied pack rule.
public enum LumenThemeSeedError: Error, LocalizedError {
    case invalidHue
    case validation([LumenIssue])

    public var errorDescription: String? {
        switch self {
        case .invalidHue: "The accent hue must be finite and between 0 and 360 degrees."
        case .validation(let issues): "The seed could not produce a valid theme: " + issues.map(\.message).joined(separator: "; ")
        }
    }
}

public extension LumenTheme {
    /// Derives a self-contained theme for `registry`, including both Increase Contrast palettes.
    /// The core registry is the default; supply the editor's registry to retain app-pack palettes
    /// (for example, the code pack's syntax colors and tuned current-line ground).
    ///
    /// `accentHue` uses the familiar HSV wheel (red 0°, green 120°, blue 240°); 260° is violet.
    /// Grounds and semantic status colors come from the standard and Contrast palettes. Category
    /// hues keep their meanings and the same standard/Contrast values used by `LumenTileColors`:
    /// light tiles select white or near-black ink, and dark slate tiles lift their colored glyphs.
    /// The existing system-accent derivation supplies readable lines, quiet tints, visible selection
    /// and deep filled accents under white text, including dimmed labels and keycaps.
    ///
    /// Chromatic roles share the seed's OKLCH hue with role chroma bounded to 0.025...0.10.
    /// Contrast and status separation move lightness, never desaturate the accent.
    /// The candidate runs the validator's Fix pass before final validation. Colors are materialized
    /// and rounded to their saved hex representation first, so
    /// a successful result has every registered token and remains valid after JSON export and reload.
    /// With the code pack, the current-line band alone may move toward black or white to remain
    /// distinct from the derived selection and find tint while retaining every reader's contrast.
    /// No metric is set: the new theme retains schema 1 until a metric is edited.
    static func seeded(accentHue: Double = 260, ground: LumenSeedGround = .paperGraphite,
                       id: String = UUID().uuidString, name: String = "Seed theme",
                       in registry: LumenRegistry = .core) throws -> LumenTheme {
        guard accentHue.isFinite, (0...360).contains(accentHue) else { throw LumenThemeSeedError.invalidHue }
        var foundation = registry.theme(id: LumenThemes.standardID) ?? LumenThemes.standard
        foundation.id = id
        foundation.name = name
        foundation.summary = "\(ground.summary) Accent hue \(Int(accentHue.rounded()))°."
        switch ground {
        case .paperGraphite:
            foundation.light?[.bgCanvas] = "#FBFAF7"
        case .brightDeep:
            foundation.dark = registry.theme(id: LumenThemes.contrastID)?.dark ?? LumenThemes.contrastDark
        }

        var candidate = try foundation.seedDerived(accentHue: accentHue, in: registry)
        if registry.contains(LumenToken.Code.currentLine) {
            candidate.separateSeedCurrentLine(in: registry)
        }
        var remaining: [LumenIssue] = []
        // Recompute after each atomic repair; never retry by desaturating the entire seed.
        var fixed: Set<LumenTheme> = []
        for _ in 0..<(registry.tokens.count * seedAppearances.count) {
            // Subsequent repairs must measure the same grounds that JSON reload will draw.
            for appearance in seedAppearances {
                let saved = candidate.palette(for: appearance).colors.mapValues { LumenColor(hex: $0.hexString)! }
                candidate.setSeedPalette(LumenPalette(colors: saved), for: appearance)
            }
            remaining = LumenValidator.issues(for: candidate, in: registry)
            if remaining.isEmpty { return candidate }
            guard fixed.insert(candidate).inserted else { break }
            var next: LumenTheme?
            // Distinctness findings have no general Fix target. Here the seed owns the accent
            // side, so a same-hue/chroma lightness repair can leave semantic status colors alone.
            let distinctRepairs = seedAppearances.flatMap { appearance in
                registry.rules.compactMap { $0 as? LumenDistinctRule }.flatMap { rule in
                    rule.tokens.filter { registry.seedAccentTokens.contains($0) }.flatMap { token in
                        rule.tokens.filter { $0 != token }.compactMap { other -> LumenIssue? in
                            let color = candidate.color(token, for: appearance, in: registry)
                            let ground = candidate.color(other, for: appearance, in: registry)
                            guard color.perceptualDistance(to: ground, in: candidate.colorSpace) < rule.minimumDistance else { return nil }
                            return LumenIssue(.warning, appearance, token: token, rule.noun,
                                fix: .visibility(token: token, ground: other, minimumContrast: nil, minimumDistance: rule.minimumDistance))
                        }
                    }
                }
            }
            for issue in remaining + distinctRepairs where issue.fix != nil {
                if let result = try? LumenValidator.fix(issue, in: candidate, registry: registry), result != candidate {
                    next = result
                    break
                }
            }
            guard let next else { break }
            candidate = next
        }
        throw LumenThemeSeedError.validation(remaining)
    }
}

private let seedAppearances: [LumenAppearance] = [
    .light, .dark, LumenAppearance(isDark: false, isHighContrast: true), LumenAppearance(isDark: true, isHighContrast: true),
]

extension LumenTheme {
    /// Seed palette before repairs, also the immutable chroma baseline for the bounded chroma check.
    /// The existing derivation supplies role lightness; OKLCH supplies a common hue. A chroma
    /// ceiling leaves lightness room for contrast at all twelve hues; the floor keeps quiet
    /// tints visibly colored. Gamut accommodation moves lightness, never clips RGB channels.
    func seedDerived(accentHue: Double, in registry: LumenRegistry) throws -> LumenTheme {
        let accent = Self.seedAccent(hue: accentHue, saturation: 0.72)
        let lab = accent.oklab(in: colorSpace)
        let hue = atan2(lab.b, lab.a)
        let derived = withSystemAccent(light: accent, dark: accent, in: registry)
        let family = Set(registry.seedAccentTokens)
        var candidate = derived
        for appearance in seedAppearances {
            let colors = try Dictionary(uniqueKeysWithValues: registry.tokens.map { token in
                var color = derived.color(token == .fgLink ? .accent : token, for: appearance, in: registry)
                if family.contains(token) {
                    let role = color.oklab(in: colorSpace)
                    let chroma = min(0.10, max(0.025, hypot(role.a, role.b)))
                    let isFilled = token == .menuHighlight || registry.reaches([.menuHighlight], from: token)
                    let isSelection = token == .bgSelected || registry.reaches([.bgSelected], from: token)
                    func carriesInk(_ mapped: LumenColor) -> Bool {
                        if isSelection {
                            let saved = LumenColor(hex: mapped.hexString)!
                            let primary = self.color(.fgPrimary, for: appearance, in: registry)
                            guard primary.contrastRatio(against: saved, in: colorSpace) >= 7 else { return false }
                        }
                        guard isFilled else { return true }
                        // Re-establish the filled role's constraints after hue/chroma projection.
                        // White ink cannot get lighter: darken the fill at fixed hue/chroma.
                        let saved = LumenColor(hex: mapped.hexString)!
                        let white = LumenColor(red: 1, green: 1, blue: 1)
                        let dimmed = white.composited(alpha: 0.82, over: saved)
                        let keycap = white.composited(alpha: 0.18, over: saved)
                        return dimmed.contrastRatio(against: saved, in: colorSpace) >= 4.5
                            && white.contrastRatio(against: keycap, in: colorSpace) >= 4.5
                    }
                    // Accommodate gamut before freezing the baseline. Keep at least half the
                    // requested role chroma and never go below the quiet-tint floor. Cyan,
                    // for example, needs less chroma to support a deep fill than violet.
                    var mapped: LumenColor?
                    for reduction in 0...10 {
                        let c = max(0.025, chroma * (1 - Double(reduction) * 0.05))
                        for step in 0...1000 {
                            let delta = Double(step) / 1000
                            let positions = [role.l - delta, role.l + delta].filter { (0...1).contains($0) }
                            mapped = positions.compactMap({ LumenValidator.oklchColor(
                                lightness: $0, chroma: c, hue: hue, alpha: 1, space: colorSpace) }).first(where: carriesInk)
                            if mapped != nil { break }
                        }
                        if mapped != nil { break }
                    }
                    guard let mapped else {
                        throw LumenThemeSeedError.validation([LumenIssue(.error, appearance, token: token,
                            "No chromatic seed color can carry this role's ink.")])
                    }
                    color = mapped
                }
                return (token.rawValue, LumenColor(hex: color.hexString)!)
            })
            candidate.setSeedPalette(LumenPalette(colors: colors), for: appearance)
        }
        return candidate
    }
}

private extension LumenTheme {
    mutating func setSeedPalette(_ palette: LumenPalette, for appearance: LumenAppearance) {
        switch (appearance.isDark, appearance.isHighContrast) {
        case (false, false): light = palette
        case (true, false): dark = palette
        case (false, true): lightHighContrast = palette
        case (true, true): darkHighContrast = palette
        }
    }

    /// The code pack's tuned band predates the new accent. Keep all other entries fixed and
    /// choose the closest passing saved color along the band's black/white blend paths.
    mutating func separateSeedCurrentLine(in registry: LumenRegistry) {
        let token = LumenToken.Code.currentLine
        let distinct = registry.rules.compactMap { $0 as? LumenDistinctRule }.filter { $0.tokens.contains(token) }
        let custom = registry.rules.compactMap { $0 as? LumenCustomRule }
        let visibility = registry.rules.compactMap { $0 as? LumenVisibilityRule }
            .filter { $0.token == token || $0.ground == token }
        let lift = registry.rules.compactMap { $0 as? LumenLiftRule }
            .filter { $0.token == token || $0.ground == token }
        let readers = registry.requirements(on: token)
        for appearance in seedAppearances {
            let original = color(token, for: appearance, in: registry)
            func passes(_ candidate: LumenTheme) -> Bool {
                let band = LumenValidator.opaqueGround(token, in: candidate, appearance: appearance, registry: registry)
                guard distinct.allSatisfy({ rule in
                    rule.tokens.filter { $0 != token }.allSatisfy { other in
                        let otherColor = LumenValidator.opaqueGround(other, in: candidate, appearance: appearance, registry: registry)
                        return band.perceptualDistance(to: otherColor, in: candidate.colorSpace) >= rule.minimumDistance
                    }
                }) else { return false }
                guard readers.allSatisfy({ reader in
                    LumenValidator.contrastIssue(reader.foreground, reader.contrast, in: candidate,
                                                 appearance: appearance, registry: registry) == nil
                }) else { return false }
                guard registry.contrastRequirements(of: token).allSatisfy({ requirement in
                    LumenValidator.contrastIssue(token, requirement, in: candidate,
                                                 appearance: appearance, registry: registry) == nil
                }) else { return false }
                return custom.allSatisfy { !$0.issues(in: candidate, appearance: appearance, registry: registry).contains { $0.token == token } }
                    && visibility.allSatisfy { $0.issues(in: candidate, appearance: appearance, registry: registry).isEmpty }
                    && lift.allSatisfy { $0.issues(in: candidate, appearance: appearance, registry: registry).isEmpty }
            }
            if passes(self) { continue }
            var best: (theme: LumenTheme, distance: Double)?
            for target in [LumenColor(red: 0, green: 0, blue: 0), LumenColor(red: 1, green: 1, blue: 1)] {
                for step in 1...255 {
                    let blended = target.composited(alpha: Double(step) / 255, over: original)
                    guard let saved = LumenColor(hex: blended.hexString) else { continue }
                    var candidate = self
                    var palette = candidate.palette(for: appearance)
                    palette[token] = saved
                    candidate.setSeedPalette(palette, for: appearance)
                    guard passes(candidate) else { continue }
                    let distance = original.perceptualDistance(to: saved, in: colorSpace)
                    if best == nil || distance < best!.distance { best = (candidate, distance) }
                    break
                }
            }
            if let best { self = best.theme }
        }
    }

    static func seedAccent(hue: Double, saturation: Double) -> LumenColor {
        let sector = (hue == 360 ? 0 : hue) / 60
        let chroma = 0.85 * saturation
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let components: (Double, Double, Double)
        switch Int(sector) {
        case 0: components = (chroma, secondary, 0)
        case 1: components = (secondary, chroma, 0)
        case 2: components = (0, chroma, secondary)
        case 3: components = (0, secondary, chroma)
        case 4: components = (secondary, 0, chroma)
        default: components = (chroma, 0, secondary)
        }
        let neutral = 0.85 - chroma
        return LumenColor(red: components.0 + neutral, green: components.1 + neutral, blue: components.2 + neutral)
    }
}
