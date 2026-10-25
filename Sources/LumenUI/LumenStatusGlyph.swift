import AppKit
import SwiftUI

/// A monochrome menu bar label image. Accepts SF Symbol names and registered `lumen.` glyphs.
/// Keep the image in the scene label; SwiftUI owns the status item and its presentation.
public struct LumenStatusGlyph: Hashable, Sendable {
    public enum Attention: Hashable, Sendable {
        case none
        case badge
        case attention
    }

    public let systemImage: String
    public let attention: Attention

    public init(_ systemImage: String, attention: Attention = .none) {
        self.systemImage = systemImage
        self.attention = attention
    }

    /// Returns nil for an unknown symbol. The optional mark is part of the template alpha mask,
    /// so both the base glyph and mark follow the system's menu bar foreground.
    @MainActor
    public func templateImage() -> NSImage? {
        let base: NSImage?
        if let glyph = LumenGlyph.named(systemImage) {
            base = glyph.templateImage(size: 18)
        } else {
            base = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
        guard let base else { return nil }
        let content = HStack(alignment: .top, spacing: 1) {
            Image(nsImage: base).resizable().scaledToFit().frame(width: 18, height: 18)
            if attention == .badge {
                Circle().frame(width: 5, height: 5)
            } else if attention == .attention {
                Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 5, height: 12)
            }
        }
        .foregroundStyle(.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let pixels = renderer.cgImage else { return nil }
        let result = NSImage(cgImage: pixels, size: CGSize(width: attention == .none ? 18 : 24, height: 18))
        result.isTemplate = true
        return result
    }

    /// A template image suitable for `MenuBarExtra`'s label builder.
    @MainActor
    public var image: Image {
        templateImage().map { Image(nsImage: $0).renderingMode(.template) }
            ?? Image(systemName: "questionmark.square.dashed").renderingMode(.template)
    }
}
