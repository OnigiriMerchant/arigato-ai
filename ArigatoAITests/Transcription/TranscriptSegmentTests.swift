//
//  TranscriptSegmentTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("TranscriptSegment value semantics and codability")
struct TranscriptSegmentTests {
    private func makeSegment(
        id: UUID = UUID(),
        text: String = "hello",
        language: SpokenLanguage = .en,
        startHostTime: UInt64 = 1000,
        endHostTime: UInt64 = 2000,
        startSeconds: Double = 0.0,
        endSeconds: Double = 1.0,
        isFinal: Bool = true,
        wasLanguageFallback: Bool = false
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            text: text,
            language: language,
            startHostTime: startHostTime,
            endHostTime: endHostTime,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            isFinal: isFinal,
            wasLanguageFallback: wasLanguageFallback
        )
    }

    @Test("init assigns every field")
    func init_assignsAllFields() {
        let id = UUID()
        let segment = TranscriptSegment(
            id: id,
            text: "こんにちは",
            language: .ja,
            startHostTime: 42,
            endHostTime: 100,
            startSeconds: 0.5,
            endSeconds: 1.25,
            isFinal: false,
            wasLanguageFallback: true
        )
        #expect(segment.id == id)
        #expect(segment.text == "こんにちは")
        #expect(segment.language == .ja)
        #expect(segment.startHostTime == 42)
        #expect(segment.endHostTime == 100)
        #expect(segment.startSeconds == 0.5)
        #expect(segment.endSeconds == 1.25)
        #expect(segment.isFinal == false)
        #expect(segment.wasLanguageFallback == true)
    }

    @Test("init defaults id to a fresh UUID")
    func init_defaultsIdToUUID() {
        let a = TranscriptSegment(
            text: "x",
            language: .en,
            startHostTime: 0,
            endHostTime: 1,
            startSeconds: 0,
            endSeconds: 1,
            isFinal: true,
            wasLanguageFallback: false
        )
        let b = TranscriptSegment(
            text: "x",
            language: .en,
            startHostTime: 0,
            endHostTime: 1,
            startSeconds: 0,
            endSeconds: 1,
            isFinal: true,
            wasLanguageFallback: false
        )
        #expect(a.id != b.id)
    }

    @Test("Equality: identical fields including id produce equal segments")
    func equality_identicalFieldsAreEqual() {
        let id = UUID()
        let a = makeSegment(id: id)
        let b = makeSegment(id: id)
        #expect(a == b)
    }

    @Test("Equality: different id produces different segments")
    func equality_differentIdMakesDifferentSegments() {
        let a = makeSegment()
        let b = makeSegment()
        #expect(a != b)
    }

    @Test("Hashable is consistent with Equatable")
    func hashable_consistentWithEquality() {
        let id = UUID()
        let a = makeSegment(id: id)
        let b = makeSegment(id: id)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Codable round-trips through JSON")
    func codable_roundTripsThroughJSON() throws {
        let original = makeSegment(
            text: "round trip",
            language: .ja,
            wasLanguageFallback: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable: language decodes from a lowercase JSON string")
    func codable_languageEncodesAsLowercaseString() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "text": "hi",
            "language": "ja",
            "startHostTime": 0,
            "endHostTime": 16000,
            "startSeconds": 0,
            "endSeconds": 1,
            "isFinal": true,
            "wasLanguageFallback": false
        }
        """
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: Data(json.utf8))
        #expect(decoded.language == .ja)
        #expect(decoded.id == id)
    }

    @Test("isFinal: both false and true are expressible")
    func isFinal_falseAndTrueAreBothExpressible() {
        let preliminary = makeSegment(isFinal: false)
        let final = makeSegment(isFinal: true)
        #expect(preliminary.isFinal == false)
        #expect(final.isFinal == true)
    }

    @Test("wasLanguageFallback flag propagates through init")
    func wasLanguageFallback_flagPropagates() {
        let normal = makeSegment(wasLanguageFallback: false)
        let fallback = makeSegment(wasLanguageFallback: true)
        #expect(normal.wasLanguageFallback == false)
        #expect(fallback.wasLanguageFallback == true)
    }

    @Test("TranscriptSegment can cross an actor boundary")
    func segment_crossesActorBoundary() async {
        actor Receiver {
            private var received: TranscriptSegment?
            func receive(_ segment: TranscriptSegment) {
                received = segment
            }

            func last() -> TranscriptSegment? {
                received
            }
        }

        let receiver = Receiver()
        let segment = makeSegment(text: "actor-bound")
        await receiver.receive(segment)
        let echoed = await receiver.last()
        #expect(echoed == segment)
    }
}
