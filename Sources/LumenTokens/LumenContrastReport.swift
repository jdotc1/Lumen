import Foundation

/// Package-shared measurements keep CLI reports on the validator's exact compositing path.
package struct LumenContrastMeasurement: Sendable {
    package let key: String
    package let foreground: LumenToken
    package let ground: LumenToken
    package let context: String
    package let ratio: Double
    package let minimum: Double
    package var passes: Bool { ratio >= minimum }
}

extension LumenValidator {
    static func measuredContrast(_ ink: LumenColor, on grounds: [LumenColor], space: LumenColorSpace) -> Double {
        grounds.map { ink.over($0).contrastRatio(against: $0, in: space) }.min() ?? 21
    }

    package static func contrastMeasurements(for theme: LumenTheme, appearance: LumenAppearance,
                                             in registry: LumenRegistry) -> [LumenContrastMeasurement] {
        let pairs = registry.specs.flatMap { spec in spec.contrast.map { (foreground: spec.token, contrast: $0) } }
            + registry.rules.compactMap { $0 as? LumenContrastPairsRule }.flatMap(\.pairs)
        let raised = Set(registry.raisedTokens)
        var result: [LumenContrastMeasurement] = []
        func append(_ foreground: LumenToken, _ requirement: LumenContrast, key: String, context: String,
                    resolution: LumenResolution = LumenResolution()) {
            let ink = theme.color(foreground, for: appearance, in: registry, resolution: resolution)
            let grounds = opaqueGrounds(requirement.ground, in: theme, appearance: appearance, registry: registry, resolution: resolution)
            result.append(LumenContrastMeasurement(key: key, foreground: foreground, ground: requirement.ground,
                context: context, ratio: measuredContrast(ink, on: grounds, space: theme.colorSpace), minimum: requirement.minimum))
        }
        for (index, pair) in pairs.enumerated() {
            append(pair.foreground, pair.contrast, key: "pair.\(index)", context: "normal")
            if raised.contains(pair.foreground) || raised.contains(pair.contrast.ground) {
                if let swapped = LumenTheme.raisedSubstitutions[pair.contrast.ground],
                   registry.contrastRequirements(of: pair.foreground).contains(where: { $0.ground == swapped && $0.minimum >= pair.contrast.minimum }) {
                    continue
                }
                append(pair.foreground, pair.contrast, key: "raised.\(index)", context: "raised",
                       resolution: LumenResolution(substitutions: LumenTheme.raisedSubstitutions))
            }
        }
        for (index, rule) in registry.rules.enumerated() {
            if let rule = rule as? LumenVisibilityRule, let minimum = rule.minimumContrast {
                append(rule.token, LumenContrast(on: rule.ground, minimum: minimum, severity: rule.severity),
                       key: "visibility.\(index)", context: "visibility")
            }
        }
        return result
    }
}
