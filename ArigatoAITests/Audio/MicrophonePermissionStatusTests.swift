//
//  MicrophonePermissionStatusTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import AVFAudio
import Testing

@Suite("MicrophonePermissionStatus mapping")
struct MicrophonePermissionStatusTests {
    @Test("undetermined maps to notDetermined")
    func undeterminedMapsToNotDetermined() {
        let status = MicrophonePermissionStatus(.undetermined)
        #expect(status == .notDetermined)
    }

    @Test("granted maps to granted")
    func grantedMapsToGranted() {
        let status = MicrophonePermissionStatus(.granted)
        #expect(status == .granted)
    }

    @Test("denied maps to denied")
    func deniedMapsToDenied() {
        let status = MicrophonePermissionStatus(.denied)
        #expect(status == .denied)
    }
}
