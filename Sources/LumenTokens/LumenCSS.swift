import Foundation

/// CSS custom properties for a theme's resolved appearances and standard metric defaults.
public enum LumenCSS {
    public static func export(_ theme: LumenTheme, in registry: LumenRegistry) throws -> String {
        try LumenDTCG.checkVersion(theme)
        let flat = try theme.flattened { registry.theme(id: $0) }
        let tokens = try LumenDTCG.mappedTokens(flat, in: registry)
        var names: Set<String> = []
        for spec in registry.specs {
            let name = property(spec.token.rawValue)
            guard name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").contains($0) }),
                  names.insert(name).inserted else {
                throw LumenDTCG.FormatError("token names do not map to unique CSS identifiers: \(spec.token.rawValue)")
            }
        }
        func declarations(_ appearance: LumenAppearance, includeMetrics: Bool) throws -> [String] {
            var result: [String] = []
            for spec in registry.specs.sorted(by: { $0.token < $1.token }) {
                let color = flat.color(spec.token, for: appearance, in: registry)
                let value = flat.colorSpace == .sRGB ? color.hexString :
                    "color(display-p3 \(decimal(color.red)) \(decimal(color.green)) \(decimal(color.blue)) / \(decimal(color.alpha)))"
                result.append("--lumen-\(property(spec.token.rawValue)): \(value);")
            }
            for token in tokens where token.path.first == "metrics" && includeMetrics {
                let value: String
                switch token.type {
                case "dimension": value = try decimal(LumenDTCG.dimension(token.value)) + "px"
                case "duration": value = try decimal(LumenDTCG.duration(token.value)) + "s"
                default: value = try decimal(LumenDTCG.number(token.value))
                }
                result.append("--lumen-\(token.path.joined(separator: "-")): \(value);")
            }
            for token in tokens where token.type == "shadow" {
                let isGlow = token.path[1] == "glow"
                guard isGlow || token.path.last == (appearance.isDark ? "dark" : "light") else { continue }
                let (opacity, radius, y) = try LumenDTCG.readShadow(token.value)
                let name = isGlow ? token.path.joined(separator: "-") : token.path.dropLast().joined(separator: "-")
                result.append("--lumen-\(name): 0px \(decimal(y))px \(decimal(radius))px 0px rgb(0 0 0 / \(decimal(opacity)));")
            }
            return result.sorted()
        }
        var lines: [String] = []
        func block(_ media: String?, _ appearance: LumenAppearance, metrics: Bool = false) throws {
            if let media { lines.append("@media \(media) {") }
            let indent = media == nil ? "" : "  "
            lines.append(indent + ":root {")
            lines += try declarations(appearance, includeMetrics: metrics).map { indent + "  " + $0 }
            lines.append(indent + "}")
            if media != nil { lines.append("}") }
        }
        let baseDark = flat.light == nil
        try block(nil, LumenAppearance(isDark: baseDark), metrics: true)
        if flat.dark != nil {
            lines.append(""); try block("(prefers-color-scheme: dark)", .dark)
        }
        if flat.lightHighContrast != nil {
            lines.append("")
            let query = flat.dark == nil ? "(prefers-contrast: more)" : "(prefers-color-scheme: light) and (prefers-contrast: more)"
            try block(query, LumenAppearance(isDark: false, isHighContrast: true))
        }
        if flat.darkHighContrast != nil {
            lines.append("")
            let query = flat.light == nil ? "(prefers-contrast: more)" : "(prefers-color-scheme: dark) and (prefers-contrast: more)"
            try block(query, LumenAppearance(isDark: true, isHighContrast: true))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func property(_ role: String) -> String { role.replacingOccurrences(of: ".", with: "-") }
    private static func decimal(_ value: Double) -> String {
        let text = String(value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
