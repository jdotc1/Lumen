import AppKit
import SwiftUI
import LumenConformance
import LumenUI

/// `LUMEN_STRESS=1`: opens each archetype window in turn, cycles it through minimum size, default
/// size, 1.3 text scale, inactive state and both chrome styles, runs `windowStructure(kind:)`,
/// `narrowSizing` and `truncation` where a check can render the state, writes a JSON and a Markdown
/// report, then quits. Faults the unified log attributes to the process are counted per window.
@MainActor
enum CatalogStress {
    static let environment = ProcessInfo.processInfo.environment
    static var isEnabled: Bool { environment["LUMEN_STRESS"] == "1" }

    struct StepResult: Codable {
        /// `headless` runs the conformance checks on a hosted view; `live` drives the real window.
        let mode: String
        let name: String
        var findings: [String]
    }

    struct WindowResult: Codable {
        let kind: String
        var steps: [StepResult] = []
        var faults = 0
        var openedAt: Date?
        var closedAt: Date?
        var findingCount: Int { steps.reduce(0) { $0 + $1.findings.count } }
    }

    struct Report: Codable {
        let pid: Int32
        let macOS: String
        let startedAt: Date
        var windows: [WindowResult]
        var faultsOutsideWindows = 0
        var faultNote: String
        var findingCount: Int { windows.reduce(0) { $0 + $1.findingCount } }
        var faultCount: Int { windows.reduce(faultsOutsideWindows) { $0 + $1.faults } }
    }

    struct Subject {
        let name: String
        let kind: LumenConformance.WindowKind
        let minimumSize: CGSize
        let defaultSize: CGSize
        let window: (_ scale: Double, _ chrome: LumenChromeStyle) -> AnyView
        /// A title to match, or nil to take the first new titled window (titles follow content).
        let title: String?
        let open: () -> Void
    }

    // MARK: Subjects

    static func subjects(openWindow: @escaping (String) -> Void, newDocument: @escaping () -> Void) -> [Subject] {
        [
            Subject(name: "Workspace window", kind: .workspace, minimumSize: SampleWorkspace.minimumSize, defaultSize: SampleWorkspace.defaultSize,
                    window: { scale, chrome in AnyView(SampleWorkspace().lumenTextScale(scale).lumenChromeStyle(chrome)) },
                    title: nil, open: { openWindow("sample-workspace") }),
            Subject(name: "Utility window", kind: .utility, minimumSize: CatalogUtilityWindow.minimumSize, defaultSize: CatalogUtilityWindow.defaultSize,
                    window: { scale, chrome in AnyView(CatalogUtilityWindow().lumenTextScale(scale).lumenChromeStyle(chrome)) },
                    title: nil, open: { openWindow("utility") }),
            Subject(name: "Library window", kind: .library, minimumSize: CatalogLibraryWindow.minimumSize, defaultSize: CatalogLibraryWindow.defaultSize,
                    window: { scale, chrome in AnyView(CatalogLibraryWindow().lumenTextScale(scale).lumenChromeStyle(chrome)) },
                    title: nil, open: { openWindow("library") }),
            Subject(name: "Document window", kind: .document, minimumSize: CatalogDocumentWindow.minimumSize, defaultSize: CatalogDocumentWindow.defaultSize,
                    window: { scale, chrome in
                        AnyView(CatalogDocumentWindow(document: CatalogTextDocument(text: "Stress sample")).lumenTextScale(scale).lumenChromeStyle(chrome))
                    },
                    title: nil, open: newDocument),
        ]
    }

    // MARK: Headless steps

    static func headlessSteps(for subject: Subject) -> [StepResult] {
        let steps: [(name: String, size: CGSize, scale: Double, chrome: LumenChromeStyle)] = [
            ("minimum size", subject.minimumSize, 1, .drawn),
            ("default size", subject.defaultSize, 1, .drawn),
            ("text scale 1.3 at minimum size", subject.minimumSize, 1.3, .drawn),
            ("chrome drawn at minimum size", subject.minimumSize, 1, .drawn),
            ("chrome glass at minimum size", subject.minimumSize, 1, .glass),
        ]
        return steps.map { step in
            let view = { subject.window(step.scale, step.chrome) }
            var findings = LumenConformance.windowStructure(kind: subject.kind, sizes: [step.size], window: view)
                .map { "windowStructure · \($0)" }
            findings += LumenConformance.truncation(sizes: [step.size], of: view).map { "truncation · \($0)" }
            findings += LumenConformance.narrowSizing([(subject.name, view())], referenceWidth: step.size.width)
                .map { "narrowSizing · \($0)" }
            return StepResult(mode: "headless", name: step.name, findings: findings)
        }
    }

    // MARK: Live steps

    static func pump(_ seconds: Double = 0.5) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    static func geometryIssues(_ view: NSView, path: String = "") -> [String] {
        var issues: [String] = []
        let here = path + "/" + String(describing: type(of: view))
        for rect in [view.frame, view.bounds] {
            let valid = rect.origin.x.isFinite && rect.origin.y.isFinite && rect.size.width.isFinite
                && rect.size.height.isFinite && rect.size.width >= 0 && rect.size.height >= 0
            if !valid { issues.append("invalid geometry \(rect) at \(here)") }
        }
        for child in view.subviews { issues += geometryIssues(child, path: here) }
        return issues
    }

    static func liveStep(_ name: String, window: NSWindow, expectedContent: CGSize?, minimum: CGSize) -> StepResult {
        var findings = geometryIssues(window.contentView ?? NSView()).prefix(5).map { "geometry · \($0)" }
        let size = window.contentRect(forFrameRect: window.frame).size
        if size.width < minimum.width - 0.5 || size.height < minimum.height - 0.5 {
            findings.append("size · content \(Int(size.width))×\(Int(size.height)) is under the \(Int(minimum.width))×\(Int(minimum.height)) minimum")
        }
        if let expected = expectedContent, size.width < expected.width - 0.5 || size.height < expected.height - 0.5 {
            // A window may only grow past a request, never come up short of it.
            findings.append("size · asked for \(Int(expected.width))×\(Int(expected.height)), got \(Int(size.width))×\(Int(size.height))")
        }
        return StepResult(mode: "live", name: name, findings: Array(findings))
    }

    static func newWindow(since known: Set<Int>, title: String?) -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && window.styleMask.contains(.titled) && !known.contains(window.windowNumber)
                && (title == nil || window.title == title)
        }
    }

    static func driveLive(_ subject: Subject, catalogWindow: NSWindow?) async -> (steps: [StepResult], opened: Date, closed: Date) {
        let known = Set(NSApp.windows.map(\.windowNumber))
        let opened = Date()
        subject.open()
        var window: NSWindow?
        for _ in 0..<20 {
            await pump(0.2)
            window = newWindow(since: known, title: subject.title)
            if window != nil { break }
        }
        guard let window else {
            return ([StepResult(mode: "live", name: "open", findings: ["window · \(subject.name) did not open within 4 s"])], opened, Date())
        }
        var steps: [StepResult] = []
        func resize(_ name: String, to size: CGSize) async {
            window.setContentSize(size)
            await pump()
            steps.append(liveStep(name, window: window, expectedContent: size, minimum: subject.minimumSize))
        }
        await resize("minimum size", to: subject.minimumSize)
        await resize("default size", to: subject.defaultSize)
        for chrome in [LumenChromeStyle.glass, .drawn] {
            CatalogChromeOverride.shared.style = chrome
            await pump()
            steps.append(liveStep("chrome \(chrome.rawValue) at default size", window: window, expectedContent: nil, minimum: subject.minimumSize))
        }
        CatalogChromeOverride.shared.style = nil
        await resize("minimum size again", to: subject.minimumSize)
        // Inactive: another window of the app takes key.
        catalogWindow?.makeKeyAndOrderFront(nil)
        await pump()
        var inactive = liveStep("inactive", window: window, expectedContent: nil, minimum: subject.minimumSize)
        if window.isKeyWindow { inactive.findings.append("state · the window is still key; inactive state was not reached") }
        steps.append(inactive)
        window.makeKeyAndOrderFront(nil)
        await resize("restored to default size", to: subject.defaultSize)
        window.close()
        await pump(0.3)
        return (steps, opened, Date())
    }

    // MARK: Faults

    /// AppKit's "Invalid view geometry" faults for this process, one date per fault.
    static func faultDates(pid: Int32, since: Date) -> [Date] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--style", "ndjson", "--start", formatter.string(from: since.addingTimeInterval(-2)),
                             "--predicate", "processID == \(pid) AND subsystem == \"com.apple.runtime-issues\" AND eventMessage CONTAINS \"negative\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let stamp = object["timestamp"] as? String else { return nil }
            return parser.date(from: stamp)
        }
    }

    // MARK: Run

    static func run(openWindow: @escaping (String) -> Void, newDocument: @escaping () -> Void) async {
        let started = Date()
        let pid = ProcessInfo.processInfo.processIdentifier
        let catalogWindow = NSApp.windows.first { $0.styleMask.contains(.titled) && $0.isVisible }
        var results: [WindowResult] = []
        for subject in subjects(openWindow: openWindow, newDocument: newDocument) {
            var result = WindowResult(kind: subject.name)
            result.steps = headlessSteps(for: subject)
            let live = await driveLive(subject, catalogWindow: catalogWindow)
            result.steps += live.steps
            result.openedAt = live.opened
            result.closedAt = live.closed
            results.append(result)
        }
        await pump(2)   // let the unified log flush
        var report = Report(pid: pid, macOS: ProcessInfo.processInfo.operatingSystemVersionString, startedAt: started,
                            windows: results,
                            faultNote: "Counts are AppKit runtime-issue faults whose message contains \"negative\", from /usr/bin/log for this PID, bucketed by the interval each window was open. These counts describe process-level native geometry faults.")
        for date in faultDates(pid: pid, since: started) {
            if let index = report.windows.firstIndex(where: { ($0.openedAt ?? .distantFuture) <= date && date <= ($0.closedAt ?? .distantPast) }) {
                report.windows[index].faults += 1
            } else {
                report.faultsOutsideWindows += 1
            }
        }
        write(report)
        NSApp.terminate(nil)
    }

    static func markdown(_ report: Report) -> String {
        var text = "# Lumen Catalog stress report\n\nmacOS \(report.macOS) · PID \(report.pid) · \(report.findingCount) conformance findings · \(report.faultCount) AppKit negative-geometry faults\n"
        for window in report.windows {
            text += "\n## \(window.kind)\n\n\(window.findingCount) findings, \(window.faults) faults while open\n\n| Mode | Step | Findings |\n|---|---|---|\n"
            for step in window.steps {
                let detail = step.findings.isEmpty ? "clean" : step.findings.joined(separator: "<br>")
                text += "| \(step.mode) | \(step.name) | \(detail) |\n"
            }
        }
        text += "\nFaults outside any window: \(report.faultsOutsideWindows)\n\n\(report.faultNote)\n"
        return text
    }

    static func write(_ report: Report) {
        let directory = URL(fileURLWithPath: environment["LUMEN_STRESS_DIR"] ?? NSTemporaryDirectory()).appending(path: "lumen-stress")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = directory.appending(path: "stress-report.json")
        let markdown = directory.appending(path: "stress-report.md")
        try? encoder.encode(report).write(to: json)
        try? Data(Self.markdown(report).utf8).write(to: markdown)
        print("Stress report: \(markdown.path)\nStress report JSON: \(json.path)\nFindings: \(report.findingCount), faults: \(report.faultCount)")
        fflush(stdout)
    }
}

/// Overview status for the package's macOS 27.0 minimum deployment target.
struct CatalogOSBanner: View {
    static let gates = ["Liquid Glass chrome", "native toolbar priorities", "document scene API", "window corner radii", "native menu image visibility"]
    private var version: OperatingSystemVersion { ProcessInfo.processInfo.operatingSystemVersion }
    private var meetsFloor: Bool { version.majorVersion >= 27 }

    var body: some View {
        let running = "macOS \(version.majorVersion).\(version.minorVersion)"
        LumenBanner(meetsFloor ? "Floor 27.0 · " + Self.gates.joined(separator: ", ") + "."
                               : "Lumen's floor is 27.0; \(Self.gates.joined(separator: ", ")) need it.",
                    title: "\(running): macOS 27 gates \(meetsFloor ? "active" : "inactive")",
                    tone: meetsFloor ? .info : .warning)
    }
}
