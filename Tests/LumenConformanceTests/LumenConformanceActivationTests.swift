import AppKit
import SwiftUI
import XCTest
import LumenConformance
import LumenHeadlessGuard

@MainActor
final class LumenConformanceActivationTests: XCTestCase {
    func testTruncationLeavesHostPolicyUnchangedWithoutPolicyGate() {
        XCTAssertTrue(LumenHeadlessGuardInstalled())
        let app = NSApplication.shared
        // The test-only guard prohibits activation before conformance creates any window.
        XCTAssertEqual(app.activationPolicy(), .prohibited)
        let observation = LumenHeadlessGuardObserveHostingPolicy {
            // No policy gate is installed in the shared host. This facade exposes the old
            // conditional setter while the actual process stays prohibited, never regular.
            XCTAssertEqual(app.activationPolicy(), .accessory)
            let before = app.activationPolicy()
            let findings = LumenConformance.truncation(sizes: [CGSize(width: 160, height: 90)]) {
                Text("Policy probe")
            }
            XCTAssertTrue(findings.isEmpty, "\(findings)")
            XCTAssertEqual(app.activationPolicy(), before)
        }
        XCTAssertEqual(observation["setterCalls"] as? Int, 0)
        XCTAssertEqual(observation["reportedPolicyAfter"] as? Int, NSApplication.ActivationPolicy.accessory.rawValue)
        XCTAssertEqual(app.activationPolicy(), .prohibited)
        print("CONFORMANCE-POLICY \(observation)")
    }
}
