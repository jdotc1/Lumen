import SwiftUI

/// A plain page title and optional supporting text, symbol and native actions.
/// Unlike `LumenDetailHeader`, this has no entity tile, metadata or hero treatment.
/// The title is never elided: actions move below it before the title wraps.
public struct LumenPageHeader<Actions: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let actions: Actions
    @Environment(\.lumenMetrics) private var metrics

    public init(_ title: String, subtitle: String? = nil, systemImage: String? = nil,
                @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.actions = actions()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: metrics.spacing.s6) {
                LumenPageHeading(title: title, subtitle: subtitle, systemImage: systemImage)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                HStack(spacing: metrics.spacing.s4) { actions }.fixedSize()
            }
            VStack(alignment: .leading, spacing: metrics.spacing.s5) {
                LumenPageHeading(title: title, subtitle: subtitle, systemImage: systemImage)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: metrics.spacing.s4) { actions }.fixedSize()
                    VStack(alignment: .leading, spacing: metrics.spacing.s4) { actions }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension LumenPageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.init(title, subtitle: subtitle, systemImage: systemImage) { EmptyView() }
    }
}

private struct LumenPageHeading: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.s4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(metrics.typography.title2)
                    .foregroundStyle(palette[.fgSecondary])
            }
            VStack(alignment: .leading, spacing: metrics.spacing.s2) {
                Text(title).font(metrics.typography.title2)
                    .foregroundStyle(palette[.fgPrimary])
                    .lumenWrapsWithoutTruncating()
                if let subtitle {
                    Text(subtitle).font(metrics.typography.body)
                        .foregroundStyle(palette[.fgSecondary])
                        .lumenWrapsWithoutTruncating()
                }
            }
        }
    }
}
