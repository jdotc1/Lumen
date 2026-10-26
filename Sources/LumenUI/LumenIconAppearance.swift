import AppKit
import Observation
import SwiftUI

/// Read-only interpretation of the system icon preference. Clear and Tinted currently use
/// dark tiles: Lumen does not reproduce the system's compositing or wallpaper tint.
struct LumenIconAppearance: Equatable, Sendable {
    enum Style: String, CaseIterable, Sendable { case regular, dark, clear, tinted }
    enum Mode: String, CaseIterable, Sendable { case automatic, light, dark }
    let style: Style
    let mode: Mode

    init(_ raw: String?) {
        let value = raw?.lowercased() ?? ""
        for style in Style.allCases {
            for mode in Mode.allCases where value == style.rawValue + mode.rawValue {
                self.style = style
                self.mode = mode
                return
            }
        }
        style = .regular
        mode = .automatic
    }

    func isDark(in scheme: ColorScheme) -> Bool {
        if style == .clear || style == .tinted { return true }
        switch mode {
        case .light: return false
        case .dark: return true
        case .automatic: return style == .dark || scheme == .dark
        }
    }
}

/// One observer for all tiles, including tiles outside a palette root. Never writes defaults.
@MainActor @Observable
final class LumenSystemIconAppearance: NSObject {
    static let shared = LumenSystemIconAppearance()
    private(set) var appearance = LumenIconAppearance(nil)

    @ObservationIgnored private let readAppearance: @MainActor () -> String?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    override convenience init() {
        self.init(readAppearance: {
            UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleIconAppearanceTheme"] as? String
        })
    }

    init(readAppearance: @escaping @MainActor () -> String?) {
        self.readAppearance = readAppearance
        super.init()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                                name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh),
                                                name: NSApplication.didBecomeActiveNotification, object: nil)
        // Cross-process preference changes are relevant only for the global domain.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(scheduleRefresh),
                                                             name: nil, object: UserDefaults.globalDomain)
    }

    @objc nonisolated private func defaultsChanged(_ notification: Notification) {
        guard notification.object == nil || (notification.object as? UserDefaults) === UserDefaults.standard else { return }
        scheduleRefresh(notification)
    }

    @objc nonisolated private func scheduleRefresh(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            pendingRefresh?.cancel()
            pendingRefresh = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
                guard let self else { return }
                pendingRefresh = nil
                refresh()
            }
        }
    }

    func refresh() {
        let next = LumenIconAppearance(readAppearance())
        if next != appearance { appearance = next }
    }
}

extension EnvironmentValues {
    /// Internal deterministic override for hosted appearance-transition checks.
    @Entry var lumenIconAppearance: LumenIconAppearance? = nil
}

/// Advisory rather than an undersized-control failure: framed glyphs are already reduced.
struct LumenTileFrameAdvisoryKey: PreferenceKey {
    static let defaultValue: Set<String> = []
    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
        value.formUnion(nextValue())
    }
}

/// A frame spans all four bounding-box edges and has an empty band separating it from its contents.
/// Measure the raster, not the name: desktopcomputer and battery remain native-sized.
@MainActor
enum LumenTileSymbolFrame {
    static let perimeterShare = 0.12
    nonisolated static let threshold = 0.75
    static let reducedShare: CGFloat = 0.52
    nonisolated static let maximumInnerBandInk = 0.35
    struct Measurement {
        let edges: [Double]
        let innerBandInk: Double
        let isGrid: Bool
        var score: Double { isGrid ? 0 : edges.min() ?? 0 }
        var isFramed: Bool { score >= threshold && innerBandInk <= maximumInnerBandInk }
        static let empty = Measurement(edges: [0, 0, 0, 0], innerBandInk: 0, isGrid: false)
    }
    private static var measurements: [String: Measurement] = [:]

    static func measurement(for name: String) -> Measurement {
        if let cached = measurements[name] { return cached }
        let result = measure(name)
        measurements[name] = result
        return result
    }

    static func score(for name: String) -> Double { measurement(for: name).score }

    static func isFramed(_ name: String) -> Bool { measurement(for: name).isFramed }

    private static func measure(_ name: String) -> Measurement {
        guard let symbol = LumenGlyph.sfSymbol(for: name),
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 96, weight: .medium)),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return .empty }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 4, y: 4, width: 120, height: 120), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        func ink(_ x: Int, _ y: Int) -> Bool {
            (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.25
        }
        var minX = 128, minY = 128, maxX = -1, maxY = -1
        for y in 0..<128 {
            for x in 0..<128 where ink(x, y) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return .empty }
        let width = maxX - minX + 1, height = maxY - minY + 1
        // A grid of separate marks has gutters in both directions, not one outer frame.
        // Preserve the existing app-placeholder grid's normal optical size.
        let middleX = (minX + width / 4)...(maxX - width / 4)
        let middleY = (minY + height / 4)...(maxY - height / 4)
        let splitX = middleX.contains { x in !(minY...maxY).contains { ink(x, $0) } }
        let splitY = middleY.contains { y in !(minX...maxX).contains { ink($0, y) } }
        let bandX = max(1, Int(Double(width) * perimeterShare))
        let bandY = max(1, Int(Double(height) * perimeterShare))
        let left = (minY...maxY).filter { y in (minX..<(minX + bandX)).contains { ink($0, y) } }.count
        let right = (minY...maxY).filter { y in ((maxX - bandX + 1)...maxX).contains { ink($0, y) } }.count
        let top = (minX...maxX).filter { x in (minY..<(minY + bandY)).contains { ink(x, $0) } }.count
        let bottom = (minX...maxX).filter { x in ((maxY - bandY + 1)...maxY).contains { ink(x, $0) } }.count
        // Three raster pixels just inside the 12% perimeter band measure the frame/content gap.
        // A solid silhouette can cover every edge but cannot leave this band mostly empty.
        var innerPixels = 0, innerInk = 0
        for y in (minY + bandY)...(maxY - bandY) {
            for x in (minX + bandX)...(maxX - bandX) {
                if x < minX + bandX + 3 || x > maxX - bandX - 3
                    || y < minY + bandY + 3 || y > maxY - bandY - 3 {
                    innerPixels += 1
                    if ink(x, y) { innerInk += 1 }
                }
            }
        }
        return Measurement(edges: [Double(left) / Double(height), Double(right) / Double(height),
                                   Double(top) / Double(width), Double(bottom) / Double(width)],
                           innerBandInk: Double(innerInk) / Double(max(1, innerPixels)),
                           isGrid: splitX && splitY)
    }
}
