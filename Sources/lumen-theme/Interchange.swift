import Foundation
import LumenTokens

/// Import/export formats are independent of the report commands' --format values.
func runInterchange(_ command: String, arguments: [String], registry: LumenRegistry) throws {
    var inputs: [String] = []
    var format: String?
    var output: String?
    var all = false
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--format", "-o":
            guard index + 1 < arguments.count else { throw ReportError("\(argument) requires a value") }
            if argument == "--format" {
                guard format == nil else { throw ReportError("--format may only be supplied once") }
                format = arguments[index + 1]
            } else {
                guard output == nil, command == "import" else { throw ReportError("-o is only accepted once, for import") }
                output = arguments[index + 1]
            }
            index += 2
        case "--all":
            guard !all, command == "export" else { throw ReportError("--all is only accepted once, for export") }
            all = true; index += 1
        default:
            guard !argument.hasPrefix("-") else { throw ReportError("unknown option \(argument)") }
            inputs.append(argument); index += 1
        }
    }
    if command == "import" {
        guard format == "dtcg", inputs.count == 1 else { throw ReportError("usage: lumen-theme import --format dtcg <file> [-o <theme.json>]") }
        let result = try LumenDTCG.importTheme(Data(contentsOf: URL(fileURLWithPath: inputs[0])), in: registry)
        for issue in result.issues {
            printError("\(issue.severity == .error ? "error" : "warning") [\(issue.appearance)] \(issue.message)")
        }
        guard !result.issues.contains(where: { $0.severity == .error }) else { throw ReportError("imported theme failed validation; no output written") }
        if let output { try result.themeJSON.write(to: URL(fileURLWithPath: output), options: .atomic) }
        else { FileHandle.standardOutput.write(result.themeJSON) }
        return
    }
    if format == nil, !all, inputs.count == 1 {
        try LumenExport.write(registry, to: URL(fileURLWithPath: inputs[0], isDirectory: true))
        print("wrote \(LumenExport.fileNames.themes), \(LumenExport.fileNames.schema), \(LumenExport.fileNames.reference) to \(inputs[0])")
        return
    }
    guard format == "dtcg" || format == "css" else { throw ReportError("export --format requires dtcg or css") }
    if format == "css" {
        guard !all, inputs.count == 2 else { throw ReportError("usage: lumen-theme export --format css <theme> <file>") }
        let source = try interchangeInput(inputs[0], registry: registry)
        try LumenCSS.export(source.theme, in: registry).write(to: URL(fileURLWithPath: inputs[1]), atomically: true, encoding: .utf8)
        return
    }
    guard (inputs.count == 1) || (inputs.count == 2 && !all) else {
        throw ReportError("usage: lumen-theme export --format dtcg [<theme>|--all] <dir>")
    }
    let directory = URL(fileURLWithPath: inputs[inputs.count - 1], isDirectory: true)
    let sources: [(theme: LumenTheme, bytes: Data?)] = inputs.count == 2
        ? [try interchangeInput(inputs[0], registry: registry)] : registry.builtInThemes.map { ($0, nil) }
    // Encode and check every filename before creating files; theme ids cannot escape the destination.
    let files = try sources.map { source -> (String, Data) in
        let id = source.theme.id
        guard id != ".", id != "..", !id.contains("/"), !id.contains("\\"), !id.contains("\0") else {
            throw ReportError("theme id cannot be used as an export filename: \(id)")
        }
        let data = try source.bytes.map { try LumenDTCG.export(themeJSON: $0, in: registry) }
            ?? LumenDTCG.export(source.theme, in: registry)
        return (id + ".tokens.json", data)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, data) in files { try data.write(to: directory.appending(path: name), options: .atomic) }
    print("wrote \(files.count) DTCG theme files to \(directory.path)")
}

private func interchangeInput(_ argument: String, registry: LumenRegistry) throws -> (theme: LumenTheme, bytes: Data?) {
    if let theme = registry.theme(id: argument) { return (theme, nil) }
    let data = try Data(contentsOf: URL(fileURLWithPath: argument))
    let theme = try JSONDecoder().decode(LumenTheme.self, from: data)
    return (theme, data)
}
