//
//  ArigatoAIAppTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/25.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Guards the production SwiftData schema registration. The B1.6 bug was
/// that `ArigatoAIApp` registered `Schema([Item.self])` (the dead Xcode
/// scaffold) while `MeetingStore` persists `Meeting`/`Sentence` — so the
/// first production insert would have failed at runtime. No test exercised
/// the production container-construction path until this one (every
/// persistence test injects its own correct container).
@Suite("ArigatoAIApp production schema")
struct ArigatoAIAppTests {
    @Test("production container registers Meeting and Sentence entities")
    func productionContainer_registersMeetingAndSentence() throws {
        let schema = ArigatoAIApp.makeAppSchema()

        let schemaEntityNames = Set(schema.entities.map(\.name))
        #expect(schemaEntityNames.contains("Meeting"))
        #expect(schemaEntityNames.contains("Sentence"))
        // Exactly two entities — guards against a stray registration
        // (e.g. a resurrected `Item` scaffold) creeping back in.
        #expect(schemaEntityNames.count == 2)

        // Prove the schema materializes into a real container as well —
        // this is the construction the app performs at launch.
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let containerEntityNames = Set(container.schema.entities.map(\.name))
        #expect(containerEntityNames.contains("Meeting"))
        #expect(containerEntityNames.contains("Sentence"))
        #expect(containerEntityNames.count == 2)
    }
}
