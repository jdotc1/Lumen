import AppKit
import SwiftUI

/// The version of the linked LumenUI library, updated by the release script.
public enum LumenLibrary {
    public static let version = "1.4.0"
}

/// One named credit line in the About panel; `url` makes the name a clickable link.
public struct LumenAboutCredit: Hashable, Sendable {
    public let name: String
    public let url: URL?

    public init(name: String, url: URL? = nil) {
        self.name = name
        self.url = url
    }
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
        options(bundle: bundle, copyrightHolder: copyrightHolder, profileURL: profileURL,
                creditsText: credits, creditLinks: [], creditsHeading: nil)
    }

    /// Builds panel contents with one line per credit; a credit with a URL is a clickable link
    /// and one without is plain text. A nonempty `creditsHeading` precedes the list after a blank line.
    public static func options(
        bundle: Bundle = .main,
        copyrightHolder: String = "Lumen contributors",
        profileURL: URL = URL(string: "https://github.com/jdotc1/LumenUI")!,
        credits: [LumenAboutCredit],
        creditsHeading: String? = nil
    ) -> [NSApplication.AboutPanelOptionKey: Any] {
        options(bundle: bundle, copyrightHolder: copyrightHolder, profileURL: profileURL,
                creditsText: nil, creditLinks: credits, creditsHeading: creditsHeading)
    }

    private static func options(
        bundle: Bundle,
        copyrightHolder: String,
        profileURL: URL,
        creditsText: String?,
        creditLinks: [LumenAboutCredit],
        creditsHeading: String?
    ) -> [NSApplication.AboutPanelOptionKey: Any] {
        let linkText = "github.com/jdotc1/LumenUI"
        // Each line carries its own optional link, so link ranges follow the text exactly
        // whatever the credit names or localized lines contain.
        var lines: [(text: String, link: URL?)] = [
            (linkText, profileURL),
            (lumenLocalized(String(localized: "Built with Lumen %@", defaultValue: "Built with Lumen \(LumenLibrary.version)", bundle: .module, comment: "AboutPanel text.")), nil)
        ]
        if let commit = bundle.object(forInfoDictionaryKey: "LumenGitCommit") as? String,
           !commit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append((lumenLocalized(String(localized: "Commit %@", defaultValue: "Commit \(commit.trimmingCharacters(in: .whitespacesAndNewlines).prefix(7))", bundle: .module, comment: "AboutPanel text.")), nil))
        }
        if let creditsText, !creditsText.isEmpty { lines.append((creditsText, nil)) }
        let named = creditLinks.filter { !$0.name.isEmpty }
        if !named.isEmpty, let creditsHeading, !creditsHeading.isEmpty {
            lines.append(("", nil))
            lines.append((creditsHeading, nil))
        }
        lines.append(contentsOf: named.map { ($0.name, $0.url) })

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let text = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n", attributes: attributes)) }
            var lineAttributes = attributes
            if let link = line.link { lineAttributes[.link] = link }
            text.append(NSAttributedString(string: line.text, attributes: lineAttributes))
        }
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

    /// Presents the standard panel with one line, linked when it has a URL, per credit.
    @MainActor
    public static func show(
        bundle: Bundle = .main,
        copyrightHolder: String = "Lumen contributors",
        profileURL: URL = URL(string: "https://github.com/jdotc1/LumenUI")!,
        credits: [LumenAboutCredit],
        creditsHeading: String? = nil
    ) {
        NSApp.orderFrontStandardAboutPanel(options: options(
            bundle: bundle, copyrightHolder: copyrightHolder, profileURL: profileURL,
            credits: credits, creditsHeading: creditsHeading))
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
    private let creditLinks: [LumenAboutCredit]?
    private let creditsHeading: String?

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
        self.creditLinks = nil
        self.creditsHeading = nil
    }

    /// The About item presents one line, linked when it has a URL, per credit.
    public init(
        bundle: Bundle = .main,
        copyrightHolder: String = "Lumen contributors",
        profileURL: URL = URL(string: "https://github.com/jdotc1/LumenUI")!,
        credits: [LumenAboutCredit],
        creditsHeading: String? = nil
    ) {
        self.bundle = bundle
        self.copyrightHolder = copyrightHolder
        self.profileURL = profileURL
        self.credits = nil
        self.creditLinks = credits
        self.creditsHeading = creditsHeading
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(lumenLocalized(String(localized: "About %@", defaultValue: "About \(LumenAboutPanel.applicationName(bundle: bundle))", bundle: .module, comment: "AboutPanel label. Values identify the item or count described."))) {
                if let creditLinks {
                    LumenAboutPanel.show(bundle: bundle, copyrightHolder: copyrightHolder,
                                        profileURL: profileURL, credits: creditLinks,
                                        creditsHeading: creditsHeading)
                } else {
                    LumenAboutPanel.show(bundle: bundle, copyrightHolder: copyrightHolder,
                                        profileURL: profileURL, credits: credits)
                }
            }
        }
    }
}
