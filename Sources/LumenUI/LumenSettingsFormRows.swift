import SwiftUI

/// A labeled text value. Monospacing applies only to the editable value, never the title.
public struct LumenSettingsTextRow: View {
    private let title: String
    private let description: String?
    private let monospaced: Bool
    @Binding private var text: String
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    public init(_ title: String, text: Binding<String>, description: String? = nil, monospaced: Bool = false) {
        self.title = title
        _text = text
        self.description = description
        self.monospaced = monospaced
    }

    public var body: some View {
        LumenSettingsRow(title, description: description) {
            TextField(title, text: $text)
                .font(monospaced ? metrics.typography.body.monospaced() : metrics.typography.body)
                .foregroundStyle(palette[.fgPrimary])
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 220, maxWidth: 280)
        }
    }
}

/// A labeled integer field with a trailing unit and room for seven digits plus grouping.
public struct LumenSettingsNumberRow: View {
    private let title: String
    private let description: String?
    private let range: ClosedRange<Int>
    private let step: Int
    private let unit: String
    @Binding private var value: Int

    public init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, unit: String,
                step: Int = 1, description: String? = nil) {
        self.title = title
        _value = value
        self.range = range
        self.unit = unit
        self.step = step
        self.description = description
    }

    public var body: some View {
        LumenSettingsRow(title, description: description) {
            LumenNumberField(value: $value, in: range, step: step, unit: unit,
                             minimumDigits: 7, usesGrouping: true)
        }
    }
}

/// A compact filled status symbol, title and explanation inside a grouped form row.
public struct LumenSettingsStatusRow: View {
    private let title: String
    private let detail: String
    private let tone: LumenTone
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    public init(_ title: String, detail: String, tone: LumenTone) {
        self.title = title
        self.detail = detail
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.s3) {
            LumenSymbol(tone.systemImage)
                .font(.system(size: metrics.iconSize.small))
                .foregroundStyle(palette[tone.foreground])
            VStack(alignment: .leading, spacing: metrics.spacing.s1) {
                Text(title).font(metrics.typography.body).foregroundStyle(palette[.fgPrimary])
                Text(detail).font(metrics.typography.caption).foregroundStyle(palette[.fgSecondary])
                    .lumenWrapsWithoutTruncating()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, metrics.spacing.s2)
    }
}

/// Visible empty content for a form section; an optional recovery action stays trailing.
public struct LumenSettingsEmptyRow: View {
    private let title: String
    private let detail: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    public init(_ title: String, detail: String? = nil) {
        self.title = title.isEmpty ? "No items available" : title
        self.detail = detail
        actionTitle = nil
        action = nil
    }

    public init(_ title: String, detail: String? = nil, actionTitle: String, action: @escaping () -> Void) {
        self.title = title.isEmpty ? "No items available" : title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s2) {
            Text(title).font(metrics.typography.body).foregroundStyle(palette[.fgSecondary])
                .lumenWrapsWithoutTruncating()
            if let detail {
                Text(detail).font(metrics.typography.caption).foregroundStyle(palette[.fgSecondary])
                    .lumenWrapsWithoutTruncating()
            }
            if let actionTitle, let action {
                LumenSettingsButtonRow { Button(actionTitle, action: action) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, metrics.spacing.s2)
    }
}

/// A form row that aligns one or more actions with the trailing control column.
public struct LumenSettingsButtonRow<Actions: View>: View {
    private let actions: Actions
    @Environment(\.lumenMetrics) private var metrics

    public init(@ViewBuilder actions: () -> Actions) { self.actions = actions() }

    public var body: some View {
        HStack(spacing: metrics.spacing.s3) { actions }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, metrics.spacing.s2)
    }
}
