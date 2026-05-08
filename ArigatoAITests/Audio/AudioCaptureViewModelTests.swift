//
//  AudioCaptureViewModelTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

/// Fake capture that records calls and exposes controllable streams.
final class FakeCapture: AudioCapturing, @unchecked Sendable {
    private struct State {
        var startCount: Int = 0
        var stopCount: Int = 0
        var shouldThrowOnStart: Bool = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setShouldThrowOnStart(_ value: Bool) {
        state.withLock { $0.shouldThrowOnStart = value }
    }

    var startCount: Int {
        state.withLock { $0.startCount }
    }

    var stopCount: Int {
        state.withLock { $0.stopCount }
    }

    func start() async throws {
        let shouldThrow = state.withLock { inner -> Bool in
            inner.startCount += 1
            return inner.shouldThrowOnStart
        }
        if shouldThrow {
            throw AudioCaptureError.engineStartFailed("fake")
        }
    }

    func stop() async {
        state.withLock { $0.stopCount += 1 }
    }

    func frameStream() async -> AsyncStream<AudioFrame> {
        AsyncStream { continuation in
            // Leave open until cancelled by the consumer task.
            continuation.onTermination = { _ in }
        }
    }

    func levelStream() async -> AsyncStream<Float> {
        AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}

@Suite("AudioCaptureViewModel state machine")
@MainActor
struct AudioCaptureViewModelTests {
    @Test("onAppear refreshes the cached permission status")
    func onAppearLoadsStatus() async {
        let permissions = FakePermissionService(initial: .granted)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        #expect(vm.permissionStatus == .granted)
        #expect(vm.isRecording == false)
    }

    @Test("toggle when undetermined prompts and starts on grant")
    func toggleUndeterminedPromptsAndStarts() async {
        let permissions = FakePermissionService(initial: .notDetermined, grantOnRequest: true)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.permissionStatus == .granted)
        #expect(permissions.requestCallCount == 1)
        #expect(capture.startCount == 1)
        #expect(vm.isRecording == true)
        await vm.toggleRecording()
        #expect(vm.isRecording == false)
        #expect(capture.stopCount == 1)
    }

    @Test("toggle when undetermined and user denies does not start capture")
    func toggleUndeterminedDeniedDoesNotStart() async {
        let permissions = FakePermissionService(initial: .notDetermined, grantOnRequest: false)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.permissionStatus == .denied)
        #expect(capture.startCount == 0)
        #expect(vm.isRecording == false)
    }

    @Test("toggle when denied is a no-op")
    func toggleWhenDeniedIsNoop() async {
        let permissions = FakePermissionService(initial: .denied)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(capture.startCount == 0)
        #expect(vm.isRecording == false)
    }

    @Test("error from start populates errorMessage and leaves isRecording false")
    func startErrorIsSurfaced() async {
        let permissions = FakePermissionService(initial: .granted)
        let capture = FakeCapture()
        capture.setShouldThrowOnStart(true)
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.isRecording == false)
        #expect(vm.errorMessage != nil)
    }
}
