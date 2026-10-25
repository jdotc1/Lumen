import SwiftUI

/// The available width of the pane, before its readable content column is constrained.
public enum LumenSettingsWidthClass: Sendable, Equatable, CaseIterable {
    case compact, regular, wide

    public init(width: CGFloat) {
        self = width < 560 ? .compact : width > 820 ? .wide : .regular
    }

    func horizontalPadding(_ metrics: LumenMetrics) -> CGFloat {
        switch self {
        case .compact: metrics.spacing.s6
        case .regular: metrics.spacing.s8
        case .wide: metrics.spacing.s9
        }
    }

    func sectionSpacing(_ metrics: LumenMetrics) -> CGFloat {
        switch self {
        case .compact: metrics.spacing.s5
        case .regular: metrics.spacing.s6
        case .wide: metrics.spacing.s7
        }
    }
}

public extension EnvironmentValues {
    @Entry var lumenSettingsWidthClass: LumenSettingsWidthClass = .regular
}

extension EnvironmentValues {
    @Entry var lumenSettingsPreferredSize: CGSize? = nil
    @Entry var lumenSettingsMeasurementID: String? = nil
    @Entry var lumenSettingsSizesWindow = true
}

public extension View {
    /// Overrides the measured opening size of a settings root. The 680 × 480 minimum and
    /// visible-screen height cap still apply. Subsequent user resizing is preserved.
    func lumenSettingsPreferredSize(_ size: CGSize) -> some View {
        environment(\.lumenSettingsPreferredSize, size)
    }
}

/// An inset group for related settings, such as an executable field and its actions.
/// Use rows inside the same group when their trailing controls should share its inner edge.
public struct LumenSettingsGroup<Content: View>: View {
    private let content: Content
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenSettingsWidthClass) private var widthClass

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: widthClass.sectionSpacing(metrics)) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(widthClass.sectionSpacing(metrics))
    }
}

struct LumenSettingsNaturalHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

struct LumenSettingsFallbackHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

struct LumenSettingsNaturalHeight: ViewModifier {
    var isFallback = false
    @Environment(\.lumenSettingsMeasurementID) private var id
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                if isFallback {
                    Color.clear.preference(key: LumenSettingsFallbackHeightKey.self,
                                           value: id.map { [$0: proxy.size.height] } ?? [:])
                } else {
                    Color.clear.preference(key: LumenSettingsNaturalHeightKey.self,
                                           value: id.map { [$0: proxy.size.height] } ?? [:])
                }
            }
        }
    }
}

/// Forms own a native scroll container; its document extent, not its viewport, is the measure.
struct LumenSettingsFormMeasure: ViewModifier {
    @Environment(\.lumenSettingsMeasurementID) private var id
    @State private var height: CGFloat = 0
    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) {
            $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom
        } action: { _, height in
            self.height = height
        }
        .preference(key: LumenSettingsNaturalHeightKey.self,
                    value: id.map { [$0: height] } ?? [:])
    }
}

/// Pure opening-size policy shared by the native window bridge and focused tests.
enum LumenSettingsSizing {
    static let minimumHeight: CGFloat = 480
    static let screenMargin: CGFloat = 48
    static func idealSize(heights: [CGFloat], preferred: CGSize?, visibleHeight: CGFloat?,
                          toolbarHeight: CGFloat = 40) -> CGSize {
        let ceiling = max(minimumHeight, visibleHeight.map { $0 - screenMargin - toolbarHeight } ?? 720)
        let natural = heights.filter { $0.isFinite }.max() ?? minimumHeight
        let height = preferred.flatMap { $0.height.isFinite ? $0.height : nil } ?? natural
        let width = preferred.flatMap { $0.width.isFinite ? $0.width : nil } ?? 820
        return CGSize(width: max(680, width), height: min(ceiling, max(minimumHeight, height)))
    }
}
