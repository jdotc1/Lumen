import AppIntents
import AppKit
import SwiftUI
import LumenUI

/// Include this package in the host app's `AppIntentsPackage.includedPackages`.
public struct LumenIntentsPackage: AppIntentsPackage {}

/// Failures are explicit: a saved shortcut never runs a removed or disabled command.
public enum LumenCommandIntentError: Error, LocalizedError, Equatable {
    case notConfigured
    case duplicateID(String)
    case unavailable(String)
    case disabled(String)
    case missingSymbol(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "The app has not configured its Lumen commands."
        case .duplicateID(let id): "More than one Lumen command has the identifier \(id)."
        case .unavailable(let id): "The command \(id) is no longer available."
        case .disabled(let id): "The command \(id) is currently disabled."
        case .missingSymbol(let name): "The command symbol \(name) could not be rendered."
        }
    }
}

/// One app-owned source of commands. Install during app initialization, before entity queries.
/// The provider is evaluated again at execution, so enabled state and actions cannot go stale.
@MainActor
public enum LumenIntentCommands {
    private static var provider: (@MainActor () -> [LumenCommand])?

    public static func configure(_ commands: @escaping @MainActor () -> [LumenCommand]) {
        provider = commands
    }

    /// All entries, including disabled ones; the menu, palette and intent share their identity.
    public static func entities() throws -> [LumenCommandEntity] {
        try commands().map { try LumenCommandEntity(command: $0) }
    }

    public static func perform(id: String) throws {
        guard let command = try commands().first(where: { $0.id == id }) else {
            throw LumenCommandIntentError.unavailable(id)
        }
        guard command.isEnabled else { throw LumenCommandIntentError.disabled(id) }
        command.perform()
    }

    private static func commands() throws -> [LumenCommand] {
        guard let provider else { throw LumenCommandIntentError.notConfigured }
        let commands = provider()
        var seen: Set<String> = []
        for command in commands where !seen.insert(command.id).inserted {
            throw LumenCommandIntentError.duplicateID(command.id)
        }
        return commands
    }
}

/// A metadata snapshot, never a captured action. Keep command IDs stable across app versions.
public struct LumenCommandEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Lumen Command" }
    public static var defaultQuery: LumenCommandQuery { LumenCommandQuery() }

    public let id: String
    public let title: String
    /// The original Lumen glyph or SF Symbol name, unchanged from the command.
    public let systemImage: String
    private let image: DisplayRepresentation.Image

    @MainActor
    public init(command: LumenCommand) throws {
        id = command.id
        title = command.title
        systemImage = command.systemImage
        if systemImage.hasPrefix("lumen.") {
            guard LumenGlyph.named(systemImage) != nil,
                  let rendered = LumenIconTile.image(systemImage, hue: command.hue, size: 32, colorScheme: .light),
                  let tiff = rendered.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw LumenCommandIntentError.missingSymbol(systemImage)
            }
            image = .init(data: png, isTemplate: false)
        } else {
            image = .init(systemName: systemImage)
        }
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: image)
    }
}

public struct LumenCommandQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [LumenCommandEntity] {
        let entities = try await LumenIntentCommands.entities()
        return identifiers.compactMap { id in entities.first { $0.id == id } }
    }

    public func entities(matching string: String) async throws -> [LumenCommandEntity] {
        try await LumenIntentCommands.entities().filter {
            string.isEmpty || $0.title.localizedStandardContains(string)
        }
    }

    public func suggestedEntities() async throws -> [LumenCommandEntity] {
        try await LumenIntentCommands.entities()
    }
}

/// One statically discoverable action with a dynamically queried command parameter.
/// The host supplies a literal `AppShortcutsProvider`; individual commands are entity choices,
/// not dynamically synthesized intent types or shortcut tiles.
public struct LumenCommandIntent: AppIntent {
    public static var title: LocalizedStringResource { "Run Lumen Command" }
    public static var supportedModes: IntentModes { .foreground }
    public static var parameterSummary: some ParameterSummary { Summary("Run \(\.$command)") }

    @Parameter(title: "Command") public var command: LumenCommandEntity

    public init() {}

    public init(command: LumenCommandEntity) {
        self.command = command
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try LumenIntentCommands.perform(id: command.id)
        return .result()
    }
}
