import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// Record only this subject, once. Recording reports failures pending human image review.
@MainActor final class LumenEntryControlsGoldenTests: XCTestCase {
    func testEntryControls() {
        let registry = LumenRegistry.core
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
        let variants = LumenSnapshot.Variant.all(for: registry.galleryThemes)
        XCTAssertEqual(variants.count, 6)
        for variant in variants {
            check(EntryControlsSubject(), name: "entry-controls", variant: variant, registry: registry, directory: directory)
        }
        let standard = LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: .light)
        check(EntryControlsSubject().lumenTextScale(1.3), name: "entry-controls-scale-1.3",
              variant: standard, registry: registry, directory: directory)
        check(EntryControlsSubject().environment(\.lumenDensity, .compact), name: "entry-controls-compact",
              variant: standard, registry: registry, directory: directory)
    }

    private func check<V: View>(_ view: V, name: String, variant: LumenSnapshot.Variant,
                               registry: LumenRegistry, directory: URL) {
        let outcome = LumenSizingGoldenEvidence.verify(view.environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current), named: name,
            size: CGSize(width: 760, height: 650), variant: variant, registry: registry,
            goldenDirectory: directory, renderer: .window)
        if let message = outcome.failureMessage { XCTFail("\(variant.label): \(message)") }
    }
}

private struct EntryControlsSubject: View {
    @Environment(\.lumenMetrics) private var metrics
    @State private var date = Date(timeIntervalSince1970: 1_792_757_400)
    @State private var value = 2.0
    @State private var selected = "Day"
    @State private var tokens = ["Swift", "UI", "Testing"]

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s4) {
            Text("Date and time · stepper and popover fields").font(metrics.typography.headline)
            HStack {
                LumenDateField(selection: $date)
                LumenDateField(selection: $date, style: .graphicalPopover)
                LumenTimeField(selection: $date)
                LumenTimeField(selection: $date, style: .graphicalPopover)
            }
            Text("Shared value · number field and formatted stepper").font(metrics.typography.headline)
            LumenFormRow("Quantity") {
                HStack {
                    LumenNumberField(value: $value, in: 0...10)
                    LumenStepper(value: $value, in: 0...10, formatter: { "\($0.formatted()) items" })
                }
            }
            Text("Segments · text, glyphs, and both").font(metrics.typography.headline)
            LumenSegmentedControl(selection: $selected, options: ["Day", "Week", "Month"], title: { $0 })
            LumenSegmentedControl(selection: $selected, options: ["Day", "Week", "Month"], labelStyle: .glyph,
                                  title: { $0 }, systemImage: symbol)
            LumenSegmentedControl(selection: $selected, options: ["Day", "Week", "Month"], labelStyle: .glyphAndText,
                                  title: { $0 }, systemImage: symbol)
            Text("Tokens · wrapping field").font(metrics.typography.headline)
            LumenTokenField(tokens: $tokens, suggestions: ["Documentation"])
                .frame(width: 340)
            Text("Disabled controls").font(metrics.typography.headline)
            HStack {
                LumenDateField(selection: $date)
                LumenTimeField(selection: $date, style: .graphicalPopover)
                LumenStepper(value: $value, in: 0...10)
                LumenSegmentedControl(selection: $selected, options: ["Day", "Week"], title: { $0 })
            }.disabled(true)
            LumenTokenField(tokens: .constant(["Read only"])).disabled(true).frame(width: 340)
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func symbol(_ option: String) -> String? {
        switch option {
        case "Day": "sun.max"
        case "Week": "calendar"
        default: "calendar.circle"
        }
    }
}
