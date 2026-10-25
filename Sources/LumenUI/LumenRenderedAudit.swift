#if DEBUG
import AppKit
import QuartzCore
import ObjectiveC.runtime
import Vision

/// Pixel evidence for the current process only. All AppKit state is frozen before analysis.
@_spi(LayoutAudit)
public enum LumenRenderedAudit {
    public struct Element: Sendable {
        let identity: String
        let ancestors: Set<String>
        let frame: CGRect
        let source: String
        let control: Bool
        let clip: CGRect?
    }
    public struct Capture: @unchecked Sendable {
        public let image: CGImage
        public let frame: CGRect
        let usable: CGRect
        let chrome: CGRect
        let exclusions: [CGRect]
        let elements: [Element]
        let clips: [CGRect]
        let drawingBounds: [CGRect]
        let margin: CGFloat?
        let scaffoldMargins: [LumenScaffoldMargin]
        let reports: Set<String>
        var ownedChromeInk: [CGRect] = []
        var protectedButtons: [CGRect] = []
        var fullBleedBackgrounds: [LumenFullBleedBackground] = []
        var fullBleedWashes: [LumenFullBleedLinearWash] = []
        var nativeControlChrome: [CGRect] = []
        var compositeOwners: [Element] = []
        var nativeMaskPreservingInk: [CGRect] = []
        var nativeMaskPreservingSources: [InkSource] = []

        var stateKey: Int {
            var hash = Hasher()
            func rect(_ value: CGRect) {
                hash.combine(value.origin.x); hash.combine(value.origin.y)
                hash.combine(value.width); hash.combine(value.height)
            }
            rect(frame); rect(usable); rect(chrome)
            for value in exclusions + clips + drawingBounds + ownedChromeInk + protectedButtons + nativeControlChrome + nativeMaskPreservingInk { rect(value) }
            hash.combine(exclusions.count); hash.combine(clips.count); hash.combine(drawingBounds.count)
            hash.combine(ownedChromeInk.count); hash.combine(protectedButtons.count); hash.combine(nativeControlChrome.count); hash.combine(nativeMaskPreservingInk.count)
            for fill in fullBleedBackgrounds {
                rect(fill.frame); hash.combine(fill.red); hash.combine(fill.green); hash.combine(fill.blue); hash.combine(fill.cornerRadius)
            }
            for wash in fullBleedWashes {
                rect(wash.frame); hash.combine(wash.start.x); hash.combine(wash.start.y)
                hash.combine(wash.end.x); hash.combine(wash.end.y)
                for stop in wash.stops {
                    hash.combine(stop.location); hash.combine(stop.red); hash.combine(stop.green); hash.combine(stop.blue)
                }
            }
            hash.combine(margin)
            for declaration in scaffoldMargins {
                rect(declaration.frame); hash.combine(declaration.margin); hash.combine(declaration.depth)
            }
            for value in reports.sorted() { hash.combine(value) }
            for element in elements + compositeOwners {
                hash.combine(element.identity); hash.combine(element.source); hash.combine(element.control)
                rect(element.frame)
                if let clip = element.clip { rect(clip) }
                for ancestor in element.ancestors.sorted() { hash.combine(ancestor) }
            }
            if let data = image.dataProvider?.data { hash.combine(data as Data) }
            return hash.finalize()
        }
    }
    struct InkSource: Sendable {
        let frame: CGRect
        let viewClass: String
    }
    struct DetectorRegion: Sendable {
        let frame: CGRect
        let characterBoxes: [CGRect]
        let rows: [CGRect]
    }
    public struct Line: Sendable {
        public let text: String
        public let frame: CGRect
        public let confidence: Float
        public let inkPixels: Int
        var observationFrame: CGRect? = nil
        var glyphBand: CGRect? = nil

        var inkRegion: CGRect {
            glyphBand.map { CGRect(x: frame.minX, y: $0.minY, width: frame.width, height: $0.height) } ?? frame
        }
    }
    public struct Result: @unchecked Sendable {
        public let image: CGImage
        public let frame: CGRect
        public let findings: [LumenLayoutAudit.Violation]
        public let findingRects: [CGRect]
        public let lines: [Line]
        public let visionSeconds: Double
        var detectorRegions: [DetectorRegion] = []

        public func observes(_ text: String) -> Bool {
            presence(of: text) != nil
        }

        /// Complete normalized label containment, with any surrounding OCR characters retained.
        public func presence(of text: String) -> (leading: String, trailing: String)? {
            let expected = normalize(text)
            guard !expected.isEmpty else { return nil }
            let visible = lines.filter { $0.inkPixels > 3 }
            func match(_ value: String) -> (leading: String, trailing: String)? {
                let recognized = normalize(value)
                guard let range = recognized.range(of: expected) else { return nil }
                return (String(recognized[..<range.lowerBound]), String(recognized[range.upperBound...]))
            }
            for line in visible {
                if let found = match(line.text) { return found }
            }
            // Only neighboring observations on the same baseline may form a recognized line.
            let ordered = visible.sorted { $0.frame.minX < $1.frame.minX }
            for (index, first) in ordered.enumerated() {
                var previous = first
                var joined = first.text
                for next in ordered.dropFirst(index + 1) {
                    let height = min(first.frame.height, next.frame.height)
                    guard abs(first.frame.minY - next.frame.minY) <= max(1, height * 0.25) else { continue }
                    let gap = next.frame.minX - previous.frame.maxX
                    guard gap >= -1, gap <= max(3, height * 0.8) else { break }
                    joined += " " + next.text
                    if let found = match(joined) { return found }
                    previous = next
                }
            }
            return nil
        }
    }
    public enum Failure: Error { case missingFrame, missingImage }

    /// Measured capture route; no general shareable-content query or permission request is used.
    @MainActor public static func capture(in window: NSWindow) throws -> Capture {
        guard let content = window.contentView, let frameView = content.superview else { throw Failure.missingFrame }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        CATransaction.flush()
        let bounds = frameView.bounds
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { throw Failure.missingImage }
        frameView.cacheDisplay(in: bounds, to: bitmap)
        guard let image = bitmap.cgImage else { throw Failure.missingImage }
        return snapshot(window, image: image)
    }

    @MainActor private static func snapshot(_ window: NSWindow, image: CGImage) -> Capture {
        let geometry = LumenWindowGeometry(window: window)
        var exclusions = geometry.trafficLights + geometry.toolbarItems + LumenNativeSplitDividers.frames(in: window)
            + LumenNativeControlChrome.searchButtonFrames(in: window)
        var clips: [CGRect] = [], drawing: [CGRect] = [], ownedChromeInk: [CGRect] = []
        var images: [Element] = []
        var nativeMaskPreservingInk: [CGRect] = []
        var nativeMaskPreservingSources: [InkSource] = []
        let nativeFields = LumenNativeControlChrome.fields(in: window)
        var fullBleedBackgrounds: [LumenFullBleedBackground] = []
        var fullBleedWashes: [LumenFullBleedLinearWash] = []
        func walk(_ view: NSView, inChrome: Bool, ancestors: Set<String> = [], controlOwner: String? = nil) {
            guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else { return }
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            // The frame's native title and toolbar controls are owned by AppKit. Exclude their
            // individual visible bounds, never the entire titlebar or the app's content subtree.
            if inChrome, view is NSControl || view is NSTextField { exclusions.append(rect) }
            if !inChrome, view.clipsToBounds, !(view is NSClipView), !(view is NSScrollView) {
                clips.append(rect)
            }
            if let background = view as? LumenFullBleedBackgroundView,
               let declaration = background.declaration(in: window) { fullBleedBackgrounds.append(declaration) }
            if let wash = view as? LumenLinearWashView {
                fullBleedWashes.append(wash.declaration(in: window))
            }
            let identity = String(describing: ObjectIdentifier(view))
            if !inChrome, view is NSImageView {
                images.append(.init(identity: controlOwner ?? identity, ancestors: ancestors,
                                    frame: rect, source: "", control: false, clip: nil))
            }
            let module = String(reflecting: type(of: view))
            let systemView = Bundle(for: type(of: view)).bundleIdentifier?.hasPrefix("com.apple.") == true
            if !inChrome, let source = view as? any LumenOwnedInkSource {
                let ink = source.ownedInkRects.map { window.convertToScreen(view.convert($0, to: nil)) }
                ownedChromeInk += ink
                nativeMaskPreservingInk += ink
                nativeMaskPreservingSources += ink.map { .init(frame: $0, viewClass: module) }
            }
            // App-defined controls that paint are drawing sources too. Only system classes
            // qualify as native; inheriting NSControl does not grant native mask ownership.
            if !inChrome, !(view is any LumenOwnedInkSource), !systemView, view !== window.contentView,
               !module.contains("Hosting"), !view.isHidden, !rect.isEmpty, paintsOwnInk(view) {
                drawing.append(rect)
                // A container hosting native chrome is not itself a competing ink source.
                // Custom drawings over/beside the native view retain their actual ownership.
                if !nativeFields.contains(where: { $0.isDescendant(of: view) }) {
                    nativeMaskPreservingInk.append(rect)
                    nativeMaskPreservingSources.append(.init(frame: rect, viewClass: module))
                }
            }
            var descendants = ancestors
            descendants.insert(identity)
            let owner = controlOwner ?? ((view is NSControl && !(view is NSImageView)) ? identity : nil)
            for child in view.subviews {
                walk(child, inChrome: inChrome && child !== window.contentView, ancestors: descendants, controlOwner: owner)
            }
        }
        if let root = window.contentView?.superview { walk(root, inChrome: true) }
        let report = LumenWindowAuditReports.record(for: window)
        let ownership = LumenAuditCompositeOwners.collect(in: window,
            elements: LumenLayoutAudit.renderedElements(in: window) + images)
        return Capture(image: image, frame: window.frame, usable: geometry.contentBounds,
                       chrome: geometry.chromeBand, exclusions: exclusions,
                       elements: ownership.elements, clips: clips,
                       drawingBounds: drawing, margin: report.pageMargin, scaffoldMargins: report.scaffoldMargins,
                       reports: Set(report.visibleTexts.map(\.text)), ownedChromeInk: ownedChromeInk,
                       protectedButtons: geometry.trafficLights.map {
                           $0.insetBy(dx: -2 / max(1, window.backingScaleFactor), dy: -2 / max(1, window.backingScaleFactor))
                       }, fullBleedBackgrounds: fullBleedBackgrounds, fullBleedWashes: fullBleedWashes, nativeControlChrome: LumenNativeControlChrome.frames(in: window), compositeOwners: ownership.containers, nativeMaskPreservingInk: nativeMaskPreservingInk, nativeMaskPreservingSources: nativeMaskPreservingSources)
    }

    /// A transparent representable is geometry, not paint. Explicit owned-ink declarations
    /// take precedence; otherwise require a drawing implementation or visible layer content.
    @MainActor private static func paintsOwnInk(_ view: NSView) -> Bool {
        let draw = #selector(NSView.draw(_:))
        if class_getMethodImplementation(type(of: view), draw) != class_getMethodImplementation(NSView.self, draw) {
            return true
        }
        guard let layer = view.layer, !layer.isHidden, layer.opacity > 0 else { return false }
        return layer.contents != nil || (layer.backgroundColor?.alpha ?? 0) > 0
            || (layer.borderWidth > 0 && (layer.borderColor?.alpha ?? 0) > 0)
    }

    /// Character boxes within one detector region may describe several baselines.
    /// Keep rows separate; an undivided region is never evidence of a single line.
    static func characterRows(_ boxes: [CGRect]) -> [CGRect] {
        var rows: [CGRect] = []
        var commonBands: [CGRect] = []
        for box in boxes.sorted(by: { $0.midY > $1.midY }) where !box.isEmpty {
            if let index = rows.indices.first(where: {
                let overlap = min(commonBands[$0].maxY, box.maxY) - max(commonBands[$0].minY, box.minY)
                return overlap > min(commonBands[$0].height, box.height) / 2
            }) {
                rows[index] = rows[index].union(box)
                commonBands[index] = CGRect(x: 0, y: max(commonBands[index].minY, box.minY), width: 1,
                    height: min(commonBands[index].maxY, box.maxY) - max(commonBands[index].minY, box.minY))
            } else {
                rows.append(box)
                commonBands.append(CGRect(x: 0, y: box.minY, width: 1, height: box.height))
            }
        }
        return rows
    }

    public static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func analyze(_ capture: Capture) throws -> Result {
        try Task.checkCancellation()
        let pixels = try Pixels(capture)
        let request = try LumenAuditOCR.makeRequest()
        let lineGeometry = try LumenAuditOCR.makeLineGeometryRequest()
        let start = Date()
        try VNImageRequestHandler(cgImage: capture.image).perform([request, lineGeometry])
        let seconds = Date().timeIntervalSince(start)
        try Task.checkCancellation()
        func screenRect(_ box: CGRect) -> CGRect {
            CGRect(x: capture.frame.minX + box.minX * capture.frame.width,
                   y: capture.frame.minY + box.minY * capture.frame.height,
                   width: box.width * capture.frame.width, height: box.height * capture.frame.height)
        }
        // Accurate recognition boxes are padded (sometimes across multiple baselines).
        // Detection supplies the glyph-height band of each line, independently of that padding.
        let detectorRegions = (lineGeometry.results ?? []).map { observation in
            let characters = (observation.characterBoxes ?? []).map { screenRect($0.boundingBox) }
            return DetectorRegion(frame: screenRect(observation.boundingBox), characterBoxes: characters,
                                  rows: characterRows(characters))
        }
        let detectedBands = detectorRegions.flatMap(\.rows)
        let excluded = capture.exclusions.map { $0.insetBy(dx: -2, dy: -2) }
        var lines: [Line] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let value = candidate.string
            var groups: [(String, CGRect)] = []
            for word in value.split(whereSeparator: { $0.isWhitespace }) {
                let box = (try? candidate.boundingBox(for: word.startIndex..<word.endIndex))?.boundingBox
                    ?? observation.boundingBox
                let rect = screenRect(box)
                if excluded.contains(where: { $0.contains(rect) }) { continue }
                if excluded.contains(where: { $0.intersects(rect) }),
                   pixels.unexcludedInk(in: rect, exclusions: excluded) == 0 { continue }
                // Vision can merge neighboring toolbar buttons into one line. Preserve natural
                // word spacing but split runs separated by a control-sized gap.
                if let previous = groups.last,
                   rect.minX - previous.1.maxX < max(3, rect.height * 0.8),
                   abs(rect.midY - previous.1.midY) < rect.height / 2 {
                    groups[groups.count - 1] = (previous.0 + " " + word, previous.1.union(rect))
                } else { groups.append((String(word), rect)) }
            }
            for (text, rect) in groups {
                // A recognition box can grow down into a neighbor. Its upper line edge
                // anchors the baseline; never divide adjacent bands at their midpoint, which
                // would hide genuinely overprinted strings.
                let observationFrame = screenRect(observation.boundingBox)
                // A detector can label a whole panel as one character. Such a box has
                // no line geometry: it must fit the recognized observation's glyph height.
                let detected = detectedBands.filter {
                    $0.intersects(rect) && $0.height <= observationFrame.height
                }.min {
                    abs($0.maxY - rect.maxY) < abs($1.maxY - rect.maxY)
                }

                // No per-line detector geometry: use this observation's own recognized
                // height, anchored at its upper baseline edge, never a detector-region union.
                let band = detected ?? screenRect(observation.boundingBox)
                let region = CGRect(x: rect.minX, y: band.minY, width: rect.width, height: band.height)
                lines.append(Line(text: text, frame: rect, confidence: candidate.confidence,
                                  inkPixels: pixels.inkCount(in: region), observationFrame: screenRect(observation.boundingBox), glyphBand: band))
            }
        }
        var result = try evaluate(capture, pixels: pixels, lines: lines, visionSeconds: seconds)
        result.detectorRegions = detectorRegions
        return result
    }

    /// Deterministic recognition input for focused geometry counterexamples. Production uses
    /// the same evaluator after the shared OCR request; no recognition policy is overridden.
    static func analyze(_ capture: Capture, recognizedLines: [Line]) throws -> Result {
        try evaluate(capture, pixels: Pixels(capture), lines: recognizedLines, visionSeconds: 0)
    }

    private static func evaluate(_ capture: Capture, pixels: Pixels, lines: [Line],
                                 visionSeconds: Double) throws -> Result {
        let context = Context(capture: capture, pixels: pixels, lines: lines)
        var evidence: [Evidence] = []
        for rule in rules {
            try Task.checkCancellation()
            evidence += rule(context)
        }
        var seen = Set<String>()
        let unique = evidence.filter { seen.insert("\($0.rule):\($0.rect):\($0.detail)").inserted }
        return Result(image: capture.image, frame: capture.frame,
                      findings: unique.map { .init(rule: $0.rule, view: $0.subject,
                                                  message: "\($0.detail); rect=\($0.rect)") },
                      findingRects: unique.map(\.rect), lines: lines, visionSeconds: visionSeconds)
    }

    /// Differential evidence is only meaningful for uniquely matched text runs. Reflow can merge
    /// or split lines, so match normalized substrings, not observation indices.
    public static func differential(_ small: Result, _ large: Result) -> [LumenLayoutAudit.Violation] {
        small.lines.compactMap { line in
            let short = normalize(line.text).replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces)
            guard short.count >= 4,
                  !large.lines.contains(where: { normalize($0.text) == normalize(line.text) }) else { return nil }
            let candidates = large.lines.filter {
                let long = normalize($0.text)
                let parts = normalize(line.text).replacingOccurrences(of: "…", with: "...")
                    .components(separatedBy: "...").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let matches = long.contains(short) || (parts.count > 1 && parts.allSatisfy { long.contains($0) })
                return long.count > short.count + 2 && matches && $0.confidence >= 0.5
            }
            guard candidates.count == 1, line.confidence >= 0.5 else { return nil }
            // Vision can combine neighboring complete button labels after a resize.
            // Require an exact ordered reconstruction, including this observation;
            // an unrelated longer label or a genuinely growing suffix still fails.
            let candidate = normalize(candidates[0].text)
            let surviving = Set(large.lines.map { normalize($0.text) })
            let neighbors = small.lines.filter {
                $0.inkPixels > 3 && $0.confidence >= 0.5 &&
                abs($0.frame.minY - line.frame.minY) <= max(1, min($0.frame.height, line.frame.height) * 0.25)
            }.sorted { $0.frame.minX < $1.frame.minX }
            for (index, first) in neighbors.enumerated() {
                guard !surviving.contains(normalize(first.text)) else { continue }
                var text = normalize(first.text)
                var includesLine = first.frame == line.frame
                var previous = first
                for next in neighbors.dropFirst(index + 1) {
                    guard !surviving.contains(normalize(next.text)) else { break }
                    let gap = next.frame.minX - previous.frame.maxX
                    guard gap >= -1, gap <= 2 * min(previous.frame.height, next.frame.height) else { break }
                    text += " " + normalize(next.text)
                    includesLine = includesLine || next.frame == line.frame
                    if includesLine && text == candidate { return nil }
                    previous = next
                }
            }
            return .init(rule: "rendered-truncation", view: line.text,
                         message: "recognized text grows to “\(candidates[0].text)” at the larger layout; rect=\(line.frame)")
        }
    }

    private struct Evidence {
        let rule: String
        let rect: CGRect
        let subject: String
        let detail: String
    }
    private struct Context {
        let capture: Capture
        let pixels: Pixels
        let lines: [Line]
        func excluded(_ rect: CGRect, includingNativeControlChrome: Bool = true) -> Bool {
            let regions = capture.exclusions.map { $0.insetBy(dx: -2, dy: -2) }
                + (includingNativeControlChrome ? capture.nativeControlChrome : [])
            // Known Lumen drawing overrides both the native bezel mask and native accessory
            // exclusions. Text retains its separate search/cancel-glyph exclusion policy.
            if includingNativeControlChrome, capture.nativeMaskPreservingInk.contains(where: { $0.intersects(rect) }) {
                // This foreground was already classified before grouping. Re-estimating a
                // background from its bounding box could turn a solid stroke into its own
                // background and silently discard it.
                return false
            }
            if regions.contains(where: { $0.contains(rect) }) { return true }
            // Vision may combine several window buttons into one apparent punctuation line.
            // Ignore only when all foreground belongs to the actual native exclusions.
            guard regions.contains(where: { $0.intersects(rect) }) else { return false }
            return pixels.unexcludedInk(in: rect, exclusions: regions) == 0
        }
        func inkFrame(_ line: Line) -> CGRect {
            pixels.inkBounds(in: line.inkRegion) ?? line.inkRegion
        }
        func compositeOwning(_ component: CGRect, control: Element? = nil) -> Element? {
            capture.compositeOwners.filter { owner in
                owner.identity.hasPrefix("lumen-composite:") && owner.frame.contains(component)
                    && capture.frame.contains(owner.frame)
                    && (owner.clip.map { $0.contains(owner.frame) } ?? true)
                    && (control.map { $0.ancestors.contains(owner.identity) } ?? true)
            }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        }
        func ownsBoundaryInk(_ rect: CGRect) -> Bool {
            guard let owner = compositeOwning(rect) else { return false }
            return pixels.components(in: owner.frame.insetBy(dx: -12, dy: -12), excludingBackground: owner.frame).contains {
                owner.frame.contains($0) && $0.contains(rect)
            }
        }
        func owner(_ line: Line) -> Element? {
            let ink = inkFrame(line)
            let candidates = capture.elements.filter {
                let intersection = $0.frame.intersection(ink)
                return !intersection.isNull && pixels.inkCount(in: intersection) > 3
            }
            // Only independent leaves establish a composite run. A large ancestor's rectangle
            // touching the observation is not evidence that the text belongs to that ancestor.
            let leaves = candidates.filter { candidate in
                !candidates.contains { $0.identity != candidate.identity && $0.ancestors.contains(candidate.identity) }
            }
            let identities = Set(leaves.map(\.identity))
            // Native text fields omit decorative prefixes/symbols from semantic leaves. The
            // shared component explicitly declares their actual composite boundary instead.
            let needsComposite = identities.count > 1 || !leaves.contains {
                $0.frame.insetBy(dx: -1, dy: -1).contains(ink)
            }
            if needsComposite, let declared = capture.compositeOwners.filter({ composite in
                composite.identity.hasPrefix("lumen-composite:") && !leaves.isEmpty
                    && leaves.allSatisfy({ $0.ancestors.contains(composite.identity) })
            }).min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
                return declared
            }
            if identities.count > 1, let first = leaves.first {
                let common = leaves.dropFirst().reduce(first.ancestors) { $0.intersection($1.ancestors) }
                if let composite = (capture.compositeOwners + capture.elements)
                    .filter({ common.contains($0.identity) })
                    .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
                    // Keep the nearest shared boundary even when ink escapes it. Climbing to a
                    // window-sized ancestor would conceal real overflow of the composite field.
                    return composite
                }
            }
            return capture.elements.filter {
                $0.frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: ink.midX, y: ink.midY))
            }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        }
    }
    // One registry for all pixel/text rules; both observer and conformance consume its output.
    private static let rules: [@Sendable (Context) -> [Evidence]] = [chromeInk, boundaryInk, overlaps, escapes, textRules]

    private static func chromeInk(_ c: Context) -> [Evidence] {
        let owned = c.capture.ownedChromeInk.filter { rect in
            rect.intersects(c.capture.chrome) || c.capture.protectedButtons.contains { $0.intersects(rect) }
        }.map { Evidence(rule: "rendered-chrome", rect: $0, subject: "Lumen chrome ink",
                         detail: "owned ink intersects measured native chrome or window-button clearance") }
        return owned + c.pixels.components(in: c.capture.chrome).filter { component in
            !c.excluded(component) && component.width * c.pixels.sx >= 1 && component.height * c.pixels.sy >= 1
        }.map { .init(rule: "rendered-chrome", rect: $0, subject: "Rendered ink", detail: "foreground ink intersects native chrome") }
    }

    private static func boundaryInk(_ c: Context) -> [Evidence] {
        var results: [Evidence] = []
        let declarations = c.capture.scaffoldMargins
        let surfaceOwners = [LumenScaffoldMargin(frame: c.capture.usable, margin: 0, depth: -1)] + declarations
        let edges = [c.capture.frame] + c.capture.clips.filter {
            $0.width < c.capture.usable.width - 2 || $0.height < c.capture.usable.height - 2
        }
        var surfaces: [(LumenScaffoldMargin, [Int?])] = []
        var backgrounds: [(LumenScaffoldMargin, Int)] = []
        func accepts(_ point: CGPoint, for declaration: LumenScaffoldMargin) -> Bool {
            // The undeclared content owner must not borrow AppKit titlebar colors.
            // Chrome has its own ink rule; content edge/margin backgrounds use usable space.
            guard declaration.frame.contains(point) else { return false }
            let owner = LumenScaffoldMargin.owner(at: point, in: declarations)
            return owner.map { $0 == declaration } ?? (declaration.depth == -1)
        }
        func background(for declaration: LumenScaffoldMargin) -> Int {
            if let cached = backgrounds.first(where: { $0.0 == declaration }) { return cached.1 }
            let result = c.pixels.background(declaration.frame, accepting: { point in
                accepts(point, for: declaration)
            })
            backgrounds.append((declaration, result))
            return result
        }
        func surface(for declaration: LumenScaffoldMargin) -> [Int?] {
            if let cached = surfaces.first(where: { $0.0 == declaration }) { return cached.1 }
            let result = c.pixels.surfaceBackgrounds(in: declaration.frame, accepting: { point in
                accepts(point, for: declaration)
            })
            surfaces.append((declaration, result))
            return result
        }
        for declaration in surfaceOwners {
            let accepting: (CGPoint) -> Bool = { point in
                accepts(point, for: declaration)
            }
            for edge in edges {
                let rects = c.pixels.boundaryContinuations(edge, surface: { surface(for: declaration) },
                    background: { background(for: declaration) }, accepting: accepting)
                for rect in rects where !c.excluded(rect) && !c.ownsBoundaryInk(rect) {
                    results.append(.init(rule: "rendered-edge", rect: rect, subject: "Rendered ink",
                                         detail: "foreground continues inward from the clipping boundary"))
                }
            }
        }
        for edge in c.capture.clips {
            for line in c.lines where edge.intersects(line.frame) && !c.excluded(line.frame, includingNativeControlChrome: false) {
                for rect in c.pixels.glyphCuts(at: edge, line: line.inkRegion) where !c.excluded(rect, includingNativeControlChrome: false) {
                    results.append(.init(rule: "rendered-edge", rect: rect, subject: line.text,
                                         detail: "recognized glyph ink continues through the last clipping column"))
                }
            }
        }
        let defaults = c.capture.margin.map {
            [LumenScaffoldMargin(frame: c.capture.usable, margin: $0, depth: -1)]
        } ?? []
        for declaration in defaults + declarations where declaration.margin > 0 {
            let bounds = declaration.frame, margin = declaration.margin
            let regions = [CGRect(x: bounds.minX, y: bounds.minY, width: margin, height: bounds.height),
                           CGRect(x: bounds.maxX - margin, y: bounds.minY, width: margin, height: bounds.height)]
            for region in regions {
                // Native bezel ownership never owns the field's glyphs. Check their measured
                // ink against the same margin even when a connected native fill is discounted.
                for line in c.lines where line.inkPixels > 3
                    && c.capture.nativeControlChrome.contains(where: { $0.intersects(line.frame) })
                    && !c.excluded(line.frame, includingNativeControlChrome: false) {
                    guard let ink = c.pixels.inkBounds(in: line.frame) else { continue }
                    let intrusion = ink.intersection(region).intersection(c.capture.usable)
                    guard !intrusion.isNull, intrusion.width > 2, intrusion.height > 2,
                          accepts(CGPoint(x: intrusion.midX, y: intrusion.midY), for: declaration) else { continue }
                    results.append(.init(rule: "rendered-margin", rect: intrusion, subject: line.text,
                                         detail: "recognized glyph ink enters its declaring scaffold or window page margin"))
                }
                let components = c.pixels.components(in: region.intersection(c.capture.usable),
                    background: { background(for: declaration) }, surface: { surface(for: declaration) }, accepting: { point in
                    accepts(point, for: declaration)
                })
                for component in components where !c.excluded(component) {
                    guard component.width > 2, component.height > 2 else { continue }
                    results.append(.init(rule: "rendered-margin", rect: component, subject: "Rendered ink",
                                         detail: "rendered content enters its declaring scaffold or window page margin"))
                }
            }
        }
        return results
    }

    private static func overlaps(_ c: Context) -> [Evidence] {
        var results: [Evidence] = []
        let elements = c.capture.elements
        for (index, first) in elements.enumerated() {
            for second in elements.dropFirst(index + 1) {
                guard first.identity != second.identity, !first.ancestors.contains(second.identity),
                      !second.ancestors.contains(first.identity) else { continue }
                let overlap = first.frame.intersection(second.frame)
                guard overlap.width > 2, overlap.height > 2, c.pixels.inkCount(in: overlap) > 8 else { continue }
                let rule = !first.control && !second.control && !first.source.isEmpty && !second.source.isEmpty
                    ? "rendered-text-geometry" : "rendered-overlap"
                results.append(.init(rule: rule, rect: overlap, subject: first.source,
                                     detail: "rendered ink occupies two independent semantic elements"))
            }
        }
        for control in elements where control.control {
            for component in c.pixels.components(in: control.frame.insetBy(dx: -12, dy: -12), excludingBackground: control.frame) {
                guard component.intersects(control.frame.insetBy(dx: 2, dy: 2)),
                      !control.frame.insetBy(dx: -4, dy: -4).contains(component),
                      !c.excluded(component),
                      !elements.contains(where: { $0.identity != control.identity && $0.frame.contains(component) }),
                      c.compositeOwning(component, control: control) == nil else { continue }
                results.append(.init(rule: "rendered-overlap", rect: component.intersection(control.frame),
                                     subject: control.source,
                                     detail: "unowned connected foreground crosses into a control's interior"))
            }
        }
        return results
    }

    private static func escapes(_ c: Context) -> [Evidence] {
        var results: [Evidence] = []
        for bounds in c.capture.drawingBounds {
            for component in c.pixels.components(in: bounds.insetBy(dx: -8, dy: -8)) {
                guard component.intersects(bounds), !bounds.insetBy(dx: -1, dy: -1).contains(component),
                      !c.capture.elements.contains(where: { $0.frame.contains(component) }), !c.excluded(component) else { continue }
                results.append(.init(rule: "rendered-escape", rect: component, subject: "Native drawing",
                                     detail: "connected ink crosses its native drawing view's bounds without a semantic owner"))
            }
        }
        return results
    }

    private static func textRules(_ c: Context) -> [Evidence] {
        var results: [Evidence] = []
        for (index, line) in c.lines.enumerated() where !c.excluded(line.frame, includingNativeControlChrome: false) && line.inkPixels > 3 {
            let owner = c.owner(line)
            // Vision's word box includes surrounding background. Ownership is a claim about
            // rendered glyphs, measured with the same foreground classifier as every ink rule.
            let inkFrame = c.inkFrame(line)
            let geometry = "glyphBand=\(String(describing: line.glyphBand)) owner=\(owner?.identity ?? "none") source=\(owner?.source ?? "none") ownerFrame=\(String(describing: owner?.frame)) recognizedBox=\(line.frame) inkFrame=\(inkFrame)"
            let source = owner?.source ?? c.capture.reports.first(where: { normalize($0) == normalize(line.text) })
            let ownedLines = owner.map { owner in
                c.lines.filter { c.owner($0)?.identity == owner.identity }.sorted {
                    abs($0.frame.midY - $1.frame.midY) > 2 ? $0.frame.midY > $1.frame.midY : $0.frame.minX < $1.frame.minX
                }
            } ?? [line]
            let recognized = ownedLines.map(\.text).joined(separator: " ")
            let ellipsis = recognized.contains("…") || recognized.contains("...")
            let obstructed = owner.map { element in
                c.capture.elements.contains { other in
                    other.identity != element.identity && !other.ancestors.contains(element.identity)
                        && !element.ancestors.contains(other.identity) && other.frame.intersects(line.frame)
                }
            } ?? false
            if let source, !source.isEmpty, !obstructed, ownedLines.first?.frame == line.frame {
                let shorter = normalize(source).count > normalize(recognized).count
                if (ellipsis && !source.contains("…") && !source.contains("...")) ||
                    (shorter && line.confidence >= 0.5 && normalize(source).contains(normalize(recognized))) {
                    results.append(.init(rule: "rendered-truncation", rect: line.frame, subject: source,
                                         detail: "recognized “\(line.text)” is shorter than its source; \(geometry)"))
                }
            }
            let crossesOwner = owner.map { !$0.frame.insetBy(dx: -1, dy: -1).contains(inkFrame) } ?? false
            if crossesOwner || !c.capture.frame.insetBy(dx: -1, dy: -1).contains(inkFrame) {
                results.append(.init(rule: "rendered-text-geometry", rect: line.frame, subject: line.text,
                                     detail: "recognized glyph ink crosses its owner or window boundary; \(geometry)"))
            }
            for other in c.lines.dropFirst(index + 1) where !c.excluded(other.frame, includingNativeControlChrome: false) {
                // Recognition boxes include padding between distinct baselines. Compare the
                // same measured glyph bounds used for owner containment, not that padding.
                let otherInkFrame = c.inkFrame(other)
                let intersection = inkFrame.intersection(otherInkFrame)
                if intersection.width > 1 && intersection.height > 1 {
                    results.append(.init(rule: "rendered-text-geometry", rect: intersection, subject: line.text,
                                         detail: "recognized glyph ink overlaps; \(geometry); otherRecognizedBox=\(other.frame) otherInkFrame=\(otherInkFrame)"))
                }
            }
        }
        return results
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let frame: CGRect
        let sx: CGFloat
        let sy: CGFloat
        let fullBleedBackgrounds: [LumenFullBleedBackground]
        let fullBleedPaths: [CGPath?]
        let fullBleedWashes: [LumenFullBleedLinearWash]
        let nativeMasks: [CGRect]
        let nativeMaskPreservingInk: [CGRect]
        init(_ capture: Capture) throws {
            width = capture.image.width; height = capture.image.height; frame = capture.frame
            fullBleedBackgrounds = capture.fullBleedBackgrounds
            fullBleedPaths = capture.fullBleedBackgrounds.map { fill in
                fill.cornerRadius > 0 ? LumenTabChrome.shape(radius: fill.cornerRadius).path(in: fill.frame).cgPath : nil
            }
            fullBleedWashes = capture.fullBleedWashes
            nativeMasks = capture.nativeControlChrome
            nativeMaskPreservingInk = capture.nativeMaskPreservingInk
            sx = CGFloat(width) / frame.width; sy = CGFloat(height) / frame.height
            let width = capture.image.width, height = capture.image.height
            var storage = [UInt8](repeating: 0, count: width * height * 4)
            let success = storage.withUnsafeMutableBytes { data -> Bool in
                guard let context = CGContext(data: data.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(capture.image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard success else { throw Failure.missingImage }
            bytes = storage
        }
        func region(_ rect: CGRect) -> (Int, Int, Int, Int) {
            guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return (0,0,0,0) }
            let clipped = rect.intersection(frame)
            guard !clipped.isNull, !clipped.isEmpty else { return (0,0,0,0) }
            return (max(0, min(width, Int(floor((clipped.minX - frame.minX) * sx)))),
                    max(0, min(height, Int(floor((frame.maxY - clipped.maxY) * sy)))),
                    max(0, min(width, Int(ceil((clipped.maxX - frame.minX) * sx)))),
                    max(0, min(height, Int(ceil((frame.maxY - clipped.minY) * sy)))))
        }
        func color(_ x: Int, _ y: Int) -> Int {
            let i = (y * width + x) * 4
            return ((Int(bytes[i]) / 16) << 8) | ((Int(bytes[i + 1]) / 16) << 4) | (Int(bytes[i + 2]) / 16)
        }
        func background(_ rect: CGRect, excluding: CGRect? = nil,
                        accepting: (CGPoint) -> Bool = { _ in true }) -> Int {
            let (x0, y0, x1, y1) = region(rect)
            guard x1 > x0, y1 > y0 else { return 0 }
            var counts: [Int: Int] = [:]
            let excluded = excluding.map { region($0) }
            let step = max(1, Int(sqrt(Double((x1-x0) * (y1-y0)) / 4096)))
            for y in stride(from: y0, to: y1, by: step) {
                for x in stride(from: x0, to: x1, by: step) {
                    if let e = excluded, x >= e.0, x < e.2, y >= e.1, y < e.3 { continue }
                    guard accepting(point(x, y)) else { continue }
                    counts[color(x, y), default: 0] += 1
                }
            }
            // A narrow owned strip may fall between every coarse sample. Estimate
            // its actual surface instead of treating the empty histogram as black.
            if counts.isEmpty && step > 1 {
                for y in y0..<y1 { for x in x0..<x1 {
                    if let e = excluded, x >= e.0, x < e.2, y >= e.1, y < e.3 { continue }
                    guard accepting(point(x, y)) else { continue }
                    counts[color(x, y), default: 0] += 1
                } }
            }
            return counts.max { $0.value < $1.value }?.key ?? 0
        }
        func point(_ x: Int, _ y: Int) -> CGPoint {
            CGPoint(x: frame.minX + (CGFloat(x) + 0.5) / sx,
                    y: frame.maxY - (CGFloat(y) + 0.5) / sy)
        }
        func ink(_ x: Int, _ y: Int, _ background: Int, surface: [Int?]? = nil) -> Bool {
            let i = (y * width + x) * 4
            guard bytes[i + 3] > 220 else { return false }
            // A declared pigment is a local background, not an excluded rectangle.
            // Apply the same contrast test to every overlaid glyph, symbol and stroke.
            let location = point(x, y)
            var backgroundFill: LumenFullBleedBackground?
            for (index, fill) in fullBleedBackgrounds.enumerated() where fill.frame.contains(location) {
                // A current-line band paints the same continuous rounded path as its
                // shared row. Transparent corners never claim the full pigment.
                if let path = fullBleedPaths[index], !path.contains(location) { continue }
                if backgroundFill.map({ fill.frame.width * fill.frame.height < $0.frame.width * $0.frame.height }) ?? true {
                    backgroundFill = fill
                }
            }
            if let fill = backgroundFill {
                var red = Double(fill.red), green = Double(fill.green), blue = Double(fill.blue)
                // plusLighter adds premultiplied source pigment to the opaque destination.
                // Only declared background paint contributes; foreground still faces the
                // unchanged contrast test against this composited local background.
                for wash in fullBleedWashes where wash.frame.contains(location) {
                    let contribution = wash.contribution(at: location)
                    red = min(255, red + contribution.0)
                    green = min(255, green + contribution.1)
                    blue = min(255, blue + contribution.2)
                }
                return max(abs(Int(bytes[i]) - Int(red.rounded())), abs(Int(bytes[i + 1]) - Int(green.rounded())),
                           abs(Int(bytes[i + 2]) - Int(blue.rounded()))) >= 20
            }
            let local = surface?[y]
            let r = local.map { ($0 >> 16) & 255 } ?? ((background >> 8) * 16 + 8)
            let g = local.map { ($0 >> 8) & 255 } ?? (((background >> 4) & 15) * 16 + 8)
            let b = local.map { $0 & 255 } ?? ((background & 15) * 16 + 8)
            return max(abs(Int(bytes[i])-r), abs(Int(bytes[i+1])-g), abs(Int(bytes[i+2])-b)) >= 20
        }
        /// A slowly varying surface is not foreground just because it differs from a window-wide
        /// histogram mode. Estimate each row from the full owning surface, never the narrow tested
        /// margin. A robust full-height color trend prevents narrow residual ownership or
        /// a horizontal foreground stripe from defining its own local background.
        func surfaceBackgrounds(in rect: CGRect, accepting: (CGPoint) -> Bool) -> [Int?] {
            let (x0, y0, x1, y1) = region(rect)
            var rows = [Int?](repeating: nil, count: height)
            var coverage = [Double](repeating: 0, count: height)
            guard x1 > x0, y1 > y0 else { return rows }
            let step = max(1, (x1 - x0) / 128)
            for y in y0..<y1 {
                var channels = [[Int]](repeating: [], count: 3)
                func sample(_ x: Int) {
                    guard accepting(point(x, y)) else { return }
                    let i = (y * width + x) * 4
                    guard bytes[i + 3] > 220 else { return }
                    for channel in 0..<3 { channels[channel].append(Int(bytes[i + channel])) }
                }
                for x in stride(from: x0, to: x1, by: step) { sample(x) }
                var sampleWidth = step
                if channels[0].isEmpty && step > 1 {
                    sampleWidth = 1
                    for x in x0..<x1 { sample(x) }
                }
                guard !channels[0].isEmpty else { continue }
                coverage[y] = Double(channels[0].count * sampleWidth)
                let median = channels.map { $0.sorted()[$0.count / 2] }
                rows[y] = (median[0] << 16) | (median[1] << 8) | median[2]
            }
            // Use separated rows across the entire owned height, not just adjacent rows:
            // the interior of a thick foreground stripe is locally smooth too. Median
            // pairwise slopes and residuals tolerate isolated ink and mild nonlinearity.
            let occupied = (y0..<y1).filter { rows[$0] != nil }
            guard occupied.count >= 3 else { return [Int?](repeating: nil, count: height) }
            let rowStep = max(1, occupied.count / 32)
            let samples = stride(from: 0, to: occupied.count, by: rowStep).compactMap { index in
                let area = occupied[index..<min(occupied.count, index + rowStep)].reduce(0) { $0 + coverage[$1] }
                return rows[occupied[index]].map { (y: occupied[index], color: $0, area: area) }
            }
            func weightedMedian(_ values: [(value: Double, weight: Double)]) -> Double {
                let sorted = values.sorted { $0.value < $1.value }
                let midpoint = sorted.reduce(0) { $0 + $1.weight } / 2
                var accumulated = 0.0
                for sample in sorted {
                    accumulated += sample.weight
                    if accumulated >= midpoint { return sample.value }
                }
                return 0
            }
            let trends: [(Double, Double)] = [16, 8, 0].map { shift in
                func channel(_ color: Int) -> Double { Double((color >> shift) & 255) }
                var slopes: [(value: Double, weight: Double)] = []
                for (index, first) in samples.enumerated() {
                    for last in samples.dropFirst(index + 1) {
                        slopes.append(((channel(last.color) - channel(first.color)) / Double(last.y - first.y),
                                       first.area * last.area))
                    }
                }
                let slope = weightedMedian(slopes)
                // Area weighting matters when a nested owner leaves only thin strips in
                // most rows but a broad background header in the remaining rows.
                let residuals = occupied.compactMap { y in
                    rows[y].map { (value: channel($0) - slope * Double(y), weight: coverage[y]) }
                }
                return (slope, weightedMedian(residuals))
            }
            var smooth = [Int?](repeating: nil, count: height)
            for y in y0..<y1 {
                guard let color = rows[y] else { continue }
                guard [16, 8, 0].enumerated().allSatisfy({ index, shift in
                    abs(Double((color >> shift) & 255) - (trends[index].0 * Double(y) + trends[index].1)) <= 8
                }) else { continue }
                smooth[y] = color
            }
            return smooth
        }
        func inkCount(in rect: CGRect) -> Int {
            let (x0, y0, x1, y1) = region(rect)
            guard x1 > x0, y1 > y0 else { return 0 }
            let bg = background(rect.insetBy(dx: -3, dy: -3))
            var count = 0
            for y in y0..<y1 { for x in x0..<x1 where ink(x, y, bg) { count += 1 } }
            return count
        }
        func inkBounds(in rect: CGRect) -> CGRect? {
            let (x0, y0, x1, y1) = region(rect)
            guard x1 > x0, y1 > y0 else { return nil }
            let bg = background(rect.insetBy(dx: -3, dy: -3))
            var left = x1, top = y1, right = x0, bottom = y0
            for y in y0..<y1 { for x in x0..<x1 where ink(x, y, bg) {
                left = min(left, x); top = min(top, y)
                right = max(right, x + 1); bottom = max(bottom, y + 1)
            } }
            guard right > left, bottom > top else { return nil }
            return screenRect(left, top, right, bottom)
        }

        func unexcludedInk(in rect: CGRect, exclusions: [CGRect]) -> Int {
            let (x0,y0,x1,y1) = region(rect)
            guard x1 > x0, y1 > y0 else { return 0 }
            let bg = background(rect.insetBy(dx: -3, dy: -3))
            for y in y0..<y1 { for x in x0..<x1 where ink(x,y,bg) {
                let point = CGPoint(x: frame.minX + (CGFloat(x)+0.5)/sx,
                                    y: frame.maxY - (CGFloat(y)+0.5)/sy)
                if !exclusions.contains(where: { $0.contains(point) }) { return 1 }
            } }
            return 0
        }
        func screenRect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> CGRect {
            CGRect(x: frame.minX + CGFloat(x0) / sx, y: frame.maxY - CGFloat(y1) / sy,
                   width: CGFloat(x1-x0) / sx, height: CGFloat(y1-y0) / sy)
        }
        func components(in rect: CGRect, excludingBackground: CGRect? = nil,
                        background: (() -> Int)? = nil, surface: (() -> [Int?])? = nil,
                        accepting: (CGPoint) -> Bool = { _ in true }) -> [CGRect] {
            let (x0, y0, x1, y1) = region(rect)
            guard x1 > x0, y1 > y0 else { return [] }
            var bg = 0
            func accepted(_ x: Int, _ y: Int) -> Bool {
                let location = point(x, y)
                return accepting(location) && (!nativeMasks.contains { $0.contains(location) }
                    || nativeMaskPreservingInk.contains { $0.contains(location) })
            }
            var visited = Set<Int>(), result: [CGRect] = []
            var resolvedSurface = false
            var localSurface: [Int?]?
            for y in y0..<y1 { for x in x0..<x1 {
                let start = y * width + x
                guard !visited.contains(start), accepted(x, y) else { continue }
                if !resolvedSurface {
                    bg = background?() ?? self.background(rect, excluding: excludingBackground, accepting: { location in
                        accepting(location) && !nativeMasks.contains { $0.contains(location) }
                    })
                    localSurface = surface?()
                    resolvedSurface = true
                }
                guard ink(x, y, bg, surface: localSurface) else { continue }
                var queue = [start], cursor = 0, minX = x, maxX = x, minY = y, maxY = y
                visited.insert(start)
                while cursor < queue.count {
                    let p = queue[cursor]; cursor += 1
                    let px = p % width, py = p / width
                    minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
                    for (nx, ny) in [(px-1,py),(px+1,py),(px,py-1),(px,py+1)] {
                        guard nx >= x0, nx < x1, ny >= y0, ny < y1 else { continue }
                        let next = ny * width + nx
                        if !visited.contains(next), accepted(nx, ny), ink(nx,ny,bg, surface: localSurface) { visited.insert(next); queue.append(next) }
                    }
                }
                if queue.count >= 5 { result.append(screenRect(minX,minY,maxX+1,maxY+1)) }
            } }
            return result
        }
        func glyphCuts(at clip: CGRect, line: CGRect) -> [CGRect] {
            let (x0, _, x1, _) = region(clip)
            let (textX0, y0, textX1, y1) = region(line.insetBy(dx: 0, dy: -1).intersection(clip))
            guard x1 - x0 >= 3, y1 > y0 else { return [] }
            let bg = background(line.insetBy(dx: -6, dy: -6))
            var result: [CGRect] = []
            for (x, adjacent, close) in [(x0, x0+1, abs(line.minX-clip.minX) < 2),
                                       (x1-1, x1-2, abs(line.maxX-clip.maxX) < max(3, line.height))] where close && x >= textX0 && x < textX1 && adjacent >= textX0 && adjacent < textX1 {
                let ys = (y0..<y1).filter { ink(x,$0,bg) && ink(adjacent,$0,bg) }
                // A complete leading A or V can have a one-point antialiased tip on the
                // clip edge. Require a contour segment, not that isolated terminal touch.
                let minimumContinuation = max(2, Int(ceil(1.5 * sy)))
                if let first = ys.first, let last = ys.last, ys.count >= minimumContinuation {
                    result.append(screenRect(min(x,adjacent),first,max(x,adjacent)+1,last+1))
                }
            }
            return result
        }
        func boundaryContinuations(_ rect: CGRect, surface: () -> [Int?], background: () -> Int,
                                   accepting: (CGPoint) -> Bool) -> [CGRect] {
            let (x0,y0,x1,y1) = region(rect)
            guard x1-x0 > 8, y1-y0 > 8 else { return [] }
            let boundaries = [
                (((x0+4)..<(x1-4)).map { ($0,y0) }, ((x0+4)..<(x1-4)).map { ($0,y0+6) }),
                (((x0+4)..<(x1-4)).map { ($0,y1-1) }, ((x0+4)..<(x1-4)).map { ($0,y1-7) }),
                (((y0+4)..<(y1-4)).map { (x0,$0) }, ((y0+4)..<(y1-4)).map { (x0+6,$0) }),
                (((y0+4)..<(y1-4)).map { (x1-1,$0) }, ((y0+4)..<(y1-4)).map { (x1-7,$0) }),
            ].map { border, inner in
                (border.filter { accepting(point($0.0, $0.1)) },
                 inner.filter { accepting(point($0.0, $0.1)) })
            }
            // Fully covered owners have no boundary pixels and need no histogram.
            guard boundaries.contains(where: { $0.0.count >= 3 && $0.1.count >= 3 }) else { return [] }
            let bg = background()
            let localSurface = surface()
            var points: [(Int,Int)] = []
            // A clipped contour has a broad flat cut; a complete ellipse only touches its
            // frame tangentially. Compare the last row with parallel rows deeper inside.
            func boundary(_ border: [(Int, Int)], _ inner: [(Int, Int)]) {
                let outerInk = border.filter { ink($0.0, $0.1, bg, surface: localSurface) }
                let innerInk = inner.filter { ink($0.0, $0.1, bg, surface: localSurface) }
                func runs(_ pixels: [(Int, Int)]) -> [[(Int, Int)]] {
                    var result: [[(Int, Int)]] = []
                    for pixel in pixels {
                        if let last = result.last?.last,
                           abs(pixel.0 - last.0) + abs(pixel.1 - last.1) == 1 {
                            result[result.count - 1].append(pixel)
                        } else { result.append([pixel]) }
                    }
                    return result
                }
                let horizontal = border.first?.1 == border.last?.1
                func span(_ run: [(Int, Int)]) -> ClosedRange<Int>? {
                    guard let first = run.first, let last = run.last else { return nil }
                    return horizontal ? first.0...last.0 : first.1...last.1
                }
                let innerRuns = runs(innerInk)
                for run in runs(outerInk) where run.count >= 3 {
                    guard let outerSpan = span(run) else { continue }
                    let innerCount = innerRuns.filter {
                        span($0).map { $0.overlaps(outerSpan) } ?? false
                    }.reduce(0) { $0 + $1.count }
                    // Separate thin rules touching an edge do not form one clipped contour.
                    // Count the complete matching inward run so a tangent ellipse still passes.
                    if innerCount >= 3, Double(run.count) >= Double(innerCount) * 0.75 {
                        points += run
                    }
                }
            }
            for (border, inner) in boundaries { boundary(border, inner) }
            guard points.count >= 3 else { return [] }
            return [screenRect(points.map(\.0).min()!,points.map(\.1).min()!,
                               points.map(\.0).max()!+1,points.map(\.1).max()!+1)]
        }
    }
}
#endif
