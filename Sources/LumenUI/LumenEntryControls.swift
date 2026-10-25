import AppKit
import SwiftUI
import LumenTokens

/// The native editor embedded in a Lumen date or time field.
public enum LumenDateFieldStyle: Sendable {
    case stepper
    case graphicalPopover
}

/// A calendar date on the same field surface and height as `LumenNumberField`.
public struct LumenDateField: View {
    private let selection: Binding<Date>
    private let range: ClosedRange<Date>?
    private let style: LumenDateFieldStyle

    public init(selection: Binding<Date>, in range: ClosedRange<Date>? = nil,
                style: LumenDateFieldStyle = .stepper) {
        self.selection = selection
        self.range = range
        self.style = style
    }

    public var body: some View {
        EntryDatePicker(selection: selection, range: range, style: style, components: .date)
    }
}

/// A time on a Lumen field surface. Ranges constrain the complete bound date, including its day.
public struct LumenTimeField: View {
    private let selection: Binding<Date>
    private let range: ClosedRange<Date>?
    private let style: LumenDateFieldStyle

    public init(selection: Binding<Date>, in range: ClosedRange<Date>? = nil,
                style: LumenDateFieldStyle = .stepper) {
        self.selection = selection
        self.range = range
        self.style = style
    }

    public var body: some View {
        EntryDatePicker(selection: selection, range: range, style: style, components: .hourAndMinute)
    }
}

/// The picker and popover share this projection, including writes at either range boundary.
@MainActor enum LumenEntryDateBinding {
    static func bounded(_ source: Binding<Date>, in range: ClosedRange<Date>?) -> Binding<Date> {
        Binding(get: { clamp(source.wrappedValue, in: range) },
                set: { source.wrappedValue = clamp($0, in: range) })
    }

    static func stepped(_ value: Date, by direction: Int, component: Calendar.Component,
                        calendar: Calendar, in range: ClosedRange<Date>?) -> Date {
        clamp(calendar.date(byAdding: component, value: direction, to: value) ?? value, in: range)
    }

    static func clamp(_ value: Date, in range: ClosedRange<Date>?) -> Date {
        guard let range else { return value }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct EntryDatePicker: View {
    let selection: Binding<Date>
    let range: ClosedRange<Date>?
    let style: LumenDateFieldStyle
    let components: DatePickerComponents
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @State private var showsPicker = false
    @FocusState private var focused: Bool

    private var value: Binding<Date> { LumenEntryDateBinding.bounded(selection, in: range) }

    @ViewBuilder private var picker: some View {
        if let range {
            DatePicker("", selection: value, in: range, displayedComponents: components)
        } else {
            DatePicker("", selection: value, displayedComponents: components)
        }
    }

    var body: some View {
        Group {
            switch style {
            case .stepper:
                HStack(spacing: metrics.spacing.s1) {
                    LumenEntryNativeDatePicker(selection: value, range: range, dateOnly: components == .date)
                        .fixedSize()
                        .focused($focused)
                        .padding(.horizontal, metrics.layout.fieldInset)
                        .frame(height: metrics.layout.controlHeight)
                        .lumenChrome(.field, focused: focused)
                    VStack(spacing: 0) {
                        LumenNumberField.StepButton(symbol: "chevron.up", title: "Increase") { nudge(1) }
                            .disabled(range.map { value.wrappedValue >= $0.upperBound } ?? false)
                        Rectangle().fill(palette[.borderSubtle]).frame(height: metrics.stroke.hairline)
                            .padding(.horizontal, 3)
                        LumenNumberField.StepButton(symbol: "chevron.down", title: "Decrease") { nudge(-1) }
                            .disabled(range.map { value.wrappedValue <= $0.lowerBound } ?? false)
                    }
                    .frame(width: LumenNumberField.stepperWidth, height: metrics.layout.controlHeight)
                    .lumenChrome(.popUp)
                }
            case .graphicalPopover:
                Button { showsPicker.toggle() } label: {
                    HStack(spacing: metrics.spacing.s2) {
                        Text(value.wrappedValue, format: components == .date ? .dateTime.year().month().day() : .dateTime.hour().minute())
                            .fixedSize()
                        LumenSymbol(components == .date ? "calendar" : "clock")
                    }
                }
                .buttonStyle(.lumenBare)
                .focused($focused)
                .lumenPopover(isPresented: $showsPicker, title: components == .date ? "Date" : "Time",
                              systemImage: components == .date ? "calendar" : "clock") {
                    picker.datePickerStyle(.graphical).labelsHidden()
                }
                .padding(.horizontal, metrics.layout.fieldInset)
                .frame(height: metrics.layout.controlHeight)
                .lumenChrome(.field, focused: focused)
            }
        }
        .font(metrics.typography.body)
        .foregroundStyle(palette[.fgPrimary])
        .lumenDisabledFade(isEnabled)
    }

    private func nudge(_ direction: Int) {
        var calendar = calendar
        calendar.timeZone = timeZone
        value.wrappedValue = LumenEntryDateBinding.stepped(value.wrappedValue, by: direction,
            component: components == .date ? .day : .minute, calendar: calendar, in: range)
    }
}

/// Borderless component editing; Lumen owns the surrounding surface and stepper.
/// NSDatePicker exposes no public selected-component API, so the adjacent arrows step days/minutes.
struct LumenEntryNativeDatePicker: NSViewRepresentable {
    let selection: Binding<Date>
    let range: ClosedRange<Date>?
    let dateOnly: Bool
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @Environment(\.fontResolutionContext) private var fontContext
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: selection) }

    func makeNSView(context: Context) -> Container {
        let container = Container()
        let editor = container.editor
        // textFieldAndStepper keeps its native arrows even without a bezel.
        editor.datePickerStyle = .textField
        editor.isBezeled = false
        editor.isBordered = false
        editor.drawsBackground = false
        editor.presentsCalendarOverlay = false
        editor.focusRingType = .none
        editor.target = context.coordinator
        editor.action = #selector(Coordinator.changed(_:))
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        let editor = container.editor
        context.coordinator.selection = selection
        context.coordinator.isEnabled = isEnabled
        editor.datePickerElements = dateOnly ? .yearMonthDay : .hourMinute
        editor.locale = locale
        editor.calendar = calendar
        editor.timeZone = timeZone
        editor.font = metrics.typography.body.monospacedDigit().resolve(in: fontContext).ctFont as NSFont
        editor.textColor = NSColor(palette[.fgPrimary])
        editor.minDate = range?.lowerBound
        editor.maxDate = range?.upperBound
        if editor.dateValue != selection.wrappedValue { editor.dateValue = selection.wrappedValue }
        // Keep the drawing enabled: disabling NSControl adds a second, system-owned fade.
        // Block editing, focus and input separately; the surrounding Lumen chrome fades once.
        editor.allowsEditing = isEnabled
        editor.cell?.isEditable = isEnabled
        editor.cell?.isSelectable = isEnabled
        editor.isEnabled = true
        editor.invalidateIntrinsicContentSize()
        container.invalidateIntrinsicContentSize()
        container.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Container, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    // A plain NSView keeps SwiftUI from applying NSControl's automatic disabled appearance.
    final class Container: NSView {
        let editor = Editor()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(editor)
        }
        required init?(coder: NSCoder) { nil }
        override var intrinsicContentSize: NSSize { editor.intrinsicContentSize }
        override func layout() {
            super.layout()
            editor.frame = bounds
        }
    }

    final class Editor: NSDatePicker {
        var allowsEditing = true
        override var acceptsFirstResponder: Bool { allowsEditing && super.acceptsFirstResponder }
        override func hitTest(_ point: NSPoint) -> NSView? { allowsEditing ? super.hitTest(point) : nil }
        override func keyDown(with event: NSEvent) {
            if allowsEditing { super.keyDown(with: event) }
        }
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Date>
        var isEnabled = true
        init(selection: Binding<Date>) { self.selection = selection }
        @objc func changed(_ sender: NSDatePicker) {
            guard isEnabled else { return }
            selection.wrappedValue = sender.dateValue
        }
    }
}

/// A formatted value and two native buttons, suitable beside a number field in a form row.
public struct LumenStepper: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let formatter: (Double) -> String
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1,
                formatter: @escaping (Double) -> String = { $0.formatted() }) {
        _value = value
        self.range = range
        self.step = step
        self.formatter = formatter
    }

    func increment(_ direction: Int) {
        guard step.isFinite, step > 0, value.isFinite else { return }
        let moved = value + Double(direction) * step
        value = min(max(moved, range.lowerBound), range.upperBound)
    }

    public var body: some View {
        HStack(spacing: metrics.spacing.s2) {
            LumenGlyphButton(systemImage: "minus", title: "Decrease", enabled: value > range.lowerBound) { increment(-1) }
            Text(formatter(value)).font(metrics.typography.body.monospacedDigit())
                .foregroundStyle(palette[.fgPrimary]).fixedSize()
            LumenGlyphButton(systemImage: "plus", title: "Increase", enabled: value < range.upperBound) { increment(1) }
        }
        .frame(minHeight: metrics.layout.controlHeight)
        .lumenChrome(.popUp)
        .lumenDisabledFade(isEnabled)
    }
}

/// Removable chips and an input. Return or comma commits; backspace on an empty input removes the last chip.
public struct LumenTokenField: View {
    @Binding private var tokens: [String]
    private let prompt: String
    private let suggestions: [String]
    @Environment(\.lumenDensity) private var density
    @State private var input = ""
    @FocusState private var focused: Bool
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    @Environment(\.fontResolutionContext) private var fontContext

    private var entryWidth: CGFloat {
        let growth = max(1, metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight)
        let font = metrics.typography.body.resolve(in: fontContext).ctFont as NSFont
        let textWidth = ((input.isEmpty ? prompt : input) as NSString).size(withAttributes: [.font: font]).width
        return max(120 * growth, ceil(textWidth) + metrics.spacing.s2)
    }

    public init(tokens: Binding<[String]>, prompt: String = "Add a token", suggestions: [String] = []) {
        _tokens = tokens
        self.prompt = prompt
        self.suggestions = suggestions
    }

    /// Whitespace is trimmed; blank and exact duplicate tokens are ignored.
    func add(_ text: String) {
        for part in text.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty && !tokens.contains(token) { tokens.append(token) }
        }
    }

    func remove(at index: Int) {
        guard tokens.indices.contains(index) else { return }
        tokens.remove(at: index)
    }

    func removeLast() { if !tokens.isEmpty { tokens.removeLast() } }

    private var fieldPadding: CGFloat {
        max(1, metrics.layout.fieldInset + density.rowVerticalPadding(detailed: false, in: metrics.layout)
            - metrics.layout.rowVerticalPadding)
    }

    private var chipPadding: CGFloat {
        max(1, metrics.spacing.s1 + density.rowVerticalPadding(detailed: false, in: metrics.layout)
            - metrics.layout.rowVerticalPadding)
    }

    private func commit() { add(input); input = "" }

    private var matches: [String] {
        suggestions.filter { !tokens.contains($0) && (input.isEmpty || $0.localizedCaseInsensitiveContains(input)) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s1) {
            LumenFlowLayout(spacing: metrics.spacing.s1, lineSpacing: metrics.spacing.s1) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    HStack(spacing: metrics.spacing.s1) {
                        Text(token).fixedSize(horizontal: false, vertical: true)
                        Button { remove(at: index) } label: {
                            Label("Remove \(token)", systemImage: "xmark").labelStyle(.iconOnly)
                                .frame(minWidth: metrics.layout.minimumHitTarget, minHeight: metrics.layout.minimumHitTarget)
                        }
                        .buttonStyle(.lumenBare)
                        .lumenIconOnlyControl()
                    }
                    .font(metrics.typography.captionEmphasized)
                    .foregroundStyle(palette[.chipSelectedForeground])
                    .padding(.horizontal, metrics.spacing.s3)
                    .padding(.vertical, chipPadding)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(palette[.chipSelectedBackground], in: .rect(cornerRadius: metrics.radius.sm))
                }
                TextField(prompt, text: $input)
                    .textFieldStyle(.plain).font(metrics.typography.body)
                    .foregroundStyle(palette[.fgPrimary])
                    .frame(minWidth: 0, idealWidth: entryWidth, maxWidth: .infinity,
                           minHeight: metrics.layout.controlHeight, alignment: .leading)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: input) { _, new in
                        if new.contains(",") {
                            let parts = new.components(separatedBy: ",")
                            add(parts.dropLast().joined(separator: ","))
                            input = parts.last ?? ""
                        }
                    }
                    .onKeyPress(.delete) {
                        guard input.isEmpty else { return .ignored }
                        removeLast()
                        return .handled
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.layout.fieldInset)
            .padding(.vertical, fieldPadding)
            .frame(minHeight: metrics.layout.controlHeight, alignment: .leading)
            .lumenChrome(.field, focused: focused)
            if focused && !matches.isEmpty {
                VStack(alignment: .leading, spacing: metrics.spacing.s1) {
                    ForEach(matches, id: \.self) { suggestion in
                        Button(suggestion) { add(suggestion); input = "" }
                            .buttonStyle(.lumenBare)
                            .font(metrics.typography.body)
                            .foregroundStyle(palette[.fgPrimary])
                            .padding(metrics.spacing.s2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lumenChrome(.card)
            }
        }
    }
}

/// Which parts of a form segment are visible. A missing glyph always falls back to its title.
public enum LumenSegmentLabelStyle: Sendable {
    case text
    case glyph
    case glyphAndText
}

/// A form-sized segmented choice with the shared macOS rounded tab selection.
public struct LumenSegmentedControl<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [Value]
    private let title: (Value) -> String
    private let systemImage: (Value) -> String?
    private let labelStyle: LumenSegmentLabelStyle
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered: Value?

    public init(selection: Binding<Value>, options: [Value], labelStyle: LumenSegmentLabelStyle = .text,
                title: @escaping (Value) -> String, systemImage: @escaping (Value) -> String? = { _ in nil }) {
        _selection = selection
        self.options = options
        self.labelStyle = labelStyle
        self.title = title
        self.systemImage = systemImage
    }

    func select(_ value: Value) {
        if options.contains(value) { selection = value }
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            segments
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(title(option)) { select(option) }
                }
            } label: { Text(title(selection)).font(metrics.typography.body) }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, metrics.layout.fieldInset)
            .frame(minHeight: metrics.layout.controlHeight)
            .lumenChrome(.popUp)
        }
        .lumenDisabledFade(isEnabled)
    }

    private var segments: some View {
        HStack(spacing: metrics.spacing.s1) {
            ForEach(options, id: \.self) { option in
                Button { select(option) } label: {
                    HStack(spacing: metrics.spacing.s2) {
                        if labelStyle != .text, let symbol = systemImage(option) {
                            LumenSymbol(symbol)
                        }
                        if labelStyle != .glyph || systemImage(option) == nil {
                            Text(title(option)).fixedSize()
                        }
                    }
                    .font(metrics.typography.body)
                    .foregroundStyle(palette[.fgPrimary])
                    .modifier(LumenTabActivity())
                    .padding(.horizontal, metrics.spacing.s3)
                    .frame(minWidth: metrics.layout.minimumHitTarget, minHeight: metrics.layout.controlHeight - 2 * metrics.layout.pillRim)
                    .background {
                        LumenTabChrome(strip: "segmented", selected: option == selection,
                                       hovered: hovered == option)
                    }
                }
                .buttonStyle(.lumenBare)
                .onHover { hovered = $0 ? option : (hovered == option ? nil : hovered) }
                .help(title(option))
            }
        }
        .padding(metrics.layout.pillRim)
        .fixedSize()
        .lumenChrome(.field)
    }
}
