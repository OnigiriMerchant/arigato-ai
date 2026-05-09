//
//  TranscriptionErrorTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("TranscriptionError shape and conformances")
struct TranscriptionErrorTests {
    @Test("localizedDescription for modelLoadFailed includes the detail string")
    func localizedDescription_modelLoadFailedIncludesDetail() {
        let error = TranscriptionError.modelLoadFailed("disk full")
        let description = error.localizedDescription
        #expect(description.contains("disk full"))
    }

    @Test("localizedDescription for each representative case is non-empty")
    func localizedDescription_eachCaseIsNonEmpty() {
        let cases: [TranscriptionError] = [
            .modelLoadFailed("x"),
            .modelNotReady,
            .decodeFailed("y"),
            .bufferUnderrun,
            .audioStreamEnded,
            .unsupportedSampleRate(44100),
        ]
        for error in cases {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("Equatable: same case with same detail is equal")
    func equatable_sameCaseSameDetailIsEqual() {
        #expect(TranscriptionError.modelLoadFailed("x") == TranscriptionError.modelLoadFailed("x"))
        #expect(TranscriptionError.decodeFailed("a") == TranscriptionError.decodeFailed("a"))
        #expect(TranscriptionError.unsupportedSampleRate(48000) == TranscriptionError.unsupportedSampleRate(48000))
    }

    @Test("Equatable: same case with different detail is not equal")
    func equatable_sameCaseDifferentDetailIsNotEqual() {
        #expect(TranscriptionError.modelLoadFailed("x") != TranscriptionError.modelLoadFailed("y"))
        #expect(TranscriptionError.unsupportedSampleRate(44100) != TranscriptionError.unsupportedSampleRate(48000))
    }

    @Test("Equatable: modelNotReady is equal to itself")
    func equatable_modelNotReadyIsEqualToItself() {
        #expect(TranscriptionError.modelNotReady == TranscriptionError.modelNotReady)
        #expect(TranscriptionError.bufferUnderrun == TranscriptionError.bufferUnderrun)
        #expect(TranscriptionError.audioStreamEnded == TranscriptionError.audioStreamEnded)
    }

    @Test("TranscriptionError can cross an actor boundary")
    func throwsAcrossActorBoundary() async {
        actor Thrower {
            func boom() throws {
                throw TranscriptionError.bufferUnderrun
            }
        }

        let thrower = Thrower()
        do {
            try await thrower.boom()
            Issue.record("Expected throw")
        } catch let error as TranscriptionError {
            #expect(error == .bufferUnderrun)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
