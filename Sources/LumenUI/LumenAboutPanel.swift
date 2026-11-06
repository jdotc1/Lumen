import AppKit
import SwiftUI

/// The version of the linked LumenUI library, updated by the release script.
public enum LumenLibrary {
    public static let version = "0.63.0"
}

/// Supplies Apple's standard About panel without creating a custom window.
public enum LumenAboutPanel {
    /// Builds panel contents without accessing NSApp or presenting UI.
    public static func options(
        bundle: Bundle = .main,
        copyrightHolder: String = "Lumen contributors",
        profileURL: URL = URL(string: "https://github.com/jdotc1/LumenUI")!,
        credits: String? = nil
    ) -> [NSApplication.AboutPanelOptionKey: Any] {
        let linkText = "github.com/jdotc1/LumenUI"
        var lines = [linkText, lumenLocalized(String(localized: "Built with Lumen %@", defaultValue: "Built with Lumen \(LumenLibrary.version)", bundle: .module, comment: "AboutPanel text."))]
        if let commit = bundle.object(forInfoDictionaryKey: "LumenGitCommit") as? String,
           !commit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(lumenLocalized(String(localized: "Commit %@", defaultValue: "Commit \(commit.trimmingCharacters(in: .whitespacesAndNewlines).prefix(7))", bundle: .module, comment: "AboutPanel text.")))
        }
        if let credits, !credits.isEmpty { lines.append(credits) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSMutableAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        text.addAttribute(.link, value: profileURL, range: NSRange(location: 0, length: linkText.utf16.count))
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: applicationName(bundle: bundle),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© \(year) \(copyrightHolder)",
            .credits: NSAttributedString(attributedString: text)
        ]
        // Missing keys fall back to AppKit's own defaults instead of showing "Version ".
        if let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !short.isEmpty {
            options[.applicationVersion] = short
        }
        if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !build.isEmpty {
            options[.version] = build
        }
        return options
    }

    /// Presents the standard panel. Call only in response to an app UI action.
    @MainActor
    public static func show(
        bundle: Bundle = .main,
        copyrightHolder: String = "Lumen contributors",
        profileURL: URL = URL(string: "https://github.com/jdotc1/LumenUI")!,
        credits: String? = nil
    ) {
        NSApp.orderFrontStandardAboutPanel(options: options(
            bundle: bundle, copyrightHolder: copyrightHolder, profileURL: profileURL, credits: credits))
    }

    fileprivate static func applicationName(bundle: Bundle) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }
}

/// Replaces the app menu's About item with Lumen's standard-panel contents.
public struct LumenAboutCommands: Commands {
    private let bundle: Bundle
    private let copyrightHolder: String
    private let profileURL: URL
    private let credits: String?

    public init(
        bundle: Bundle = .main,
        copyrightHolder: String = "Lumen contributors",
        profileURL: URL = URL(string: "https://github.com/jdotc1/LumenUI")!,
        credits: String? = nil
    ) {
        self.bundle = bundle
        self.copyrightHolder = copyrightHolder
        self.profileURL = profileURL
        self.credits = credits
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(lumenLocalized(String(localized: "About %@", defaultValue: "About \(LumenAboutPanel.applicationName(bundle: bundle))", bundle: .module, comment: "AboutPanel label. Values identify the item or count described."))) {
                LumenAboutPanel.show(bundle: bundle, copyrightHolder: copyrightHolder,
                                    profileURL: profileURL, credits: credits)
            }
        }
    }
}
