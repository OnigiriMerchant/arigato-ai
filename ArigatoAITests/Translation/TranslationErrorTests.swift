//
//  TranslationErrorTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/12.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("TranslationError shape and conformances")
struct TranslationErrorTests {
    @Test("localizedDescription for modelLoadFailed includes the detail string")
    func localizedDescription_modelLoadFailed_includesDetail() {
        let error = TranslationError.modelLoadFailed("disk full")
        let description = error.localizedDescription
        #expect(description.contains("disk full"))
    }

    @Test("localizedDescription for each case is non-empty")
    func localizedDescription_eachCase_isNonEmpty() {
        let cases: [TranslationError] = [
            .modelLoadFailed("x"),
            .modelNotReady,
            .generationFailed("y"),
            .overlappingGenerationRejected,
            .unsupportedDirection(source: .ja, target: .ja),
            .warmupFailed("z"),
        ]
        for error in cases {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("Equatable: same case with same detail is equal")
    func equatable_sameCaseSameDetail_isEqual() {
        #expect(TranslationError.modelLoadFailed("x") == TranslationError.modelLoadFailed("x"))
        #expect(TranslationError.generationFailed("a") == TranslationError.generationFailed("a"))
        #expect(TranslationError.warmupFailed("b") == TranslationError.warmupFailed("b"))
        #expect(
            TranslationError.unsupportedDirection(source: .ja, target: .ja)
                == TranslationError.unsupportedDirection(source: .ja, target: .ja)
        )
        #expect(TranslationError.modelNotReady == TranslationError.modelNotReady)
        #expect(
            TranslationError.overlappingGenerationRejected
                == TranslationError.overlappingGenerationRejected
        )
    }

    @Test("Equatable: same case with different detail is not equal")
    func equatable_sameCaseDifferentDetail_isNotEqual() {
        #expect(TranslationError.modelLoadFailed("x") != TranslationError.modelLoadFailed("y"))
        #expect(TranslationError.generationFailed("a") != TranslationError.generationFailed("b"))
        #expect(TranslationError.warmupFailed("a") != TranslationError.warmupFailed("b"))
        #expect(
            TranslationError.unsupportedDirection(source: .ja, target: .ja)
                != TranslationError.unsupportedDirection(source: .en, target: .en)
        )
    }

    @Test("TranslationError can cross an actor boundary by throw")
    func crossesActorBoundary_byThrow() async {
        actor Thrower {
            func boom() throws {
                throw TranslationError.modelNotReady
            }
        }

        let thrower = Thrower()
        do {
            try await thrower.boom()
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            #expect(error == .modelNotReady)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
