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
///
/// ## B1.4 — UI #9 Context A toolbar `ShareLink`
///
/// The same `.toolbar` modifier carries a second ``ToolbarItem`` at
/// `.topBarTrailing` rendering a SwiftUI `ShareLink` when the session's
/// phase is ``MeetingSessionPhase/ended`` and the active meeting has at
/// least one persisted sentence. The render gate matches
/// ``MeetingDetailView``'s Context B `ShareLink` (UI #4 "buttons exist
/// only when usable").
///
/// Data path: ``ActiveMeetingShareViewModel`` is constructed per render
/// (same Option a pattern as ``TranscriptSplitScreenViewModel``) and
/// hydrated by a `.task(id:)` modifier so the share payload's title +
/// sentences are fetched once the meeting reaches the ended phase.
struct ContentView: View {
    /// The shared bootstrapper threaded in from ``ArigatoAIApp`` via
    /// the SwiftUI environment. ``AppBootstrapper/coordinator`` drives
    /// the optional-coordinator ladder for the controls surface and
    /// ``AppBootstrapper/meetingStore`` gates the history toolbar item.
    @Environment(AppBootstrapper.self) private var bootstrapper

    /// One-shot SwiftUI flag flipped by
    /// ``OnboardingViewModel/finish()`` via the onComplete callback.
    /// Starts `false` so the first render reads
    /// ``AppBootstrapper/onboardingStore/hasCompletedOnboarding`` from
    /// the persistent store. Once flipped to `true`, ``ContentView``
    /// re-renders against the main-app branch even before the next
    /// store read would observe the new flag (the same SwiftUI render
    /// cycle the callback fires in).
    ///
    /// The combined check `!onboardingComplete &&
    /// !store.hasCompletedOnboarding` covers both directions: a fresh
    /// process (store flag set, in-process flag still `false`) skips
    /// onboarding by reading the persistent flag; an in-flight finish
    /// (in-process flag flipped, persistent flag also written) skips
    /// onboarding via either gate.
    @State private var onboardingComplete: Bool = false

    var body: some View {
        if !onboardingComplete && !bootstrapper.onboardingStore.hasCompletedOnboarding {
            OnboardingView(store: bootstrapper.onboardingStore) {
                onboardingComplete = true
            }
        } else {
            mainContent
        }
    }

    /// The main-app surface. Extracted from ``body`` so the
    /// top-of-body onboarding branch keeps its conditional shape
    /// simple. Renders the same `NavigationStack` /
    /// ``TranscriptLiveView`` + history-toolbar combo Step 6 wired up;
    /// nothing about the main-app routing changed in Step 14.
    @ViewBuilder
    private var mainContent: some View {
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

        // B1.4 — UI #9 Context A: re-derive the active-meeting share
        // VM each render, scoped to the ended-phase meeting only. The
        // VM is non-nil **only** when the phase is `.ended` AND the
        // store is reachable — recording / paused phases have no Share
        // affordance (UI #4 morphing table).
        let shareModel = makeShareModel()

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
                // B1.4 / UI #9 Context A — active-view toolbar Share.
                // Renders only when:
                //   1. The session phase is `.ended` (gate enforced by
                //      `makeShareModel()` returning nil for any other
                //      phase).
                //   2. The share VM has a hydrated snapshot.
                //   3. The snapshot's `sentences` are non-empty (UI #4
                //      "buttons exist only when usable").
                if let shareModel,
                   let snapshot = shareModel.snapshot,
                   !snapshot.sentences.isEmpty,
                   let exportURL = activeMeetingExportURL(snapshot: snapshot)
                {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: exportURL) {
                            Image(systemName: "square.and.arrow.up")
                                .accessibilityLabel("Share transcript")
                        }
                    }
                }
            }
            // Drive the share VM's reload when the active meetingID
            // changes (typically on the recording → ended transition,
            // or when a new meeting ends after the previous one).
            // `.task(id:)` cancels the prior in-flight reload on every
            // identifier change, matching the last-query-wins
            // scheduling assumption documented on
            // ``ActiveMeetingShareViewModel``.
            .task(id: activeShareIdentity()) {
                if let shareModel {
                    await shareModel.reload()
                }
            }
        }
    }

    /// Builds the active-meeting share VM, gated on the session phase
    /// being ``MeetingSessionPhase/ended``. Returns `nil` for any other
    /// phase so the toolbar `ShareLink` does not render outside the
    /// locked Context A trigger.
    ///
    /// Mirrors the construction pattern of ``makeTranscriptModel()`` —
    /// derived per render, scoped to the active meetingID, no
    /// long-lived `@State`. SwiftUI re-evaluates the body when the
    /// underlying `bootstrapper.coordinator?.session.phase` changes,
    /// producing a fresh VM on every phase transition.
    private func makeShareModel() -> ActiveMeetingShareViewModel? {
        guard let coordinator = bootstrapper.coordinator,
              let store = bootstrapper.meetingStore
        else {
            return nil
        }
        let phase = coordinator.session.phase
        guard case let .ended(meetingID, _, _) = phase else {
            return nil
        }
        return ActiveMeetingShareViewModel(store: store, meetingID: meetingID)
    }

    /// Stable identity for the share VM's `.task(id:)` modifier so the
    /// reload re-fires exactly when the active ended-meeting changes.
    /// Returns a sentinel when no share VM should be active (idle /
    /// recording / paused phases) so the `.task(id:)` does not run any
    /// fetcher in those phases.
    private func activeShareIdentity() -> AnyHashable {
        guard let coordinator = bootstrapper.coordinator,
              case let .ended(meetingID, _, _) = coordinator.session.phase
        else {
            return AnyHashable("inactive")
        }
        return AnyHashable(meetingID)
    }

    /// Synthesizes the temp-file `URL` for the share payload on demand.
    /// Mirrors ``MeetingDetailView/exportURL`` but reads from the
    /// share VM's atomic snapshot rather than from injected DTOs.
    ///
    /// Returns `nil` if ``TranscriptExporter/writeTemporaryFile(markdown:filename:)``
    /// throws — the caller (the toolbar `ShareLink` guard above) hides
    /// the item on `nil`, matching UI decision #4 "buttons exist only
    /// when usable."
    ///
    /// ## Synchronous write contract
    ///
    /// `TranscriptExporter.writeTemporaryFile` performs synchronous
    /// `Data.write(to:)` on the calling thread (the
    /// `TranscriptExporter` type-level scheduling-assumption doc
    /// covers this). MVP-1 transcript sizes (30–60 KB) make the
    /// inline call fine — re-fired every body re-evaluation via the
    /// computed-property pattern that
    /// ``MeetingDetailView/exportURL`` established (Step 13).
    private func activeMeetingExportURL(snapshot: ActiveMeetingShareViewModel.Snapshot) -> URL? {
        do {
            let body = TranscriptExporter.markdownBody(
                summary: snapshot.summary,
                sentences: snapshot.sentences
            )
            let filename = TranscriptExporter.makeFilename(
                title: snapshot.summary.title,
                startedAt: snapshot.summary.startedAt
            )
            return try TranscriptExporter.writeTemporaryFile(
                markdown: body,
                filename: filename
            )
        } catch {
            return nil
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
