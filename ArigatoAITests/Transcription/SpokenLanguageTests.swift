//
//  SpokenLanguageTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("SpokenLanguage parsing and metadata")
struct SpokenLanguageTests {
    @Test("init(whisperCode:) accepts \"ja\"")
    func initWhisperCode_jaIsAccepted() {
        #expect(SpokenLanguage(whisperCode: "ja") == .ja)
    }

    @Test("init(whisperCode:) accepts \"en\"")
    func initWhisperCode_enIsAccepted() {
        #expect(SpokenLanguage(whisperCode: "en") == .en)
    }

    @Test("init(whisperCode:) normalises uppercase input")
    func initWhisperCode_uppercaseIsNormalized() {
        #expect(SpokenLanguage(whisperCode: "JA") == .ja)
    }

    @Test("init(whisperCode:) trims surrounding whitespace")
    func initWhisperCode_whitespaceIsTrimmed() {
        #expect(SpokenLanguage(whisperCode: " en ") == .en)
    }

    @Test("init(whisperCode:) returns nil for unsupported ISO 639-1 codes")
    func initWhisperCode_unsupportedReturnsNil() {
        #expect(SpokenLanguage(whisperCode: "fr") == nil)
        #expect(SpokenLanguage(whisperCode: "zh") == nil)
        #expect(SpokenLanguage(whisperCode: "de") == nil)
        #expect(SpokenLanguage(whisperCode: "ko") == nil)
    }

    @Test("init(whisperCode:) returns nil for empty string")
    func initWhisperCode_emptyReturnsNil() {
        #expect(SpokenLanguage(whisperCode: "") == nil)
    }

    @Test("init(whisperCode:) returns nil for ISO 639-2 codes")
    func initWhisperCode_iso639_2ReturnsNil() {
        #expect(SpokenLanguage(whisperCode: "jpn") == nil)
    }

    @Test("init(whisperCode:) returns nil for BCP-47 tags")
    func initWhisperCode_bcp47ReturnsNil() {
        #expect(SpokenLanguage(whisperCode: "ja-JP") == nil)
    }

    @Test("rawValue matches the lowercase Whisper code")
    func rawValue_matchesWhisperCode() {
        #expect(SpokenLanguage.ja.rawValue == "ja")
        #expect(SpokenLanguage.en.rawValue == "en")
    }

    @Test("Codable round-trips as a lowercase JSON string")
    func codable_roundTripsAsLowercaseString() throws {
        let json = Data("\"ja\"".utf8)
        let decoded = try JSONDecoder().decode(SpokenLanguage.self, from: json)
        #expect(decoded == .ja)

        let encoded = try JSONEncoder().encode(SpokenLanguage.en)
        let encodedString = String(decoding: encoded, as: UTF8.self)
        #expect(encodedString == "\"en\"")
    }

    @Test("displayName is human-readable and unique per case")
    func displayName_isHumanReadable() {
        let names = SpokenLanguage.allCases.map(\.displayName)
        for name in names {
            #expect(!name.isEmpty)
        }
        #expect(Set(names).count == names.count)
    }

    @Test("bcp47 returns expected region-qualified locale identifiers")
    func bcp47_matchesExpected() {
        #expect(SpokenLanguage.ja.bcp47 == "ja-JP")
        #expect(SpokenLanguage.en.bcp47 == "en-US")
    }

    @Test("CaseIterable contains exactly ja and en")
    func caseIterable_containsExactlyJaAndEn() {
        #expect(SpokenLanguage.allCases == [.ja, .en])
    }
}
