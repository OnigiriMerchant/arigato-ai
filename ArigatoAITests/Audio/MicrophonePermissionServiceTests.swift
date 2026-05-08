//
//  MicrophonePermissionServiceTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

/// In-memory fake that conforms to ``MicrophonePermissionServicing`` and
/// drives state transitions deterministically for VM tests.
final class FakePermissionService: MicrophonePermissionServicing, @unchecked Sendable {
    private struct State {
        var current: MicrophonePermissionStatus
        var grantOnRequest: Bool
        var requestCallCount: Int = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(initial: MicrophonePermissionStatus, grantOnRequest: Bool = true) {
        state = OSAllocatedUnfairLock(
            initialState: State(current: initial, grantOnRequest: grantOnRequest)
        )
    }

    var requestCallCount: Int {
        state.withLock { $0.requestCallCount }
    }

    func currentStatus() async -> MicrophonePermissionStatus {
        state.withLock { $0.current }
    }

    func requestAccess() async -> MicrophonePermissionStatus {
        state.withLock { inner in
            inner.requestCallCount += 1
            if inner.current == .notDetermined {
                inner.current = inner.grantOnRequest ? .granted : .denied
            }
            return inner.current
        }
    }
}

@Suite("MicrophonePermissionServicing — fake transitions")
struct MicrophonePermissionServiceTests {
    @Test("undetermined transitions to granted on request when configured to grant")
    func undeterminedToGranted() async {
        let service = FakePermissionService(initial: .notDetermined, grantOnRequest: true)
        let initial = await service.currentStatus()
        #expect(initial == .notDetermined)
        let after = await service.requestAccess()
        #expect(after == .granted)
    }

    @Test("undetermined transitions to denied when configured to deny")
    func undeterminedToDenied() async {
        let service = FakePermissionService(initial: .notDetermined, grantOnRequest: false)
        let after = await service.requestAccess()
        #expect(after == .denied)
    }

    @Test("denied stays denied without re-prompting more than once")
    func deniedStaysDenied() async {
        let service = FakePermissionService(initial: .denied)
        let first = await service.requestAccess()
        let second = await service.requestAccess()
        #expect(first == .denied)
        #expect(second == .denied)
    }
}
