//
//  TranslatedSegmentTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/12.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("TranslatedSegment value semantics")
struct TranslatedSegmentTests {
    private func makeSegment(
        id: UUID = UUID(),
        sourceSegmentID: UUID = UUID(),
        sourceText: String = "hello",
        translatedText: String = "こんにちは",
        direction: TranslationDirection = .enToJa,
        startHostTime: UInt64 = 1000,
        endHostTime: UInt64 = 2000,
        isFallback: Bool = false
    ) -> TranslatedSegment {
        TranslatedSegment(
            id: id,
            sourceSegmentID: sourceSegmentID,
            sourceText: sourceText,
            translatedText: translatedText,
            direction: direction,
            startHostTime: startHostTime,
            endHostTime: endHostTime,
            isFallback: isFallback
        )
    }

    @Test("init assigns every field, including sourceSegmentID and isFallback")
    func init_assignsAllFields() {
        let id = UUID()
        let sourceID = UUID()
        let segment = TranslatedSegment(
            id: id,
            sourceSegmentID: sourceID,
            sourceText: "hello",
            translatedText: "こんにちは",
            direction: .enToJa,
            startHostTime: 42,
            endHostTime: 100,
            isFallback: true
        )
        #expect(segment.id == id)
        #expect(segment.sourceSegmentID == sourceID)
        #expect(segment.sourceText == "hello")
        #expect(segment.translatedText == "こんにちは")
        #expect(segment.direction == .enToJa)
        #expect(segment.startHostTime == 42)
        #expect(segment.endHostTime == 100)
        #expect(segment.isFallback == true)
    }

    @Test("init defaults id to a fresh UUID per instance")
    func init_defaultsIdToFreshUUID() {
        let sourceID = UUID()
        let a = TranslatedSegment(
            sourceSegmentID: sourceID,
            sourceText: "x",
            translatedText: "y",
            direction: .jaToEn,
            startHostTime: 0,
            endHostTime: 1,
            isFallback: false
        )
        let b = TranslatedSegment(
            sourceSegmentID: sourceID,
            sourceText: "x",
            translatedText: "y",
            direction: .jaToEn,
            startHostTime: 0,
            endHostTime: 1,
            isFallback: false
        )
        #expect(a.id != b.id)
    }

    @Test("TranslatedSegment can cross an actor boundary")
    func segment_crossesActorBoundary() async {
        actor Receiver {
            private var received: TranslatedSegment?
            func receive(_ segment: TranslatedSegment) {
                received = segment
            }

            func last() -> TranslatedSegment? {
                received
            }
        }

        let receiver = Receiver()
        let segment = makeSegment(sourceText: "actor-bound")
        await receiver.receive(segment)
        let echoed = await receiver.last()
        #expect(echoed == segment)
    }
}
