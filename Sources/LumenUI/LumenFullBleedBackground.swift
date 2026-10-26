import AppKit
import SwiftUI

/// Only a background paint layer may make this declaration. Its measured extent and
/// resolved pigment are evidence about fill, never permission to ignore foreground.
struct LumenFullBleedBackground: Equatable, Sendable {
    let frame: CGRect
    let red: Int
    let green: Int
    let blue: Int
    var cornerRadius: CGFloat = 0
}

extension Color {
    @MainActor func lumenFullBleedBackground() -> some View {
        lumenFullBleedBackground(self)
    }
}

extension View {
    /// For an existing background modifier, retain its native painting semantics and
    /// attach only the declaration of that specific pigment at the same extent.
    func lumenFullBleedBackground(_ color: Color, cornerRadius: CGFloat = 0) -> some View {
        background {
            GeometryReader { geometry in
                LumenFullBleedBackgroundReporter(color: color, cornerRadius: cornerRadius, size: geometry.size)
                    .frame(width: 0, height: 0)
            }
        }
    }
}

private struct LumenFullBleedBackgroundReporter: NSViewRepresentable {
    let color: Color
    let cornerRadius: CGFloat
    let size: CGSize
    func makeNSView(context: Context) -> LumenFullBleedBackgroundView {
        LumenFullBleedBackgroundView()
    }
    func updateNSView(_ view: LumenFullBleedBackgroundView, context: Context) {
        view.color = color
        view.cornerRadius = cornerRadius
        view.reportedSize = size
    }
}

@MainActor
final class LumenFullBleedBackgroundView: LumenNonpaintingReportView {
    var color = Color.clear
    var cornerRadius: CGFloat = 0

    func declaration(in window: NSWindow) -> LumenFullBleedBackground? {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB), rgb.alphaComponent >= 1 else { return nil }
        return .init(frame: reportedFrame(in: window),
                     red: Int((rgb.redComponent * 255).rounded()),
                     green: Int((rgb.greenComponent * 255).rounded()),
                     blue: Int((rgb.blueComponent * 255).rounded()), cornerRadius: cornerRadius)
    }
}

/// The exact premultiplied pigment of an additive linear background layer. These stops
/// come from the same Gradient used to paint; they never sample foreground pixels.
struct LumenFullBleedLinearWash: Equatable, Sendable {
    struct Stop: Equatable, Sendable {
        let location: CGFloat
        let red: Double
        let green: Double
        let blue: Double
    }
    let frame: CGRect
    let start: CGPoint
    let end: CGPoint
    let stops: [Stop]

    func contribution(at point: CGPoint) -> (Double, Double, Double) {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared : 0
        guard let first = stops.first, let last = stops.last else { return (0, 0, 0) }
        if t <= first.location { return (first.red, first.green, first.blue) }
        if t >= last.location { return (last.red, last.green, last.blue) }
        for (a, b) in zip(stops, stops.dropFirst()) where t >= a.location && t <= b.location {
            let fraction = Double((t - a.location) / (b.location - a.location))
            return (a.red + (b.red - a.red) * fraction,
                    a.green + (b.green - a.green) * fraction,
                    a.blue + (b.blue - a.blue) * fraction)
        }
        return (0, 0, 0)
    }
}

/// Painting and declaration share exactly one stop list, direction and layout extent.
struct LumenDeclaredLinearWash: View {
    let stops: [Gradient.Stop]
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    var body: some View {
        LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
            .background {
                GeometryReader { geometry in
                    LumenLinearWashReporter(stops: stops, startPoint: startPoint, endPoint: endPoint,
                                            size: geometry.size)
                        .frame(width: 0, height: 0)
                }
            }
    }
}

private struct LumenLinearWashReporter: NSViewRepresentable {
    let stops: [Gradient.Stop]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    let size: CGSize
    func makeNSView(context: Context) -> LumenLinearWashView { LumenLinearWashView() }
    func updateNSView(_ view: LumenLinearWashView, context: Context) {
        view.stops = stops.compactMap { stop in
            guard let rgb = NSColor(stop.color).usingColorSpace(.deviceRGB) else { return nil }
            return .init(location: stop.location, red: rgb.redComponent * rgb.alphaComponent * 255,
                         green: rgb.greenComponent * rgb.alphaComponent * 255,
                         blue: rgb.blueComponent * rgb.alphaComponent * 255)
        }
        view.startPoint = startPoint
        view.endPoint = endPoint
        view.reportedSize = size
    }
}

@MainActor
final class LumenLinearWashView: LumenNonpaintingReportView {
    var stops: [LumenFullBleedLinearWash.Stop] = []
    var startPoint = UnitPoint.top
    var endPoint = UnitPoint.bottom

    func declaration(in window: NSWindow) -> LumenFullBleedLinearWash {
        let frame = reportedFrame(in: window)
        func point(_ value: UnitPoint) -> CGPoint {
            CGPoint(x: frame.minX + value.x * frame.width, y: frame.maxY - value.y * frame.height)
        }
        return .init(frame: frame, start: point(startPoint), end: point(endPoint), stops: stops)
    }
}
