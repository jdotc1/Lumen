import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor final class LumenEntryControlsTests: XCTestCase {
    func testSegmentSelectionRoundTripRejectsUnknownOptions() {
        var value = "Day"
        let control = LumenSegmentedControl(selection: Binding(get: { value }, set: { value = $0 }),
                                            options: ["Day", "Week"], title: { $0 })
        control.select("Week")
        XCTAssertEqual(value, "Week")
        value = "Day"
        control.select("Unknown")
        XCTAssertEqual(value, "Day")
    }

    func testNarrowEntryControlsFitAForm() {
        XCTAssertLessThanOrEqual(LumenLayout.minimumWidth(of: LumenTokenField(tokens: .constant(["Swift", "UI"]))), 300)
        XCTAssertLessThanOrEqual(LumenLayout.minimumWidth(of: LumenStepper(value: .constant(2), in: 0...10)), 300)
        XCTAssertLessThanOrEqual(LumenLayout.minimumWidth(of: LumenDateField(selection: .constant(Date(timeIntervalSince1970: 0)))), 300)
        XCTAssertLessThanOrEqual(LumenLayout.minimumWidth(of: LumenTimeField(selection: .constant(Date(timeIntervalSince1970: 0)))), 300)
        XCTAssertLessThanOrEqual(LumenLayout.minimumWidth(of: LumenSegmentedControl(selection: .constant("Day"),
            options: ["Day", "Week"], title: { $0 })), 300)
    }

    func testDateBindingRoundTripAndRangeClamping() {
        let lower = Date(timeIntervalSince1970: 100)
        let upper = Date(timeIntervalSince1970: 200)
        var stored = lower
        let source = Binding(get: { stored }, set: { stored = $0 })
        let bounded = LumenEntryDateBinding.bounded(source, in: lower...upper)
        bounded.wrappedValue = Date(timeIntervalSince1970: 150)
        XCTAssertEqual(stored.timeIntervalSince1970, 150)
        stored = upper
        XCTAssertEqual(bounded.wrappedValue, upper)
        bounded.wrappedValue = Date(timeIntervalSince1970: 300)
        XCTAssertEqual(stored, upper)
        bounded.wrappedValue = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(stored, lower)
        let unlimited = LumenEntryDateBinding.bounded(source, in: nil)
        unlimited.wrappedValue = Date(timeIntervalSince1970: 500)
        XCTAssertEqual(stored.timeIntervalSince1970, 500)
    }

    func testStepperWritesBindingAndClampsBothEnds() {
        var value = 1.0
        let binding = Binding(get: { value }, set: { value = $0 })
        let control = LumenStepper(value: binding, in: 0...2, step: 0.75)
        control.increment(1)
        XCTAssertEqual(value, 1.75)
        control.increment(1)
        XCTAssertEqual(value, 2)
        value = 0.25
        control.increment(-1)
        XCTAssertEqual(value, 0)
        value = 1
        LumenStepper(value: binding, in: 0...2, step: .nan).increment(1)
        XCTAssertEqual(value, 1)
    }

    func testTokenAddRemoveAndExternalBindingChanges() {
        var tokens = ["Swift"]
        let field = LumenTokenField(tokens: Binding(get: { tokens }, set: { tokens = $0 }))
        field.add(" Swift, UI , , Testing ")
        XCTAssertEqual(tokens, ["Swift", "UI", "Testing"])
        field.remove(at: 1)
        XCTAssertEqual(tokens, ["Swift", "Testing"])
        tokens = ["External", "Value"]
        field.removeLast()
        XCTAssertEqual(tokens, ["External"])
        field.removeLast()
        field.removeLast()
        field.remove(at: 99)
        XCTAssertEqual(tokens, [])
    }
}

@MainActor final class LumenEntryEditorTests: XCTestCase {
    func testCalendarArrowsAndBounds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let next = LumenEntryDateBinding.stepped(date, by: 1, component: .day, calendar: calendar, in: nil)
        XCTAssertEqual(calendar.component(.hour, from: next), 12)
        XCTAssertEqual(next.timeIntervalSince(date), 23 * 3600)
        let minute = LumenEntryDateBinding.stepped(date, by: -1, component: .minute, calendar: calendar, in: nil)
        XCTAssertEqual(minute.timeIntervalSince(date), -60)
        XCTAssertEqual(LumenEntryDateBinding.stepped(date, by: 1, component: .day,
            calendar: calendar, in: date...date.addingTimeInterval(60)), date.addingTimeInterval(60))
    }

    func testNativeEditorFontChromeDisabledAndBinding() throws {
        let date = Date(timeIntervalSince1970: 1_792_757_400)
        var stored = date
        let binding = Binding(get: { stored }, set: { stored = $0 })
        let native = LumenEntryNativeDatePicker(selection: binding, range: nil, dateOnly: true)
        let host = NSHostingView(rootView: native.lumenTextScale(1.3).disabled(true))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        host.layoutSubtreeIfNeeded()
        func editor(in view: NSView) -> LumenEntryNativeDatePicker.Editor? {
            if let found = view as? LumenEntryNativeDatePicker.Editor { return found }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let picker = try XCTUnwrap(editor(in: host))
        XCTAssertEqual(picker.datePickerStyle, .textField)
        XCTAssertFalse(picker.isBezeled)
        XCTAssertFalse(picker.isBordered)
        XCTAssertFalse(picker.drawsBackground)
        XCTAssertTrue(picker.isEnabled, "Lumen owns the disabled fade")
        XCTAssertFalse(picker.allowsEditing)
        XCTAssertFalse(picker.acceptsFirstResponder)
        let font = try XCTUnwrap(picker.font)
        let resolved = LumenMetrics.resolving(nil, textScale: 1.3).typography.body.monospacedDigit()
            .resolve(in: EnvironmentValues().fontResolutionContext)
        XCTAssertEqual(font.pointSize, resolved.pointSize, accuracy: 0.01)
        let coordinator = try XCTUnwrap(picker.target as? LumenEntryNativeDatePicker.Coordinator)
        picker.dateValue = date.addingTimeInterval(60)
        coordinator.changed(picker)
        XCTAssertEqual(stored, date, "Disabled actions cannot write")
        coordinator.isEnabled = true
        coordinator.changed(picker)
        XCTAssertEqual(stored, date.addingTimeInterval(60))
    }

    func testCompactTokenPaddingReducesHeightWithoutShrinkingType() {
        func height(_ density: LumenDensity) -> CGFloat {
            let host = NSHostingView(rootView: LumenTokenField(tokens: .constant(["Read only"]))
                .environment(\.lumenDensity, density).frame(width: 340))
            return host.fittingSize.height
        }
        XCTAssertLessThan(height(.compact), height(.regular))
    }
}
