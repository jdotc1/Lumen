import Foundation

/// Generated, publishable forms of a registry: the built-in themes as JSON, a JSON Schema for
/// theme files (editors autocomplete from it), and a Markdown token reference.
public enum LumenExport {
    public static let fileNames = (themes: "builtin-themes.json", schema: "theme.schema.json", reference: "token-reference.md")

    /// How an app names its exported files and titles them. `.lumen` is Lumen's own.
    public struct Brand: Sendable {
        public var themesFile: String
        public var schemaFile: String
        public var referenceFile: String
        public var schemaTitle: String
        public var referenceTitle: String
        /// Export only the themes the app offers (`registry.galleryThemes`) rather than every built-in.
        public var galleryThemesOnly: Bool

        public init(themesFile: String = LumenExport.fileNames.themes, schemaFile: String = LumenExport.fileNames.schema,
                    referenceFile: String = LumenExport.fileNames.reference, schemaTitle: String = "Lumen theme",
                    referenceTitle: String = "Lumen tokens", galleryThemesOnly: Bool = false) {
            self.themesFile = themesFile
            self.schemaFile = schemaFile
            self.referenceFile = referenceFile
            self.schemaTitle = schemaTitle
            self.referenceTitle = referenceTitle
            self.galleryThemesOnly = galleryThemesOnly
        }

        public static let lumen = Brand()

        /// An app's brand: `<app>-theme.schema.json`, "<App> theme", "<App> colors", its gallery themes.
        public static func app(_ name: String) -> Brand {
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
            return Brand(schemaFile: "\(slug)-theme.schema.json", schemaTitle: "\(name) theme",
                         referenceTitle: "\(name) colors", galleryThemesOnly: true)
        }
    }

    public static func builtInThemesJSON(_ registry: LumenRegistry) throws -> String {
        try builtInThemesJSON(registry, galleryThemesOnly: false)
    }

    public static func builtInThemesJSON(_ registry: LumenRegistry, galleryThemesOnly: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let themes = galleryThemesOnly ? registry.galleryThemes : registry.builtInThemes
        return String(decoding: try encoder.encode(themes), as: UTF8.self) + "\n"
    }

    public static func themeSchemaJSON(_ registry: LumenRegistry, title: String = "Lumen theme") throws -> String {
        let color: [String: Any] = ["type": "string", "pattern": "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$", "description": "#RRGGBB or #RRGGBBAA"]
        var properties: [String: Any] = [:]
        for spec in registry.specs {
            var description = spec.fallback.map { "Component role; defaults to \($0.description)." }
                ?? "Semantic role; every complete variant defines it."
            if spec.surface != .window { description += " Drawn by the \(spec.surface.rawValue) surface." }
            if !spec.summary.isEmpty { description += " \(spec.summary)." }
            properties[spec.token.rawValue] = ["$ref": "#/$defs/color", "description": description]
        }
        for (key, token) in registry.renamedKeys {
            properties[key] = ["$ref": "#/$defs/color", "deprecated": true, "description": "Renamed; loads as \(token.rawValue)."]
        }
        for key in registry.retiredKeys {
            properties[key] = ["$ref": "#/$defs/color", "deprecated": true, "description": "Retired; ignored when loading."]
        }
        let palette: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": ["$ref": "#/$defs/color"]]
        func depthEffect(opacity: [String: Any], radius: Double, y: Double) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "properties": [
                "opacity": opacity,
                "radius": ["type": "number", "minimum": 0, "maximum": 32, "default": radius],
                "y": ["type": "number", "minimum": 0, "maximum": 32, "default": y,
                      "description": "Vertical offset in points; must not exceed the resolved radius. Checked by lumen-theme validate."],
            ]]
        }
        func opacity(_ value: Double) -> [String: Any] {
            ["type": "number", "minimum": 0, "maximum": 0.6, "default": value]
        }
        func shadowOpacity(light: Double, dark: Double) -> [String: Any] {
            ["type": "object", "additionalProperties": false,
             "properties": ["light": opacity(light), "dark": opacity(dark)]]
        }
        let depth: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "description": "Optional shadow and glow values. Every field inherits independently, then uses the app's depth. Popover opacity in each appearance and radius must be at least menu's; checked by lumen-theme validate. Surface color lift is unchanged.",
            "properties": [
                "menu": depthEffect(opacity: shadowOpacity(light: 0.12, dark: 0.40), radius: 10, y: 4),
                "popover": depthEffect(opacity: shadowOpacity(light: 0.14, dark: 0.45), radius: 16, y: 6),
                "glow": ["type": "object", "additionalProperties": false, "properties": [
                    "hero": depthEffect(opacity: opacity(0.4), radius: 20, y: 4),
                    "selection": depthEffect(opacity: opacity(0.45), radius: 8, y: 0),
                ]],
            ],
        ]
        var metricProperties: [String: Any] = [
            "radiusProfile": [
                "oneOf": [["enum": ["standard", "rounded"]], ["type": "number", "minimum": 0, "maximum": 12]],
                "description": "Corner ramp: standard (4, 6, 8, 10, 12 pt), rounded (6, 8, 10, 12, 12 pt), or one uniform radius. Never exceeds half the smallest 24 pt control height.",
            ],
            "typeScale": ["type": "number", "minimum": 0.9, "maximum": 1.3,
                          "description": "Typography multiplier. Control and row boxes grow above 1; the 24 pt minimum hit target is preserved."],
            "spacingScale": ["type": "number", "minimum": 1.0, "maximum": 1.25,
                             "description": "Spacing-ramp multiplier."],
            "motion": ["enum": ["standard", "reduced", "none"],
                       "description": "Motion preset. System Reduce Motion remains authoritative."],
        ]
        metricProperties["depth"] = depth
        for key in registry.lockedMetrics { metricProperties[key.rawValue] = false }
        let metrics: [String: Any] = [
            "type": "object", "properties": metricProperties, "additionalProperties": false,
            "description": "Optional schema-2 metrics. Each omitted member inherits from the parent theme, then uses the app's metrics. Pack-locked members are forbidden; app-level overrides take precedence.",
        ]
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": title,
            "type": "object",
            "required": ["id", "name"],
            "anyOf": [["required": ["inherits"]], ["required": ["light"]], ["required": ["dark"]]],
            "properties": [
                "schemaVersion": ["type": "integer", "minimum": 1, "maximum": LumenTheme.currentSchemaVersion],
                "id": ["type": "string", "minLength": 1, "pattern": "\\S"],
                "name": ["type": "string", "minLength": 1, "pattern": "\\S"],
                "summary": ["type": "string"],
                "colorSpace": ["enum": ["srgb", "display-p3"]],
                "highContrast": ["type": "boolean",
                                 "description": "A maximum-legibility theme: components draw their Increase Contrast look for it."],
                "inherits": ["type": "string", "examples": registry.builtInThemes.map(\.id)],
                "metrics": ["$ref": "#/$defs/metrics"],
                "light": ["$ref": "#/$defs/palette"], "dark": ["$ref": "#/$defs/palette"],
                "lightHighContrast": ["$ref": "#/$defs/palette"], "darkHighContrast": ["$ref": "#/$defs/palette"],
            ],
            "$defs": ["color": color, "palette": palette, "metrics": metrics],
        ]
        let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// One table per group: tier, fallback, surface, and the value in each built-in theme.
    public static func tokenReferenceMarkdown(_ registry: LumenRegistry, title: String = "Lumen tokens") -> String {
        let themes = registry.builtInThemes
        let columns = themes.flatMap { theme in
            theme.supportedAppearances.map { isDark in (theme, isDark, "\(theme.name) \(isDark ? "dark" : "light")") }
        }
        var lines = [
            "# \(title)", "",
            "Generated by `LumenExport` from the registered packs. Do not edit by hand.", "",
            registry.groups.map { "[\($0.title)](#\($0.title.lowercased().replacingOccurrences(of: " ", with: "-")))" }.joined(separator: " · "),
            "", "## Theme metrics", "",
            "Schema 2 adds optional `metrics`; colors or an inherited color theme remain required. Each metric inherits independently. New color-only themes retain schema 1 and omit the `metrics` key; adding metrics promotes them to schema 2. Explicit version-2 files are not downgraded. App-level `.lumenMetrics` overrides take precedence.", "",
            "| Metric | Accepted values | When omitted |",
            "|---|---|---|",
            "| `radiusProfile` | `standard`: 4, 6, 8, 10, 12 pt; `rounded`: 6, 8, 10, 12, 12 pt; or a uniform number from 0 through 12 pt | Inherit, then use the app's radius ramp |",
            "| `typeScale` | 0.9–1.3 | Inherit, then use the app's typography |",
            "| `spacingScale` | 1.0–1.25 | Inherit, then use the app's spacing |",
            "| `motion` | `standard`, `reduced`, `none` | Inherit, then use the app's motion |",
            "| `depth` | Optional `menu`, `popover`, and `glow` objects (below) | Inherit every field, then use the app's depth |", "",
            "Type scales above 1 grow controls and rows along with text; smaller scales never shrink the control box or its 24 pt minimum hit target. Theme radii cannot exceed half the smallest control height. The system Reduce Motion setting still takes precedence.", "",
            "A pack may lock radius, type scale, spacing scale, motion and depth with `LumenPack.lockedMetrics`. Setting an inherited or explicit locked metric produces a validator error and prevents application; it is never silently clamped.",
        ]
        if !registry.lockedMetrics.isEmpty {
            lines += ["", "Locked by this registry: " + registry.lockedMetrics.map(\.rawValue).sorted().map { "`\($0)`" }.joined(separator: ", ") + "."]
        }
        lines += [
            "", "### Depth", "",
            "Every object and field inside `metrics.depth` is optional. `inherits` merges individual fields, including `opacity.light` and `opacity.dark`; unresolved fields keep the app's depth. Built-in themes omit depth and retain these defaults. App-level `.lumenMetrics` overrides keep their existing precedence. Surface color lift rules are unchanged.", "",
            "| Path below `metrics.depth` | Default opacity | Default radius | Default y |",
            "|---|---|---|---|",
            "| `menu` | `light`: 0.12; `dark`: 0.40 | 10 pt | 4 pt |",
            "| `popover` | `light`: 0.14; `dark`: 0.45 | 16 pt | 6 pt |",
            "| `glow.hero` | 0.4 | 20 pt | 4 pt |",
            "| `glow.selection` | 0.45 | 8 pt | 0 pt |", "",
            "Menu and popover accept `opacity: { \"light\": number, \"dark\": number }`, `radius`, and `y`. Each glow accepts numeric `opacity`, `radius`, and `y`. Opacity is 0–0.6; radius is 0–32 pt; y is 0–radius. Popover opacity in each appearance and radius must be at least menu's. `lumen-theme validate` checks these bounds after inheritance and default resolution; the schema describes the same keys and numeric bounds.", "",
            "A pack locks the entire depth declaration with `LumenPack.lockedMetrics = [.depth]`. Any explicit or inherited depth declaration, including an empty object or a neutral value, produces the existing locked-metric validator error and is refused by the theme store.",
        ]
        lines += ["", "### Built-in metric declarations", "", "| Theme | Metrics |", "|---|---|"]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for theme in themes {
            let declaration = theme.metrics.flatMap { try? encoder.encode($0) }
                .map { "`" + String(decoding: $0, as: UTF8.self) + "`" } ?? "Inherit app metrics"
            lines.append("| \(theme.name) | \(declaration) |")
        }
        for group in registry.groups {
            lines += ["", "## \(group.title)", "",
                      "| Token | Tier | Falls back to | Surface | " + columns.map(\.2).joined(separator: " | ") + " |",
                      "|---|---|---|---|" + String(repeating: "---|", count: columns.count)]
            for token in group.tokens {
                guard let spec = registry.spec(for: token) else { continue }
                let values = columns.map { theme, isDark, _ in theme.color(token, for: LumenAppearance(isDark: isDark), in: registry).hexString }
                lines.append("| `\(token.rawValue)` | \(spec.isComponent ? "component" : "semantic") | "
                             + "\(spec.fallback.map { "`\($0.description)`" } ?? "") | \(spec.surface.rawValue) | "
                             + values.joined(separator: " | ") + " |")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func write(_ registry: LumenRegistry, to directory: URL) throws {
        try write(registry, to: directory, brand: .lumen)
    }

    public static func write(_ registry: LumenRegistry, to directory: URL, brand: Brand) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try builtInThemesJSON(registry, galleryThemesOnly: brand.galleryThemesOnly)
            .write(to: directory.appending(path: brand.themesFile), atomically: true, encoding: .utf8)
        try themeSchemaJSON(registry, title: brand.schemaTitle)
            .write(to: directory.appending(path: brand.schemaFile), atomically: true, encoding: .utf8)
        try tokenReferenceMarkdown(registry, title: brand.referenceTitle)
            .write(to: directory.appending(path: brand.referenceFile), atomically: true, encoding: .utf8)
    }
}
