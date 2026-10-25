import AppIntents
import XCTest
import LumenUI
@testable import LumenIntents

@MainActor
final class LumenCommandIntentTests: XCTestCase {
    @MainActor private final class CommandState {
        var calls = 0
        var enabled = true
        var increment = 1
    }

    func testEntityListPreservesIDsTitlesAndSymbols() async throws {
        let commands = [
            LumenCommand(id: "colors", "Show Colors", category: "View", systemImage: "paintpalette") {},
            LumenCommand(id: "inspector", "Toggle Inspector", category: "View", systemImage: "sidebar.trailing") {},
            LumenCommand(id: "palette", "Open Command Palette", category: "View", systemImage: "command") {},
        ]
        LumenIntentCommands.configure { commands }
        let entities = try await LumenCommandQuery().suggestedEntities()
        XCTAssertEqual(entities.map(\.id), commands.map(\.id))
        XCTAssertEqual(entities.map(\.title), commands.map(\.title))
        XCTAssertEqual(entities.map(\.systemImage), commands.map(\.systemImage))
        for entity in entities {
            XCTAssertEqual(String(localized: entity.displayRepresentation.title), entity.title)
            XCTAssertEqual(entity.displayRepresentation.image, .init(systemName: entity.systemImage))
        }
    }

    func testIntentPerformsTheSameActionAsTheCommand() async throws {
        var calls = 0
        let command = LumenCommand(id: "shared", "Shared Action", category: "View", systemImage: "command") { calls += 1 }
        LumenIntentCommands.configure { [command] }
        command.perform()
        let entity = try XCTUnwrap(LumenIntentCommands.entities().first)
        _ = try await LumenCommandIntent(command: entity).perform()
        XCTAssertEqual(calls, 2)
    }

    func testExecutionResolvesCurrentActionAndEnabledState() async throws {
        let state = CommandState()
        LumenIntentCommands.configure {
            let current = state.increment
            return [LumenCommand(id: "live", "Live Action", category: "View", systemImage: "command", isEnabled: state.enabled) {
                state.calls += current
            }]
        }
        let entity = try XCTUnwrap(LumenIntentCommands.entities().first)
        state.increment = 10
        _ = try await LumenCommandIntent(command: entity).perform()
        XCTAssertEqual(state.calls, 10)
        state.enabled = false
        XCTAssertThrowsError(try LumenIntentCommands.perform(id: entity.id)) {
            XCTAssertEqual($0 as? LumenCommandIntentError, .disabled("live"))
        }
        XCTAssertEqual(state.calls, 10)
    }

    func testRemovedAndDuplicateIDsFailExplicitly() throws {
        LumenIntentCommands.configure { [] }
        XCTAssertThrowsError(try LumenIntentCommands.perform(id: "gone")) {
            XCTAssertEqual($0 as? LumenCommandIntentError, .unavailable("gone"))
        }
        let command = LumenCommand(id: "same", "Duplicate", category: "View", systemImage: "command") {}
        LumenIntentCommands.configure { [command, command] }
        XCTAssertThrowsError(try LumenIntentCommands.entities()) {
            XCTAssertEqual($0 as? LumenCommandIntentError, .duplicateID("same"))
        }
    }

    func testQueryRestoresIDsInRequestedOrderAndSearchesTitles() async throws {
        LumenIntentCommands.configure {
            ["Colors", "Inspector"].map { title in
                LumenCommand(id: title.lowercased(), title, category: "View", systemImage: "command") {}
            }
        }
        let query = LumenCommandQuery()
        let restored = try await query.entities(for: ["inspector", "missing", "colors"])
        XCTAssertEqual(restored.map(\.id), ["inspector", "colors"])
        let matches = try await query.entities(matching: "COLOR")
        XCTAssertEqual(matches.map(\.id), ["colors"])
    }

    func testLumenGlyphUsesRenderedImageAndUnknownGlyphFails() throws {
        let entity = try LumenCommandEntity(command:
            LumenCommand(id: "glyph", "Call Graph", category: "View", systemImage: "lumen.callGraph") {})
        XCTAssertEqual(entity.systemImage, "lumen.callGraph")
        XCTAssertNotNil(entity.displayRepresentation.image)
        XCTAssertNotEqual(entity.displayRepresentation.image, .init(systemName: "lumen.callGraph"))
        XCTAssertThrowsError(try LumenCommandEntity(command:
            LumenCommand(id: "missing", "Missing", category: "View", systemImage: "lumen.unknown") {})) {
            XCTAssertEqual($0 as? LumenCommandIntentError, .missingSymbol("lumen.unknown"))
        }
    }
}
