import AppKit
import SwiftUI

/// Opt-in measurements for the isolated Catalog preview's real Settings scene.
/// Only the explicit shots option resizes this preview's own window; neither mode activates it.
/// The launcher captures each published window ID and acknowledges it before the next resize.
struct CatalogSettingsWindowMetrics: NSViewRepresentable {
    static var engineControlFrames: [String: CGRect] = [:]

    func makeNSView(context: Context) -> MetricsView { MetricsView() }
    func updateNSView(_ nsView: MetricsView, context: Context) {}

    final class MetricsView: NSView {
        private var scheduled = false
        private var metrics: [String: Any] = [:]
        private var shots: [[String: Any]] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !scheduled, window != nil,
                  let destination = ProcessInfo.processInfo.environment["LUMEN_CATALOG_SETTINGS_METRICS"] else { return }
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let window = self.window else { return }
                self.metrics = self.measure(window)
                guard let path = ProcessInfo.processInfo.environment["LUMEN_CATALOG_SETTINGS_SHOTS"] else {
                    self.writeMetrics(to: destination)
                    return
                }
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try self.publishStage(window, named: "default", directory: directory, destination: destination)
                } catch {
                    self.report(error, destination: destination)
                    return
                }
            }
        }

        private func measure(_ window: NSWindow) -> [String: Any] {
            let items = window.toolbar?.items ?? []
            return [
                "windowID": window.windowNumber,
                "engineControlTrailingEdges": CatalogSettingsWindowMetrics.engineControlFrames.mapValues { $0.maxX },
                "title": window.title,
                "frameWidth": window.frame.width,
                "frameHeight": window.frame.height,
                "contentWidth": window.contentLayoutRect.width,
                "contentHeight": window.contentLayoutRect.height,
                "bandHeight": window.frame.height - window.contentLayoutRect.height,
                "backingScale": window.backingScaleFactor,
                "toolbarStyle": window.toolbarStyle.rawValue,
                "toolbarItems": items.map { $0.itemIdentifier.rawValue },
                "sidebarToggleCount": items.filter {
                    $0.itemIdentifier.rawValue.contains("toggleSidebar") ||
                    $0.itemIdentifier.rawValue.contains("lumen.settings.sidebar")
                }.count
            ]
        }

        private func resize(_ window: NSWindow, contentSize: CGSize) {
            // Full-size-content windows include toolbar chrome in setContentSize. Apply the
            // difference to the frame so these targets describe the visible pane area exactly.
            var frame = window.frame
            let heightChange = contentSize.height - window.contentLayoutRect.height
            frame.origin.y -= heightChange
            frame.size.height += heightChange
            frame.size.width += contentSize.width - window.contentLayoutRect.width
            if let screen = window.screen {
                frame.origin.x = max(screen.visibleFrame.minX, min(frame.origin.x, screen.visibleFrame.maxX - frame.width))
                frame.origin.y = max(screen.visibleFrame.minY, min(frame.origin.y, screen.visibleFrame.maxY - frame.height))
            }
            window.setFrame(frame, display: true, animate: false)
        }

        private func publishAfterLayout(named name: String, directory: URL, destination: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let window = self.window else { return }
                do {
                    try self.publishStage(window, named: name, directory: directory, destination: destination)
                } catch {
                    self.report(error, destination: destination)
                }
            }
        }

        private func publishStage(_ window: NSWindow, named name: String, directory: URL, destination: String) throws {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            var sample = measure(window)
            sample["name"] = name
            sample["path"] = directory.appending(path: "settings-\(name).png").path
            let data = try JSONSerialization.data(withJSONObject: sample, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appending(path: "settings-stage.json"), options: .atomic)
            awaitCapture(named: name, sample: sample, directory: directory, destination: destination,
                         deadline: Date().addingTimeInterval(10))
        }

        private func awaitCapture(named name: String, sample: [String: Any], directory: URL,
                                  destination: String, deadline: Date) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, let window = self.window else { return }
                let ackURL = directory.appending(path: "settings-ack.json")
                if let data = try? Data(contentsOf: ackURL),
                   let ack = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   ack["name"] as? String == name {
                    guard ack["success"] as? Bool == true else {
                        self.reportCaptureFailure(ack["error"] as? String ?? "Window capture failed for \(name)",
                                                  destination: destination)
                        return
                    }
                    self.shots.append(sample)
                    switch name {
                    case "default":
                        self.resize(window, contentSize: CGSize(width: 680, height: 480))
                        self.publishAfterLayout(named: "minimum", directory: directory, destination: destination)
                    case "minimum":
                        let band = window.frame.height - window.contentLayoutRect.height
                        let visible = window.screen?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
                        self.resize(window, contentSize: CGSize(width: min(1220, visible.width - 40),
                                                               height: min(720, visible.height - band - 40)))
                        self.publishAfterLayout(named: "wide", directory: directory, destination: destination)
                    default:
                        self.metrics["shots"] = self.shots
                        self.writeMetrics(to: destination)
                    }
                } else if Date() >= deadline {
                    self.reportCaptureFailure("Timed out waiting for the launcher's \(name) capture acknowledgement",
                                              destination: destination)
                } else {
                    self.awaitCapture(named: name, sample: sample, directory: directory,
                                      destination: destination, deadline: deadline)
                }
            }
        }

        private func reportCaptureFailure(_ message: String, destination: String) {
            report(NSError(domain: "CatalogSettingsCapture", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: message]), destination: destination)
        }

        private func report(_ error: Error, destination: String) {
            metrics["captureError"] = error.localizedDescription
            metrics["shots"] = shots
            writeMetrics(to: destination)
            NSLog("Settings window capture failed: %@", error.localizedDescription)
        }

        private func writeMetrics(to destination: String) {
            do {
                let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
            } catch {
                NSLog("Settings window metrics failed: %@", error.localizedDescription)
            }
        }
    }
}
