//
//  ContentView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/06.
//

import SwiftData
import SwiftUI

/// Top-level app surface for Arigato AI. Phase 4 hosts the live
/// transcription experience via ``TranscriptLiveView``; the bootstrapper
/// flows in from ``ArigatoAIApp`` through the SwiftUI environment, so this
/// view is a thin wrapper.
///
/// ## Group D Step 6 — navigation
///
/// The body is wrapped in a `NavigationStack` so the active-meeting view
/// remains the root and a history icon in the top-right toolbar pushes
/// ``MeetingListView`` as a destination. This honors UI decision #11 —
/// active-meeting view is root; history is pushable, never reversed.
///
/// ## Group D Step 8 — bootstrapper-driven optional-coordinator ladder
///
/// Step 6's inline ``MeetingStore`` construction and Step 7's
/// ``MeetingControlsViewModel/disabled()`` placeholder are both lifted in
/// Step 8 — both surfaces now read from the shared ``AppBootstrapper``.
///
/// **Controls surface (D8-2 option a).** The view derives the controls
/// VM each render: `bootstrapper.coordinator.map { .wiring(coordinator: $0) } ?? .disabled()`.
/// Until ``AppBootstrapper/coordinator`` is published, the controls
/// surface falls back to ``MeetingControlsViewModel/disabled()`` — a no-op
/// stand-in whose action closures are all empty. Once
/// ``AppBootstrapper/startPrewarm(variant:)`` finishes warmup and
/// publishes the coordinator, SwiftUI re-renders against
/// ``MeetingControlsViewModel/wiring(coordinator:)``. The window is
/// sub-50ms in production (detached ``MeetingStore`` init + a single
/// main-actor hop per Amendment 3 / FB13399899).
///
/// **History destination.** The toolbar history icon is rendered only
/// when ``AppBootstrapper/meetingStore`` is non-nil. The detached-init
/// window is imperceptible because the idle-phase active-meeting view
/// has no transcript content to navigate away from yet.
///
/// ## Group D Step 9a — split-screen transcript VM wiring
///
/// The split-screen transcript surface needs a ``TranscriptSplitScreenViewModel``
/// scoped to **the active meeting's** identifier. The meeting identifier
/// is carried by ``MeetingSession/phase``'s associated values (every
/// non-idle phase carries a `meetingID`), so this view derives the VM
/// each render from `coordinator.session.phase`.
///
/// **Re-construction pattern (Option a from the dispatch brief).** When
/// the active meeting changes (a new meeting starts after the previous
/// one ended), `phase`'s `meetingID` value changes and SwiftUI re-renders
/// against a freshly-constructed VM. Re-init cost is dominated by the
/// initial `.task(id: refreshTrigger)` reload; the previous VM is
/// released when no view body holds a reference. Option b (mutate one
/// long-lived VM's `meetingID`) would avoid the re-init but add an
/// `meetingID` setter to the VM that is unused everywhere else — the
/// extra surface area is not worth saving one fetch per meeting.
///
/// **`sentencesDidUpdate` callback installation.** The same render path
/// installs `coordinator.session.sentencesDidUpdate = { [weak vm] in
/// vm?.requestReload() }`. The closure is `[weak vm]` so a VM that
/// outlives its installation (rare — phase change typically tears it
/// down) does not keep the session alive. Installation happens **every
/// render** but is idempotent on the session side (one optional closure
/// slot; last write wins).
///
/// **`session` access shape.** ``MeetingSession`` exposes `phase` as
/// `@Observable` `private(set)`, so SwiftUI reads it via the
/// environment-installed bootstrapper. The phase-to-meetingID mapping is
/// inlined here as a computed `activeMeetingID(...)` rather than added
/// as a method on `MeetingSession` (MAY-NOT-modify scope for Step 9a's
/// ContentView wiring).
struct ContentView: View {
    /// The shared bootstrapper threaded in from ``ArigatoAIApp`` via
    /// the SwiftUI environment. ``AppBootstrapper/coordinator`` drives
    /// the optional-coordinator ladder for the controls surface and
    /// ``AppBootstrapper/meetingStore`` gates the history toolbar item.
    @Environment(AppBootstrapper.self) private var bootstrapper

    var body: some View {
        // D8-2 option (a): derive the wired VM each render. SwiftUI
        // re-renders against `wiring(coordinator:)` once the
        // bootstrapper publishes the coordinator.
        let controlsModel = bootstrapper.coordinator.map {
            MeetingControlsViewModel.wiring(coordinator: $0)
        } ?? MeetingControlsViewModel.disabled()

        // D9a wiring (Option a): re-derive the split-screen VM each
        // render. The VM is non-nil only when both the coordinator and
        // an active meetingID are available (i.e. phase != .idle).
        // Idle / pre-coordinator renders pass `transcriptModel: nil` so
        // ``TranscriptLiveView`` falls back to its empty-state branch.
        let transcriptModel = makeTranscriptModel()

        NavigationStack {
            TranscriptLiveView(
                controlsModel: controlsModel,
                transcriptModel: transcriptModel
            )
            .toolbar {
                if let store = bootstrapper.meetingStore {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            MeetingListView(store: store)
                        } label: {
                            Image(systemName: "clock")
                                .accessibilityLabel("History")
                        }
                    }
                }
            }
        }
    }

    /// Builds the active-meeting ``TranscriptSplitScreenViewModel`` and
    /// wires its reload trampoline to ``MeetingSession/sentencesDidUpdate``.
    ///
    /// Returns `nil` when:
    ///   - The bootstrapper has not yet published a coordinator (warmup
    ///     window or container-error path).
    ///   - No ``MeetingStore`` is available (same reason as above).
    ///   - The session's ``MeetingSession/phase`` is ``MeetingSessionPhase/idle``
    ///     (no meetingID to scope the VM against).
    ///
    /// Otherwise constructs a fresh VM scoped to the phase's `meetingID`
    /// and installs the `sentencesDidUpdate` callback so every successful
    /// `appendSentence` (from the translation-event pump) bumps the VM's
    /// `refreshTrigger` and re-runs `.task(id:)`.
    private func makeTranscriptModel() -> TranscriptSplitScreenViewModel? {
        guard let coordinator = bootstrapper.coordinator,
              let store = bootstrapper.meetingStore,
              let meetingID = activeMeetingID(in: coordinator.session.phase)
        else {
            return nil
        }
        let vm = TranscriptSplitScreenViewModel(store: store, meetingID: meetingID)
        // Install the reload trampoline. `[weak vm]` avoids keeping the
        // VM alive past its render-derived lifetime. The session's
        // single optional callback slot is last-write-wins — re-installing
        // on every render is safe because the closure is closed over a
        // weak reference to the current VM.
        coordinator.session.sentencesDidUpdate = { [weak vm] in
            vm?.requestReload()
        }
        return vm
    }

    /// Extracts the meeting identifier from a ``MeetingSessionPhase``.
    ///
    /// Inlined here rather than added as a method on ``MeetingSession``
    /// because Step 9a's MAY-NOT-modify scope covers `MeetingSession`.
    /// `MeetingSession.activeMeetingID()` already exists as a `private`
    /// method used by `process(event:)`; a future cleanup pass can
    /// promote it to internal and replace this helper.
    private func activeMeetingID(in phase: MeetingSessionPhase) -> PersistentIdentifier? {
        switch phase {
        case let .recording(id, _): return id
        case let .paused(id, _, _): return id
        case let .stoppingWithUndoWindow(id, _, _): return id
        case let .ended(id, _, _): return id
        case .idle: return nil
        }
    }
}

#Preview {
    ContentView()
        .environment(AppBootstrapper())
}
