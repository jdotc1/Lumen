import AppIntents
import LumenIntents
import LumenTokens
import LumenUI
import SwiftUI

struct CatalogIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [LumenIntentsPackage.self] }
}

/// Literal discovery metadata belongs to the app; command titles and actions come from its palette.
struct CatalogAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LumenCommandIntent(),
            phrases: ["Run \(\.$command) in \(.applicationName)"],
            shortTitle: "Run Command",
            systemImageName: "command"
        )
    }
}

@MainActor
enum CatalogIntentCommands {
    static func commands(store: LumenThemeStore) -> [LumenCommand] {
        let ids = [LumenThemes.standardID, LumenThemes.midnightID, LumenThemes.ultravioletID]
        return CatalogPalette.themes(store: store).filter { command in
            ids.contains { command.id == "theme.\($0)" }
        }
    }

    static func install(store: LumenThemeStore) {
        LumenIntentCommands.configure { commands(store: store) }
        CatalogAppShortcuts.updateAppShortcutParameters()
    }
}

struct CatalogIntentMenu: Commands {
    let store: LumenThemeStore

    var body: some Commands {
        CommandMenu("Theme Commands") {
            ForEach(CatalogIntentCommands.commands(store: store)) { command in
                Button(action: command.perform) {
                    LumenMenuLabel(command.title, systemImage: command.systemImage, hue: command.hue)
                }
                .disabled(!command.isEnabled)
            }
        }
    }
}
