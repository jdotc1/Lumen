import Foundation
import LumenTokens

/// Report formats are scoped to these commands; future export formats have a separate dispatch.
enum ReportFormat: String { case text, markdown, json }

struct ReportInput {
    let themes: [String: LumenTheme]
    let collection: Bool

    init(_ argument: String, registry: LumenRegistry) throws {
        let source: [LumenTheme]
        if let builtin = registry.theme(id: argument) {
            source = [builtin]
            collection = false
        } else {
            let data = try Data(contentsOf: URL(fileURLWithPath: argument))
            collection = (try JSONSerialization.jsonObject(with: data)) is [Any]
            source = collection ? try JSONDecoder().decode([LumenTheme].self, from: data)
                                : [try JSONDecoder().decode(LumenTheme.self, from: data)]
        }
        var byID: [String: LumenTheme] = [:]
        for theme in source {
            guard theme.schemaVersion <= LumenTheme.currentSchemaVersion else {
                throw ReportError("needs a newer Lumen (theme format \(theme.schemaVersion))")
            }
            guard byID.updateValue(theme, forKey: theme.id) == nil else {
                throw ReportError("duplicate theme id \(theme.id)")
            }
        }
        var flattened: [String: LumenTheme] = [:]
        for theme in source {
            flattened[theme.id] = try theme.flattened { byID[$0] ?? registry.theme(id: $0) }
        }
        themes = flattened
    }
}

struct ReportError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct ValueChange: Encodable {
    let appearance: String
    let kind: String
    let path: String
    let before: String?
    let after: String?
}

struct ContrastValue: Encodable {
    let ratio: Double
    let minimum: Double
    let passes: Bool
    init(_ measurement: LumenContrastMeasurement) {
        ratio = measurement.ratio
        minimum = measurement.minimum
        passes = measurement.passes
    }
}

struct ContrastRow: Encodable {
    let appearance: String
    let rule: String
    let foreground: String
    let ground: String
    let context: String
    let before: ContrastValue?
    let after: ContrastValue?
}

struct ThemeReport: Encodable {
    let theme: String
    let status: String
    let changes: [ValueChange]
    let contrast: [ContrastRow]
}

func appearances(_ theme: LumenTheme?) -> [LumenAppearance] {
    guard let theme else { return [] }
    return theme.supportedAppearances.flatMap { dark in
        let high = (dark ? theme.darkHighContrast : theme.lightHighContrast) != nil
        return ([false] + (high ? [true] : [])).map { LumenAppearance(isDark: dark, isHighContrast: $0) }
    }
}

func metricLeaves(_ theme: LumenTheme?) throws -> [String: String] {
    guard let metrics = theme?.metrics else { return [:] }
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics))
    var result: [String: String] = [:]
    func visit(_ value: Any, path: String) {
        if let dictionary = value as? [String: Any], !dictionary.isEmpty {
            for (key, child) in dictionary { visit(child, path: path + "." + key) }
        } else { result[path] = String(describing: value) }
    }
    visit(object, path: "metrics")
    return result
}

func contrastRows(_ before: LumenTheme?, _ after: LumenTheme?, appearance: LumenAppearance,
                  changed: Set<String>?, registry: LumenRegistry) -> [ContrastRow] {
    func measurements(_ theme: LumenTheme?) -> [LumenContrastMeasurement] {
        guard let theme, appearances(theme).contains(appearance) else { return [] }
        return LumenValidator.contrastMeasurements(for: theme, appearance: appearance, in: registry)
    }
    let old = Dictionary(uniqueKeysWithValues: measurements(before).map { ($0.key, $0) })
    let new = Dictionary(uniqueKeysWithValues: measurements(after).map { ($0.key, $0) })
    return Set(old.keys).union(new.keys).sorted().compactMap { key in
        guard let measurement = new[key] ?? old[key] else { return nil }
        if let changed, !changed.contains(measurement.foreground.rawValue), !changed.contains(measurement.ground.rawValue),
           old[key]?.ratio == new[key]?.ratio { return nil }
        return ContrastRow(appearance: appearance.description, rule: key, foreground: measurement.foreground.rawValue,
                           ground: measurement.ground.rawValue, context: measurement.context,
                           before: old[key].map(ContrastValue.init), after: new[key].map(ContrastValue.init))
    }
}

func diffReports(_ a: ReportInput, _ b: ReportInput, registry: LumenRegistry) throws -> [ThemeReport] {
    let pairs: [(String, LumenTheme?, LumenTheme?)]
    if !a.collection, !b.collection, let old = a.themes.values.first, let new = b.themes.values.first {
        pairs = [(old.id == new.id ? old.id : "\(old.id) → \(new.id)", old, new)]
    } else {
        pairs = Set(a.themes.keys).union(b.themes.keys).sorted().map { ($0, a.themes[$0], b.themes[$0]) }
    }
    return try pairs.compactMap { id, old, new in
        var changes: [ValueChange] = []
        var contrast: [ContrastRow] = []
        func add(_ appearance: String, _ path: String, _ before: String?, _ after: String?) {
            guard before != after else { return }
            changes.append(ValueChange(appearance: appearance, kind: before == nil ? "added" : after == nil ? "removed" : "changed",
                                       path: path, before: before, after: after))
        }
        for appearance in LumenAppearance.all where appearances(old).contains(appearance) || appearances(new).contains(appearance) {
            let oldPresent = appearances(old).contains(appearance)
            let newPresent = appearances(new).contains(appearance)
            let oldColors = oldPresent ? old?.palette(for: appearance).colors ?? [:] : [:]
            let newColors = newPresent ? new?.palette(for: appearance).colors ?? [:] : [:]
            var changed: Set<String> = []
            let keys = Set(oldColors.keys).union(newColors.keys).union(registry.tokens.map(\.rawValue))
            for key in keys.sorted() {
                let token = LumenToken(key)
                let before: String?
                let after: String?
                // Preserve declaration additions/removals even when a default draws the same color.
                if (oldColors[key] == nil) != (newColors[key] == nil) {
                    before = oldColors[key]?.hexString
                    after = newColors[key]?.hexString
                } else {
                    before = oldPresent ? old?.color(token, for: appearance, in: registry).hexString : nil
                    after = newPresent ? new?.color(token, for: appearance, in: registry).hexString : nil
                }
                if before != after { changed.insert(key); add(appearance.description, key, before, after) }
            }
            contrast += contrastRows(old, new, appearance: appearance, changed: changed, registry: registry)
        }
        let oldMetrics = try metricLeaves(old), newMetrics = try metricLeaves(new)
        for key in Set(oldMetrics.keys).union(newMetrics.keys).sorted() {
            add("all", key, oldMetrics[key], newMetrics[key])
        }
        add("all", "colorSpace", old?.colorSpace.rawValue, new?.colorSpace.rawValue)
        add("all", "highContrast", old.map { String($0.isHighContrast) }, new.map { String($0.isHighContrast) })
        guard !changes.isEmpty || !contrast.isEmpty || old == nil || new == nil else { return nil }
        return ThemeReport(theme: id, status: old == nil ? "added" : new == nil ? "removed" : "changed", changes: changes, contrast: contrast)
    }
}

func contrastReports(_ input: ReportInput, registry: LumenRegistry) -> [ThemeReport] {
    input.themes.keys.sorted().compactMap { id in
        guard let theme = input.themes[id] else { return nil }
        let rows = appearances(theme).flatMap { contrastRows(nil, theme, appearance: $0, changed: nil, registry: registry) }
            .sorted { lhs, rhs in
                if lhs.after?.passes != rhs.after?.passes { return lhs.after?.passes == false }
                if lhs.appearance != rhs.appearance { return lhs.appearance < rhs.appearance }
                return lhs.rule < rhs.rule
            }
        return ThemeReport(theme: id, status: "contrast", changes: [], contrast: rows)
    }
}

func render(_ reports: [ThemeReport], format: ReportFormat) throws -> String {
    if format == .json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(reports), as: UTF8.self) + "\n"
    }
    func safe(_ value: String) -> String {
        guard format == .markdown else { return value }
        return value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "|", with: "&#124;")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "`", with: "&#96;")
    }
    func value(_ value: ContrastValue?) -> String {
        guard let value else { return "absent" }
        return String(format: "%.2f:1 %@ (minimum %.2f:1)", locale: Locale(identifier: "en_US_POSIX"),
                      value.ratio, value.passes ? "PASS" : "FAIL", value.minimum)
    }
    var lines: [String] = []
    for report in reports {
        lines.append((format == .markdown ? "##### " : "") + safe(report.theme) + " (\(report.status))")
        for change in report.changes {
            lines.append("- [\(change.appearance)] \(safe(change.path)) (\(change.kind)): \(safe(change.before ?? "absent")) → \(safe(change.after ?? "absent"))")
        }
        for row in report.contrast {
            let label = "[\(row.appearance)] \(safe(row.foreground)) on \(safe(row.ground)) (\(row.context))"
            let delta = report.status == "contrast" ? value(row.after) : value(row.before) + " → " + value(row.after)
            lines.append("- \(label): \(delta)")
        }
        lines.append("")
    }
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
}

func runReport(_ command: String, arguments: [String], registry: LumenRegistry) throws {
    var inputs: [String] = []
    var format = ReportFormat.text
    var index = 0
    var sawFormat = false
    while index < arguments.count {
        if arguments[index] == "--format" {
            guard !sawFormat, index + 1 < arguments.count, let parsed = ReportFormat(rawValue: arguments[index + 1]) else {
                throw ReportError("--format requires text, markdown, or json")
            }
            sawFormat = true; format = parsed; index += 2
        } else {
            inputs.append(arguments[index]); index += 1
        }
    }
    guard inputs.count == (command == "diff" ? 2 : 1) else {
        throw ReportError(command == "diff" ? "usage: lumen-theme diff <a> <b> [--format markdown|json]" :
                          "usage: lumen-theme contrast <theme> [--format markdown|json]")
    }
    let a = try ReportInput(inputs[0], registry: registry)
    let reports = command == "diff" ? try diffReports(a, ReportInput(inputs[1], registry: registry), registry: registry)
                                     : contrastReports(a, registry: registry)
    print(try render(reports, format: format), terminator: "")
}
