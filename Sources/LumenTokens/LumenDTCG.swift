import Foundation
import CoreFoundation

/// DTCG 2025.10 interchange. Lumen JSON remains the canonical, lossless theme format.
public enum LumenDTCG {
    public static let extensionKey = "com.jdotc1.lumen"

    public struct ImportResult: Sendable {
        public let theme: LumenTheme
        /// Original source bytes when unchanged; canonical Lumen JSON after a supported edit.
        public let themeJSON: Data
        public let issues: [LumenIssue]
    }

    /// Exports a value using Lumen's deterministic JSON encoding as its source representation.
    public static func export(_ theme: LumenTheme, in registry: LumenRegistry) throws -> Data {
        let canonical = try encode(theme)
        return try export(themeJSON: theme.sourceEncoding(matching: canonical) ?? canonical, in: registry)
    }

    /// Retains whitespace, omitted fields, hex casing and unknown source fields for an unchanged round trip.
    public static func export(themeJSON: Data, in registry: LumenRegistry) throws -> Data {
        let theme = try JSONDecoder().decode(LumenTheme.self, from: themeJSON)
        try checkVersion(theme)
        let tokens = try mappedTokens(theme, in: registry)
        var root: [String: Any] = [:]
        var baseline: [String: Any] = [:]
        for token in tokens {
            set(["$type": token.type, "$value": token.value], at: token.path, in: &root)
            baseline[token.key] = token.value
        }
        let source = try object(themeJSON)
        root["$extensions"] = [extensionKey: [
            "mappingVersion": 1, "theme": source,
            "sourceJSON": String(decoding: themeJSON, as: UTF8.self),
            "baseline": baseline,
            "packs": registry.packs.map { ["id": $0.id, "lockedMetrics": $0.lockedMetrics.map(\.rawValue).sorted()] },
        ]]
        return try json(root)
    }

    /// Imports the documented Lumen mapping, returning conversion warnings and validator findings.
    /// The caller decides whether to save a theme with errors; the CLI refuses to do so.
    public static func importTheme(_ data: Data, in registry: LumenRegistry) throws -> ImportResult {
        let root = try object(data)
        let metadata = (root["$extensions"] as? [String: Any])?[extensionKey] as? [String: Any]
        if let version = metadata?["mappingVersion"] as? Int, version != 1 {
            throw FormatError("unsupported Lumen DTCG mapping version \(version)")
        }
        let source = metadata?["theme"] as? [String: Any] ?? ["id": "imported", "name": "Imported", "light": [:]]
        let original = try JSONDecoder().decode(LumenTheme.self, from: json(source))
        try checkVersion(original)
        var theme = original
        var issues: [LumenIssue] = []
        func warn(_ path: String, _ message: String) {
            issues.append(LumenIssue(.warning, .light, token: nil, "DTCG \(path): \(message)"))
        }
        if metadata == nil { warn("$extensions", "Lumen metadata absent; using id and name Imported, without source-byte preservation") }
        let baseline = metadata?["baseline"] as? [String: Any] ?? [:]
        let flat = try original.flattened { registry.theme(id: $0) }
        let expected = try mappedTokens(flat, in: registry)
        var known = Dictionary(uniqueKeysWithValues: expected.map { ($0.key, $0) })
        // All four appearances can be added by a design tool, even when absent in the source.
        for (name, _) in variants {
            for spec in registry.specs {
                let path = [name, escaped(spec.group), escaped(spec.token.rawValue)]
                known[path.joined(separator: ".")] = Token(path: path, type: "color", value: [:])
            }
        }
        var leaves: [String: Token] = [:]
        func visit(_ group: [String: Any], path: [String], inheritedType: String?) {
            let type = group["$type"] as? String ?? inheritedType
            if let value = group["$value"] {
                let token = Token(path: path, type: type ?? "", value: value)
                leaves[token.key] = token
                return
            }
            for key in group.keys.sorted() where !key.hasPrefix("$") {
                if let child = group[key] as? [String: Any] { visit(child, path: path + [key], inheritedType: type) }
                else { warn((path + [key]).joined(separator: "."), "expected a token or group object; ignored") }
            }
        }
        visit(root, path: [], inheritedType: nil)
        func resolve(_ key: String, seen: Set<String> = []) throws -> Token {
            guard seen.count < 64, !seen.contains(key), var token = leaves[key] else {
                throw FormatError("missing or cyclic token reference \(key)")
            }
            if let reference = token.value as? String, reference.hasPrefix("{"), reference.hasSuffix("}") {
                let target = try resolve(String(reference.dropFirst().dropLast()), seen: seen.union([key]))
                token.value = target.value
                if token.type.isEmpty { token.type = target.type }
            }
            return token
        }
        var edits: [String: Token] = [:]
        for key in leaves.keys.sorted() {
            guard let mapping = known[key] else { warn(key, "unknown token path; ignored"); continue }
            do {
                let token = try resolve(key)
                guard token.type == mapping.type else {
                    warn(key, "unsupported type \(token.type.isEmpty ? "(missing)" : token.type); expected \(mapping.type); ignored")
                    continue
                }
                // The baseline records the actual exported values, independent of later registry changes.
                if let before = baseline[key], equivalent(before, token.value, type: token.type) { continue }
                edits[key] = token
            } catch { warn(key, error.localizedDescription) }
        }
        for key in baseline.keys.sorted() where leaves[key] == nil {
            warn(key, "exported token is missing; retained its Lumen declaration (omission does not delete)")
        }
        var importedSpace: LumenColorSpace?
        for key in edits.keys.sorted() {
            guard let token = edits[key], token.type == "color", token.path.count == 3,
                  let variant = variants.first(where: { $0.0 == token.path[0] }),
                  let spec = registry.specs.first(where: { escaped($0.group) == token.path[1] && escaped($0.token.rawValue) == token.path[2] }) else { continue }
            do {
                let (color, space) = try readColor(token.value)
                // Lumen has one color space for the entire theme. Never relabel existing components.
                let required = metadata == nil ? importedSpace : flat.colorSpace
                guard required == nil || required == space else { throw FormatError("mixed color spaces cannot be represented by one Lumen theme; ignored") }
                importedSpace = space
                var palette = theme[keyPath: variant.1] ?? LumenPalette()
                palette[spec.token] = color
                theme[keyPath: variant.1] = palette
            } catch { warn(key, error.localizedDescription) }
        }
        if metadata == nil, let importedSpace { theme.colorSpace = importedSpace }
        var metrics = theme.metrics ?? LumenThemeMetrics()
        var changedMetrics = false
        for name in ["typeScale", "spacingScale"] {
            if let token = edits["metrics.\(name)"] {
                do {
                    let value = try number(token.value)
                    if name == "typeScale" { metrics.typeScale = value } else { metrics.spacingScale = value }
                    changedMetrics = true
                } catch { warn(token.key, error.localizedDescription) }
            }
        }
        func acceptedValue(_ key: String) throws -> Any {
            if let edit = edits[key] { return edit.value }
            if let original = baseline[key] { return original }
            throw FormatError("missing supported token \(key)")
        }
        let radiusKeys = radiusNames.map { "metrics.radius.\($0)" }
        if radiusKeys.contains(where: { edits[$0] != nil }) {
            do {
                let values = try radiusKeys.map { key in try dimension(acceptedValue(key)) }
                if values == [4, 6, 8, 10, 12] { metrics.radiusProfile = .standard }
                else if values == [6, 8, 10, 12, 12] { metrics.radiusProfile = .rounded }
                else if Set(values).count == 1 { metrics.radiusProfile = .uniform(values[0]) }
                else { throw FormatError("radius ramp must be standard, rounded, or uniform; retained original profile") }
                changedMetrics = true
            } catch { warn("metrics.radius", error.localizedDescription) }
        }
        let motionKeys = motionNames.map { "metrics.motion.\($0)" }
        if motionKeys.contains(where: { edits[$0] != nil }) {
            do {
                let values = try motionKeys.map { key in try duration(acceptedValue(key)) }
                guard let preset = LumenThemeMetrics.Motion.allCases.first(where: { motionValues($0) == values }) else {
                    throw FormatError("durations must match a Lumen motion preset; retained original motion")
                }
                metrics.motion = preset; changedMetrics = true
            } catch { warn("metrics.motion", error.localizedDescription) }
        }
        var depthObject = try metrics.depth.map { try object(JSONEncoder().encode($0)) } ?? [:]
        var depthChanges: [String: Double] = [:]
        var conflicts: Set<String> = []
        for key in edits.keys.sorted() {
            guard let token = edits[key], token.type == "shadow" else { continue }
            do {
                let values = try readShadow(token.value)
                let old = try baseline[key].map(readShadow)
                let path = token.path
                let prefix = path[1] == "glow" ? "glow.\(path[2])" : path[1]
                let opacity = path[1] == "glow" ? "\(prefix).opacity" : "\(prefix).opacity.\(path[2])"
                for (field, value, previous) in [(opacity, values.0, old?.0), ("\(prefix).radius", values.1, old?.1), ("\(prefix).y", values.2, old?.2)] {
                    if value == previous { continue }
                    if let other = depthChanges[field], other != value { conflicts.insert(field) }
                    depthChanges[field] = value
                }
            } catch { warn(key, error.localizedDescription) }
        }
        var changedDepth = false
        for field in depthChanges.keys.sorted() {
            if conflicts.contains(field) { warn(field, "conflicting appearance values for a shared depth field; retained original"); continue }
            if let value = depthChanges[field] { set(value, at: field.components(separatedBy: "."), in: &depthObject) }
            changedMetrics = true; changedDepth = true
        }
        if changedDepth { metrics.depth = try JSONDecoder().decode(LumenThemeDepth.self, from: json(depthObject)) }
        if changedMetrics { theme.metrics = metrics }
        theme = try JSONDecoder().decode(LumenTheme.self, from: encode(theme))
        let flattened = try theme.flattened { registry.theme(id: $0) }
        issues += LumenValidator.issues(for: flattened, in: registry)
        for key in LumenTheme.unknownTopLevelKeys(in: try json(source)) {
            warn("$extensions.theme.\(key)", "unknown Lumen field; preserved in JSON but ignored by the theme")
        }
        // Exported locks are descriptive; the destination registry remains authoritative.
        if let packs = metadata?["packs"] as? [[String: Any]] {
            let locks = Set(packs.flatMap { $0["lockedMetrics"] as? [String] ?? [] })
            for key in (flattened.metrics?.keys ?? []).sorted(by: { $0.rawValue < $1.rawValue })
                where locks.contains(key.rawValue) && !registry.lockedMetrics.contains(key) {
                warn("metrics.\(key.rawValue)", "source pack locks this metric; destination registry does not enforce that lock")
            }
        }
        let canonical = try encode(theme)
        let output: Data
        if theme == original, let spelling = metadata?["sourceJSON"] as? String,
           let saved = try? JSONDecoder().decode(LumenTheme.self, from: Data(spelling.utf8)), saved == original {
            output = Data(spelling.utf8)
        } else if theme == original { output = try json(source) }
        else {
            // Overlay known fields without dropping unrecognized source metadata.
            var updated = source
            for (key, value) in try object(canonical) { updated[key] = value }
            output = try json(updated)
        }
        theme.retainSourceEncoding(output, canonical: canonical)
        return ImportResult(theme: theme, themeJSON: output, issues: issues)
    }

    struct FormatError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    struct Token {
        var path: [String]
        var type: String
        var value: Any
        var key: String { path.joined(separator: ".") }
    }

    static var variants: [(String, WritableKeyPath<LumenTheme, LumenPalette?>)] { [
        ("light", \.light), ("dark", \.dark), ("lightHighContrast", \.lightHighContrast), ("darkHighContrast", \.darkHighContrast),
    ] }
    static let radiusNames = ["xs", "sm", "md", "lg", "xl"]
    static let motionNames = ["fast", "standard", "emphasized"]

    static func checkVersion(_ theme: LumenTheme) throws {
        guard theme.schemaVersion <= LumenTheme.currentSchemaVersion else {
            throw FormatError("needs a newer Lumen (theme format \(theme.schemaVersion))")
        }
    }

    static func encode(_ theme: LumenTheme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(theme) + Data("\n".utf8)
    }

    static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
    }

    static func object(_ data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FormatError("expected a JSON object")
        }
        return result
    }

    static func equal(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? NSNumber, let b = b as? NSNumber {
            guard (CFGetTypeID(a) == CFBooleanGetTypeID()) == (CFGetTypeID(b) == CFBooleanGetTypeID()) else { return false }
            return a == b
        }
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            return a.keys.sorted() == b.keys.sorted() && a.allSatisfy { key, value in b[key].map { equal(value, $0) } == true }
        }
        if let a = a as? [Any], let b = b as? [Any] {
            return a.count == b.count && zip(a, b).allSatisfy { equal($0, $1) }
        }
        if let a = a as? String, let b = b as? String { return a == b }
        return a is NSNull && b is NSNull
    }

    static func equivalent(_ a: Any, _ b: Any, type: String) -> Bool {
        if equal(a, b) { return true }
        do {
            switch type {
            case "color":
                let old = try readColor(a), new = try readColor(b)
                return old.0 == new.0 && old.1 == new.1
            case "duration": return try duration(a) == duration(b)
            case "dimension": return try dimension(a) == dimension(b)
            case "shadow":
                let old = try readShadow(a), new = try readShadow(b)
                return old.0 == new.0 && old.1 == new.1 && old.2 == new.2
            default: return false
            }
        } catch { return false }
    }

    static func escaped(_ name: String) -> String {
        name.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: ".", with: "%2E")
            .replacingOccurrences(of: "$", with: "%24").replacingOccurrences(of: "{", with: "%7B")
            .replacingOccurrences(of: "}", with: "%7D")
    }

    static func set(_ value: Any, at path: [String], in object: inout [String: Any]) {
        guard let first = path.first else { return }
        if path.count == 1 { object[first] = value; return }
        var child = object[first] as? [String: Any] ?? [:]
        set(value, at: Array(path.dropFirst()), in: &child)
        object[first] = child
    }

    static func number(_ value: Any) throws -> Double {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else {
            throw FormatError("expected a finite number")
        }
        return n.doubleValue
    }

    static func dimension(_ value: Any) throws -> Double {
        guard let object = value as? [String: Any], object["unit"] as? String == "px", let value = object["value"] else {
            throw FormatError("only px dimensions map to Lumen points; ignored")
        }
        return try number(value)
    }

    static func duration(_ value: Any) throws -> Double {
        guard let object = value as? [String: Any], let value = object["value"],
              let unit = object["unit"] as? String, ["s", "ms"].contains(unit) else {
            throw FormatError("expected duration in s or ms")
        }
        return try number(value) / (unit == "ms" ? 1000 : 1)
    }

    static func colorValue(_ color: LumenColor, space: LumenColorSpace) -> [String: Any] {
        ["colorSpace": space.rawValue, "components": [color.red, color.green, color.blue], "alpha": color.alpha]
    }

    static func readColor(_ value: Any) throws -> (LumenColor, LumenColorSpace) {
        guard let object = value as? [String: Any], let name = object["colorSpace"] as? String,
              let space = LumenColorSpace(rawValue: name), let components = object["components"] as? [Any], components.count == 3 else {
            throw FormatError("expected srgb or display-p3 color with three numeric components")
        }
        let c = try components.map(number), alpha = try number(object["alpha"] ?? 1)
        guard (c + [alpha]).allSatisfy({ (0...1).contains($0) }) else { throw FormatError("color components and alpha must be within 0...1") }
        return (LumenColor(red: c[0], green: c[1], blue: c[2], alpha: alpha), space)
    }

    static func readShadow(_ value: Any) throws -> (Double, Double, Double) {
        guard let object = value as? [String: Any], let color = object["color"], let x = object["offsetX"],
              let y = object["offsetY"], let blur = object["blur"], let spread = object["spread"] else {
            throw FormatError("expected one shadow object; layered shadows are unsupported")
        }
        let (ink, _) = try readColor(color)
        guard ink.red == 0, ink.green == 0, ink.blue == 0, try dimension(x) == 0,
              try dimension(spread) == 0, object["inset"] == nil || object["inset"] as? Bool == false else {
            throw FormatError("Lumen depth requires neutral black, zero offsetX/spread and no inset; ignored")
        }
        return (ink.alpha, try dimension(blur), try dimension(y))
    }

    static func motionValues(_ preset: LumenThemeMetrics.Motion?) -> [Double] {
        switch preset {
        case .reduced: [0.07, 0.11, 0.16]
        case .none?: [0, 0, 0]
        default: [0.14, 0.22, 0.32]
        }
    }

    static func mappedTokens(_ theme: LumenTheme, in registry: LumenRegistry) throws -> [Token] {
        let flat = try theme.flattened { registry.theme(id: $0) }
        var tokens: [Token] = []
        for (name, keyPath) in variants where flat[keyPath: keyPath] != nil {
            let appearance = LumenAppearance(isDark: name.hasPrefix("dark"), isHighContrast: name.hasSuffix("HighContrast"))
            for spec in registry.specs {
                tokens.append(Token(path: [name, escaped(spec.group), escaped(spec.token.rawValue)], type: "color",
                                    value: colorValue(flat.color(spec.token, for: appearance, in: registry), space: flat.colorSpace)))
            }
        }
        let metrics = flat.metrics
        tokens += [Token(path: ["metrics", "typeScale"], type: "number", value: metrics?.typeScale ?? 1),
                   Token(path: ["metrics", "spacingScale"], type: "number", value: metrics?.spacingScale ?? 1)]
        let radii: [Double]
        switch metrics?.radiusProfile {
        case .standard?: radii = [4, 6, 8, 10, 12]
        case .rounded?: radii = [6, 8, 10, 12, 12]
        case .uniform(let r)?: radii = Array(repeating: r, count: 5)
        case nil: radii = [4, 6, 8, 10, 14]
        }
        for (name, value) in zip(radiusNames, radii) {
            tokens.append(Token(path: ["metrics", "radius", name], type: "dimension", value: ["value": value, "unit": "px"]))
        }
        for (name, value) in zip(motionNames, motionValues(metrics?.motion)) {
            tokens.append(Token(path: ["metrics", "motion", name], type: "duration", value: ["value": value, "unit": "s"]))
        }
        let depth = LumenDepth.resolving(metrics?.depth)
        func shadow(_ path: [String], _ opacity: Double, _ radius: Double, _ y: Double) {
            tokens.append(Token(path: ["depth"] + path, type: "shadow", value: [
                "color": colorValue(LumenColor(red: 0, green: 0, blue: 0, alpha: opacity), space: .sRGB),
                "offsetX": ["value": 0, "unit": "px"], "offsetY": ["value": y, "unit": "px"],
                "blur": ["value": radius, "unit": "px"], "spread": ["value": 0, "unit": "px"],
            ]))
        }
        for (name, value) in [("menu", depth.menu), ("popover", depth.popover)] {
            shadow([name, "light"], value.opacity.light, value.radius, value.y)
            shadow([name, "dark"], value.opacity.dark, value.radius, value.y)
        }
        shadow(["glow", "hero"], depth.glow.hero.opacity, depth.glow.hero.radius, depth.glow.hero.y)
        shadow(["glow", "selection"], depth.glow.selection.opacity, depth.glow.selection.radius, depth.glow.selection.y)
        return tokens
    }
}
