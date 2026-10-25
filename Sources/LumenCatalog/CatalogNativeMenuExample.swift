import AppKit
import SwiftUI
import LumenUI

/// Real NSMenu items demonstrate the OS default beside a semantically meaningful color.
struct CatalogNativeMenuExample: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var scale

    func makeNSView(context: Context) -> NSPopUpButton {
        NSPopUpButton(frame: .zero, pullsDown: true)
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Native Image Policy", action: nil, keyEquivalent: "")
        menu.addItem(LumenMenuLabel("Open File — automatic", systemImage: "folder.fill", hue: .hueBlue)
            .makeMenuItem(colorScheme: colorScheme, scale: scale))
        menu.addItem(LumenMenuLabel("Green status — meaningful", systemImage: "circle.fill", hue: .hueGreen)
            .makeMenuItem(imageCarriesMeaning: true, colorScheme: colorScheme, scale: scale))
        button.menu = menu
    }
}
