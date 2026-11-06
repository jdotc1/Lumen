import Foundation
import Synchronization

/// Test-only scope for expanding package-owned strings while a headless host lays out its views.
/// The process-wide scope also covers AppKit run-loop callbacks during synchronous rendering.
@_spi(LumenLocalizationChecks)
public enum LumenLocalization {
    // A dedicated stress process opts in before cached built-in descriptors initialize.
    private static let pseudoLocale = Mutex(ProcessInfo.processInfo.environment["LUMEN_PSEUDO_LOCALE"] == "1")

    @MainActor
    public static func withPseudoLocale<Result>(_ enabled: Bool, _ body: () throws -> Result) rethrows -> Result {
        let previous = pseudoLocale.withLock { value in
            let previous = value
            value = enabled
            return previous
        }
        defer { pseudoLocale.withLock { $0 = previous } }
        return try body()
    }

    static func resolved(_ value: String) -> String {
        guard pseudoLocale.withLock({ $0 }), !value.isEmpty else { return value }
        let count = max(3, Int(ceil(Double(value.count) * 1.3)) - value.count)
        // Preserve interpolated app data; only the diagnostic padding introduces accented glyphs.
        return "[" + value + String(repeating: "é", count: count - 2) + "]"
    }
}

/// Resolve through the package catalog first, then apply the opt-in headless stress transform.
func lumenLocalized(_ value: String) -> String {
    LumenLocalization.resolved(value)
}
