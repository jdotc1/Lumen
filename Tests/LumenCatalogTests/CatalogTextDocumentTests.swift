import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import LumenCatalog

@MainActor
final class CatalogTextDocumentTests: XCTestCase {
    func testUTF8FileWrapperRoundTripPreservesOriginalText() async throws {
        let original = "Field notes\nCafé — αβγ 🌿\n\nFinal line\n"
        let document = CatalogTextDocument(text: original)
        let snapshot = try await document.snapshot(contentType: .plainText)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "notes.txt")
        try CatalogTextDocument.encode(snapshot).write(to: url, options: .atomic, originalContentsURL: nil)
        let read = try CatalogTextDocument.decode(FileWrapper(url: url))
        let restored = CatalogTextDocument()
        try await restored.apply(snapshot: read, previous: nil)
        XCTAssertEqual(restored.text, original)
        let saved = try await restored.snapshot(contentType: .plainText)
        XCTAssertEqual(saved, original)
    }

    func testReadRejectsDirectoryAndInvalidUTF8() {
        XCTAssertThrowsError(try CatalogTextDocument.decode(FileWrapper(directoryWithFileWrappers: [:])))
        XCTAssertThrowsError(try CatalogTextDocument.decode(FileWrapper(regularFileWithContents: Data([0xFF, 0xFE]))))
        XCTAssertEqual(try CatalogTextDocument.decode(CatalogTextDocument.encode("")), "")
    }

    func testEditingRegistersUndoAndRedo() {
        let document = CatalogTextDocument(text: "Before")
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        document.replaceText("After", undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(document.text, "After")
        undo.undo()
        XCTAssertEqual(document.text, "Before")
        undo.redo()
        XCTAssertEqual(document.text, "After")
    }

    func testApplySnapshotReplacesEditedContentForRevert() async throws {
        let document = CatalogTextDocument(text: "Edited")
        try await document.apply(snapshot: "Saved", previous: "Original")
        XCTAssertEqual(document.text, "Saved")
    }
}
