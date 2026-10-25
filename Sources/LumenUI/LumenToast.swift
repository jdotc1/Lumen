import SwiftUI
import Observation
import LumenTokens

/// A transient window notice. Unlike `LumenNoticeCard`, it lives above the content.
public struct LumenToast: Identifiable {
    public let id: UUID
    public let title: String
    public let message: String?
    public let tone: LumenTone
    public let action: Action?
    /// Seconds of visible, unhovered time; nil stays until dismissed.
    public let duration: TimeInterval?

    public struct Action {
        public let title: String
        public let perform: @MainActor () -> Void
        public init(_ title: String, perform: @escaping @MainActor () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    /// Info and success expire after four seconds; warning and danger stay.
    public init(title: String, message: String? = nil, tone: LumenTone = .info, action: Action? = nil) {
        self.init(title: title, message: message, tone: tone, action: action,
                  duration: tone == .warning || tone == .danger ? nil : 4)
    }

    /// Explicit duration overrides the tone's default. Nil always means persistent.
    public init(title: String, message: String? = nil, tone: LumenTone = .info, action: Action? = nil,
                duration: TimeInterval?) {
        id = UUID()
        self.title = title
        self.message = message
        self.tone = tone
        self.action = action
        self.duration = duration.map { $0.isFinite ? max(0, $0) : 4 }
    }
}

/// Hold one center in each window's `@State`; no shared or global notice queue.
@MainActor @Observable
public final class LumenToastCenter {
    private struct Entry {
        let toast: LumenToast
        var remaining: TimeInterval?
        var started: TimeInterval?
        var hovered = false
    }
    private var entries: [Entry] = []
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let schedulesTimers: Bool
    @ObservationIgnored private var timer: Task<Void, Never>?

    public convenience init() {
        self.init(now: { ProcessInfo.processInfo.systemUptime }, schedulesTimers: true)
    }

    init(now: @escaping () -> TimeInterval, schedulesTimers: Bool) {
        self.now = now
        self.schedulesTimers = schedulesTimers
    }

    deinit { timer?.cancel() }

    /// The newest three, in posting order (newest at the bottom).
    public var visibleToasts: [LumenToast] { entries.suffix(3).map(\.toast) }
    public var collapsedCount: Int { max(0, entries.count - 3) }

    @discardableResult
    public func post(_ toast: LumenToast) -> UUID {
        settle()
        entries.removeAll { $0.toast.id == toast.id }
        entries.append(Entry(toast: toast, remaining: toast.duration))
        resumeVisibleTimers()
        return toast.id
    }

    public func dismiss(id: UUID) {
        settle()
        entries.removeAll { $0.toast.id == id }
        resumeVisibleTimers()
    }

    func setHovered(_ hovered: Bool, id: UUID) {
        settle()
        if let index = entries.firstIndex(where: { $0.toast.id == id }) { entries[index].hovered = hovered }
        resumeVisibleTimers()
    }

    /// Deduct elapsed monotonic time before changing visibility or hover state.
    private func settle() {
        let instant = now()
        for index in entries.indices {
            if let started = entries[index].started, let remaining = entries[index].remaining {
                entries[index].remaining = max(0, remaining - max(0, instant - started))
            }
            entries[index].started = nil
        }
        entries.removeAll { $0.remaining == 0 }
    }

    func expireDueToasts() {
        settle()
        resumeVisibleTimers()
    }

    private func resumeVisibleTimers() {
        timer?.cancel()
        let instant = now()
        let visibleStart = max(0, entries.count - 3)
        for index in entries.indices {
            entries[index].started = index >= visibleStart && !entries[index].hovered && entries[index].remaining != nil
                ? instant : nil
        }
        guard schedulesTimers,
              let delay = entries.filter({ $0.started != nil }).compactMap(\.remaining).min() else { return }
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expireDueToasts()
        }
    }
}

extension EnvironmentValues {
    @Entry var lumenToastPreferredWidth: CGFloat?
}

public extension View {
    /// Preferred maximum toast width in points, still bounded by the available host width.
    /// Apply after `lumenToasts`. Nil, nonpositive or nonfinite values restore the scaled default.
    func lumenToastWidth(_ width: CGFloat?) -> some View {
        environment(\.lumenToastPreferredWidth, width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
    }

    /// Host once in a window. Apply to the content above its status bar (before a bottom
    /// `safeAreaInset`), or pass the status bar's occupied height as `bottomInset`.
    func lumenToasts(_ center: LumenToastCenter, bottomInset: CGFloat = 0) -> some View {
        modifier(LumenToastHost(center: center, bottomInset: bottomInset))
    }
}

private struct LumenToastHost: ViewModifier {
    let center: LumenToastCenter
    let bottomInset: CGFloat
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenToastPreferredWidth) private var preferredWidth
    private var resolvedWidth: CGFloat { preferredWidth ?? 360 * metrics.floatingTextGrowth }

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            ViewThatFits(in: .vertical) {
                LumenToastStack(center: center)
                ScrollView { LumenToastStack(center: center).padding(metrics.spacing.s2) }
                    .frame(maxWidth: resolvedWidth)
                    .defaultScrollAnchor(.bottom)
            }
                .padding(metrics.spacing.s4)
                .padding(.bottom, max(0, bottomInset))
        }
    }
}

struct LumenToastStack: View {
    let center: LumenToastCenter
    @Environment(\.lumenToastPreferredWidth) private var preferredWidth
    private var resolvedWidth: CGFloat { preferredWidth ?? 360 * metrics.floatingTextGrowth }
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: metrics.spacing.s3) {
            if center.collapsedCount > 0 {
                Text("+\(center.collapsedCount)")
                    .font(metrics.typography.captionEmphasized)
                    .foregroundStyle(palette[.fgSecondary])
                    .padding(.horizontal, metrics.spacing.s3).padding(.vertical, metrics.spacing.s1)
                    .background(palette[.bgElevated], in: .rect(cornerRadius: metrics.radius.sm))
                    .help("\(center.collapsedCount) earlier notices; dismiss a visible notice to reveal them")
            }
            ForEach(center.visibleToasts) { toast in
                LumenToastCard(toast: toast) { center.dismiss(id: toast.id) }
                    .onHover { center.setHovered($0, id: toast.id) }
                    .lumenTransition(.toast)
            }
        }
        .frame(minWidth: 0, idealWidth: resolvedWidth, maxWidth: resolvedWidth, alignment: .trailing)
        .lumenAnimation(.toast, value: center.visibleToasts.map(\.id))
    }
}

struct LumenToastCard: View {
    let toast: LumenToast
    let dismiss: () -> Void
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenResolvedChromeStyle) private var chrome

    var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.s3) {
            LumenSymbol(toast.tone.systemImage)
                .font(metrics.typography.bodyEmphasized)
                .foregroundStyle(palette[toast.tone.foreground])
            VStack(alignment: .leading, spacing: metrics.spacing.s2) {
                Text(toast.title).font(metrics.typography.bodyEmphasized)
                    .foregroundStyle(palette[.fgPrimary]).lumenWrapsWithoutTruncating()
                if let message = toast.message {
                    Text(message).font(metrics.typography.callout)
                        .foregroundStyle(palette[.fgSecondary]).lumenWrapsWithoutTruncating()
                }
                if let action = toast.action {
                    Button { action.perform(); dismiss() } label: {
                        Text(action.title).lumenWrapsWithoutTruncating()
                    }
                    .buttonStyle(NoticeActionStyle(edge: palette[.borderDefault]))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .foregroundStyle(palette[.fgSecondary])
                .frame(width: metrics.layout.minimumHitTarget, height: metrics.layout.minimumHitTarget)
                .contentShape(.rect).lumenIconOnlyControl("Dismiss").help("Dismiss")
        }
        .padding(metrics.spacing.s4)
        .lumenRaisedGround()
        .background {
            let shape = RoundedRectangle(cornerRadius: metrics.radius.lg, style: .continuous)
            // A notice always owns its ground, even over text or another colored surface.
            // Keep the opaque backing under the material so glass cannot reveal page text.
            ZStack {
                shape.fill(palette[.bgElevated])
                if chrome == .glass {
                    shape.fill(.thickMaterial).glassEffect(.regular, in: shape)
                }
            }
        }
        .overlay {
            if chrome == .drawn {
                RoundedRectangle(cornerRadius: metrics.radius.lg, style: .continuous)
                    .strokeBorder(palette[.borderDefault], lineWidth: metrics.stroke.hairline)
            }
        }
        .lumenElevation(.popover)
    }
}
