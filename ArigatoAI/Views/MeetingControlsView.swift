//
//  MeetingControlsView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - View

/// Meeting controls surface — status badge + morphing primary/secondary
/// button cluster + undo toast (Group D UI decisions #3, #4, #5, #7, #8).
///
/// The view is a pure projection of ``MeetingControlsViewModel``. The VM
/// owns 12 closures (13 when the optional `onAppear` is supplied) that
/// expose read state (phase, permission status, audio level, wall-clock
/// `now`) and action side effects (start, pause, resume, requestStop,
/// undoStop, finalizeStop, newTranscript, openSettings,
/// requestPermission). Two factories expose the canonical wiring shapes:
///
/// - ``MeetingControlsViewModel/disabled()`` — a no-op placeholder used by
///   previews, by ``ContentView`` until Step 8 swaps in the real wiring,
///   and by tests of the view body itself. Always reports
///   ``MicrophonePermissionStatus/notDetermined`` and an idle phase.
/// - ``MeetingControlsViewModel/wiring(coordinator:now:)`` — pulls every
///   read closure off a live ``MeetingCoordinator`` and routes every
///   action to the matching coordinator method. Called for the first
///   time in **Step 8**.
///
/// ## Permission states
///
/// The view branches on `model.permissionStatus()` and reproduces the
/// four-state surface that the old `RecordControl` inside
/// ``TranscriptLiveView`` carried — `notDetermined`, `granted`, `denied`,
/// `restricted` — but routes each branch through VM closures rather than
/// driving an ``AudioCaptureViewModel`` directly. This honours the locked
/// "closure-injected seam" decision (D7-1 option c) and keeps the view
/// passive.
///
/// ## Badge timer
///
/// The status badge wraps its content in `TimelineView(.periodic(from:by:))`
/// at 1Hz (D7-3 option a). The timer's `context.date` is **only**
/// consulted for the recording / stoppingWithUndoWindow phases; the
/// paused-elapsed and ended-final renderings ignore `context.date` and
/// read frozen times out of the phase payload itself. The freeze
/// contract lives in ``MeetingControlsFormatter/badgeDisplay(for:now:)``.
///
/// ## Concurrency scheduling assumption (Concurrency design discipline)
///
/// All tap methods on ``MeetingControlsViewModel`` are assumed to be
/// **mutually exclusive at the call site** — SwiftUI's button gesture
/// system serializes user taps. The view model does **not** internally
/// serialize concurrent invocations. If two tap methods are invoked
/// concurrently (e.g., from a test bypassing SwiftUI's gesture
/// serialization), both action closures will execute and both
/// ``MeetingControlsViewModel/inFlightAction`` writes will land — the
/// last write wins. This is harmless in production because the gesture
/// system never produces concurrent taps; the deterministic last-write-
/// wins semantics is locked by the named violation test
/// `vm_concurrentTapStartAndTapPause_bothClosuresInvoked_lastInFlightActionWins`
/// in `MeetingControlsViewTests`.
struct MeetingControlsView: View {
    /// The view model whose closures drive every read and action. Held as
    /// a plain property because ``MeetingControlsViewModel`` is
    /// `@Observable` (Swift 6) — SwiftUI observes its state without
    /// needing a property wrapper.
    let model: MeetingControlsViewModel

    var body: some View {
        VStack(spacing: 12) {
            errorBanner
            switch model.permissionStatus() {
            case .notDetermined:
                notDeterminedContent
            case .granted:
                grantedContent
            case .denied:
                deniedContent
            case .restricted:
                restrictedContent
            }
        }
        // Animate the error banner's insertion/removal: it appears at the
        // exact moment the user reaches to retry, so the cluster below must
        // glide rather than jump under the finger (same mis-tap class as
        // the undo-toast overlap fixed 2026-06-10).
        .animation(.default, value: model.lastError == nil)
        .task(id: model.onAppear != nil) {
            // Keyed on whether an `onAppear` closure is wired. ContentView
            // swaps the `.disabled()` placeholder (`onAppear == nil`) for
            // the production-wired VM (`onAppear != nil`) when the
            // bootstrapper publishes the coordinator, WITHOUT changing this
            // view's structural identity — a plain `.task` fires once
            // against the placeholder and never re-fires, so the wired
            // permission refresh would never run. The id flips
            // false → true at most once (the coordinator is published
            // exactly once and never reset), so the wired refresh runs
            // once per appearance.
            if let onAppear = model.onAppear {
                await onAppear()
            }
        }
    }

    // MARK: - Error banner

    /// Visible surface for ``MeetingControlsViewModel/lastError``. Before
    /// 2026-06-10 NO screen rendered action errors — a failed START (e.g.
    /// the device zombie-capture bug throwing `alreadyRunning`) looked like
    /// a dead button. Color-only differentiation per the design language;
    /// clears automatically because every tap method nils `lastError` on
    /// its next success.
    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.lastError {
            Label(errorText(for: error), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("meeting.controls.errorBanner")
        }
    }

    /// Prefers the typed `errorDescription` (all project error enums
    /// conform to `LocalizedError`) over the generic NSError fallback.
    private func errorText(for error: any Error) -> String {
        if let localized = (error as? any LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }

    // MARK: - notDetermined

    /// Pre-permission surface: a real, tappable affordance that requests
    /// microphone access. Tapping "Allow microphone" runs
    /// ``MeetingControlsViewModel/tapRequestPermission()`` (production
    /// wiring → ``AudioCaptureViewModel/requestPermission()``), which
    /// prompts the user and republishes the permission status so this view
    /// advances to the granted (START control) or denied (Open Settings)
    /// branch. The button participates in the cluster-wide
    /// `.disabled(inFlightAction != nil)` gating while a request is in
    /// flight.
    private var notDeterminedContent: some View {
        VStack(spacing: 12) {
            Text("Microphone access")
                .font(.headline)
            Text("Arigato AI needs your microphone to transcribe and translate meeting audio entirely on your device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow microphone") {
                Task { await model.tapRequestPermission() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.inFlightAction != nil)
            .accessibilityIdentifier("meeting.controls.requestPermission")
        }
    }

    // MARK: - denied

    /// Post-denial surface: user must open Settings to re-grant access.
    private var deniedContent: some View {
        VStack(spacing: 8) {
            Text("Microphone access required")
                .font(.subheadline.weight(.semibold))
            Text("Enable microphone access in Settings to start a meeting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                model.onOpenSettings()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - restricted

    /// MDM / parental-controls surface: no actionable affordance.
    private var restrictedContent: some View {
        VStack(spacing: 8) {
            Text("Microphone unavailable")
                .font(.subheadline.weight(.semibold))
            Text("Microphone access is restricted on this device. Check Screen Time or device-management settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - granted

    /// Active surface: undo toast (stopping phase only) stacked on top, then
    /// a single controls row carrying the status badge and the primary +
    /// secondary buttons side-by-side.
    ///
    /// The toast is a STACKED sibling, not an `.overlay` — the previous
    /// overlay-at-bottom rendered the toast on top of the badge and button
    /// cluster (visually overlapping them and intercepting taps aimed at
    /// NEW TRANSCRIPT; observed on device 2026-06-10). Stacking lets every
    /// surface own its own hit-test area; ``controlsRow`` (badge + buttons)
    /// is the sibling below it and never overlaps it. This invariant is
    /// regression-critical and must survive any future layout change here.
    private var grantedContent: some View {
        VStack(spacing: 16) {
            undoToast
            controlsRow
        }
    }

    /// The badge + primary + secondary controls, laid out on **one row** by
    /// default (UI: a single horizontal cluster reads as one control group
    /// rather than a vertical stack of disconnected affordances).
    ///
    /// Wrapped in `ViewThatFits(in: .horizontal)` so the single-row layout
    /// is used whenever it fits the available width, and the prior stacked
    /// (badge-over-buttons) arrangement is the graceful fallback when it
    /// does **not** — e.g. large Dynamic Type sizes that widen the button
    /// labels past the row width. This *closes* the V3 #40 concern class
    /// (a fixed single-axis layout that clips under large Dynamic Type)
    /// rather than adding a new instance of it: the vertical fallback is a
    /// real, tested degradation path, not a hope that the row always fits.
    ///
    /// `ViewThatFits` measures its children at their ideal size and renders
    /// the first that fits; both children are pure projections of the same
    /// formatter specs, so whichever renders, the badge/buttons and their
    /// accessibility identifiers are identical — only the axis differs.
    private var controlsRow: some View {
        ViewThatFits(in: .horizontal) {
            horizontalControls
            verticalControls
        }
    }

    /// Single-row arrangement: badge (leading) + primary + secondary,
    /// centered. The badge is elided in phases where the formatter returns
    /// no badge (idle), and each button appears only when its formatter spec
    /// is non-`nil`, so a lone-button phase (idle → START only;
    /// stopping/ended → NEW TRANSCRIPT only) renders a single centered
    /// control rather than a button stranded at one edge of a wide row.
    private var horizontalControls: some View {
        HStack(spacing: 12) {
            badge
            primaryButton
            secondaryButton
        }
    }

    /// Vertical fallback reproducing the prior stacked arrangement: badge
    /// over the primary button over the secondary button. Used by
    /// ``controlsRow``'s `ViewThatFits` only when ``horizontalControls``
    /// does not fit the available width.
    private var verticalControls: some View {
        VStack(spacing: 12) {
            badge
            primaryButton
            secondaryButton
        }
    }

    /// Status badge surface (UI decision #3). The wrapping
    /// `TimelineView(.periodic)` is the per-second tick driver; the
    /// formatter decides which clock value to display. The pulsing red
    /// dot is rendered as a SwiftUI `Circle` that animates opacity at
    /// 1Hz when `display.isPulsing` is `true` (matches the iOS
    /// "live recording" affordance).
    private var badge: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            if let display = MeetingControlsFormatter.badgeDisplay(
                for: model.phase(),
                now: context.date
            ) {
                HStack(spacing: 6) {
                    badgeIcon(for: display)
                    Text(display.text)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .accessibilityLabel(display.text)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.meterTrack, in: Capsule())
            }
        }
    }

    /// Renders the badge's leading glyph. The recording / stopping
    /// pulses are a red `Circle`; the paused glyph is a system pause
    /// icon; the ended glyph is a system stop square. Using SwiftUI
    /// shape primitives lets us animate the pulse with a simple
    /// `.opacity` modifier rather than relying on `symbolEffect` which
    /// is restricted to SF Symbols.
    @ViewBuilder
    private func badgeIcon(for display: MeetingControlsFormatter.BadgeDisplay) -> some View {
        switch display.kind {
        case .recordingPulse:
            Circle()
                .fill(Color.recordingActive)
                .frame(width: 8, height: 8)
                .opacity(display.isPulsing ? 1.0 : 0.4)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: display.isPulsing)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        case .ended:
            Image(systemName: "stop.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// The primary button (UI decision #4 + the foundational "buttons exist
    /// only when they can be used" principle). Renders only when the
    /// formatter returns a non-`nil` primary spec for the current phase;
    /// otherwise contributes nothing to either arrangement. Shared verbatim
    /// by ``horizontalControls`` and ``verticalControls`` so the button,
    /// its `.borderedProminent` style, its in-flight disable gating, its
    /// `meeting.controls.primary` identifier, and its dispatch closure are
    /// identical regardless of which axis `ViewThatFits` picks.
    @ViewBuilder
    private var primaryButton: some View {
        if let primary = MeetingControlsFormatter.primaryButton(for: model.phase()) {
            Button(primary.label) {
                Task { await dispatchPrimary(primary.kind) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.inFlightAction != nil)
            .accessibilityIdentifier("meeting.controls.primary")
        }
    }

    /// The secondary button. Renders only when the formatter returns a
    /// non-`nil` secondary spec (recording / paused → STOP); idle, the
    /// stopping window, and the ended phase emit no secondary, so this
    /// contributes nothing and the primary stands alone (centered in the
    /// horizontal arrangement). Shared verbatim by ``horizontalControls``
    /// and ``verticalControls``; preserves the `.bordered` style, the
    /// in-flight disable gating, the `meeting.controls.secondary`
    /// identifier, and the dispatch closure.
    @ViewBuilder
    private var secondaryButton: some View {
        if let secondary = MeetingControlsFormatter.secondaryButton(for: model.phase()) {
            Button(secondary.label) {
                Task { await dispatchSecondary(secondary.kind) }
            }
            .buttonStyle(.bordered)
            .disabled(model.inFlightAction != nil)
            .accessibilityIdentifier("meeting.controls.secondary")
        }
    }

    /// Undo toast shown only in
    /// ``MeetingSessionPhase/stoppingWithUndoWindow``, stacked above the
    /// badge in ``grantedContent``. Parent owns dismissal: when
    /// ``MeetingSession`` exits the stopping phase (undo or finalize) the
    /// SwiftUI body re-renders without the toast.
    @ViewBuilder
    private var undoToast: some View {
        if case let .stoppingWithUndoWindow(_, _, deadline) = model.phase() {
            UndoStopToastView(deadline: deadline) {
                Task { await model.tapUndo() }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Dispatch

    /// Routes a primary-button tap to the matching VM `tap*` method based
    /// on the action kind the formatter returned.
    private func dispatchPrimary(_ kind: MeetingControlsViewModel.ActionKind) async {
        switch kind {
        case .start: await model.tapStart()
        case .pause: await model.tapPause()
        case .resume: await model.tapResume()
        case .newTranscript: await model.tapNewTranscript()
        case .requestStop: await model.tapRequestStop()
        case .undoStop: await model.tapUndo()
        // Never emitted by the formatter's button cluster — the permission
        // button dispatches directly — but the switch stays exhaustive and
        // honest should a spec ever carry it.
        case .requestPermission: await model.tapRequestPermission()
        }
    }

    /// Routes a secondary-button tap. Pre-MVP-1 hardening relocated Share
    /// to the active-view toolbar per UI #9 Context A; the formatter no
    /// longer emits a `.share` case from the cluster, so this dispatcher
    /// handles `.stop` only.
    private func dispatchSecondary(_ kind: MeetingControlsFormatter.SecondaryButtonSpec.SecondaryKind) async {
        switch kind {
        case .stop:
            await model.tapRequestStop()
        }
    }
}

// MARK: - View Model

/// View model for ``MeetingControlsView``.
///
/// Holds a closure-injected seam (D7-1 option c): 12 closures (plus an
/// optional `onAppear`) cover every read and action the view needs.
/// Production wiring routes them all through ``MeetingCoordinator`` via
/// ``MeetingControlsViewModel/wiring(coordinator:now:)``. Tests inject
/// recording fakes per closure.
///
/// `@MainActor` because the VM publishes ``inFlightAction`` and
/// ``lastError`` for SwiftUI; `@Observable` per Swift 6 conventions.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// Tap methods are assumed mutually exclusive at the call site —
/// SwiftUI's button gesture system serializes user taps. The VM does
/// **not** internally serialize concurrent `tap*` invocations. Under a
/// (test-only) race, both action closures execute and both
/// ``inFlightAction`` writes land; the last write wins. Production is
/// unaffected because the gesture system never produces concurrent taps.
///
/// **Named violation test**:
/// `vm_concurrentTapStartAndTapPause_bothClosuresInvoked_lastInFlightActionWins`
/// drives two `tap*` methods concurrently and asserts both closures
/// were invoked.
@MainActor
@Observable
final class MeetingControlsViewModel {
    // MARK: - Read closures

    /// Returns the current ``MeetingSessionPhase``. Production wiring
    /// closes over ``MeetingCoordinator/session``'s `phase`.
    let phase: () -> MeetingSessionPhase

    /// Returns the current microphone permission status. Production
    /// wiring closes over
    /// ``MeetingCoordinator/captureViewModel``'s `permissionStatus`.
    let permissionStatus: () -> MicrophonePermissionStatus

    /// Returns the most recent normalized RMS audio level in `[0, 1]`.
    /// Reserved for future VU-meter integration; Step 7 does not render
    /// the meter but the closure is part of the canonical wiring.
    let level: () -> Float

    /// Returns wall-clock `Date`. Tests inject a fake; production uses
    /// `Date.init`.
    let now: () -> Date

    // MARK: - Action closures (mutating side effects)

    /// Invoked by ``tapStart()``. Production wiring closes over
    /// `coordinator.startMeeting(at:)`.
    let onStart: @Sendable () async throws -> Void

    /// Invoked by ``tapPause()``. Production wiring closes over
    /// `coordinator.pauseMeeting(at:)`.
    let onPause: @Sendable () async throws -> Void

    /// Invoked by ``tapResume()``. Production wiring closes over
    /// `coordinator.resumeMeeting(at:)`.
    let onResume: @Sendable () async throws -> Void

    /// Invoked by ``tapRequestStop()``. Production wiring closes over
    /// `coordinator.requestStop(at:)`.
    let onRequestStop: @Sendable () async throws -> Void

    /// Invoked by ``tapUndo()``. Production wiring closes over
    /// `coordinator.undoStop()`.
    let onUndoStop: @Sendable () async throws -> Void

    /// Force-commits the in-flight stopping window. Invoked **only** by
    /// ``tapNewTranscript()`` when the current phase is
    /// ``MeetingSessionPhase/stoppingWithUndoWindow`` (the "skip the
    /// undo wait — finalize and start a new transcript" path). Production
    /// wiring closes over `coordinator.finalizeStop(at:)`.
    let onFinalizeStop: @Sendable () async throws -> Void

    /// Invoked by ``tapNewTranscript()`` to return the session to
    /// ``MeetingSessionPhase/idle``. Production wiring closes over
    /// `coordinator.newTranscript()`.
    let onNewTranscript: @Sendable () async throws -> Void

    /// Invoked by the "Open Settings" button on the denied permission
    /// surface. Production wiring closes over
    /// `coordinator.captureViewModel.openSettings()`.
    let onOpenSettings: () -> Void

    /// Invoked by the "Allow microphone" button on the not-determined
    /// permission surface, via ``tapRequestPermission()``. Production
    /// wiring closes over
    /// `coordinator.captureViewModel.requestPermission()`, which prompts
    /// the user (overlapping calls are single-flighted — see
    /// ``AudioCaptureViewModel/requestPermission()`` for the scheduling
    /// contract) and republishes the permission status so the view
    /// advances to the granted/denied branch. ``disabled()`` supplies an
    /// explicit no-op placeholder.
    let onRequestPermission: @Sendable () async -> Void

    /// Optional — fired from the view body's `.task` modifier. The
    /// production wiring routes this to
    /// `coordinator.captureViewModel.onAppear()` so the permission flow
    /// can refresh on view appearance. `.disabled()` returns `nil` here
    /// (no-op placeholder).
    let onAppear: (@Sendable () async -> Void)?

    // MARK: - Observable state

    /// The most recent error raised by an action closure. Cleared on the
    /// next successful action.
    private(set) var lastError: Error?

    /// The currently-running action kind, or `nil` when idle. Used by
    /// the view to disable buttons while a tap is in flight.
    private(set) var inFlightAction: ActionKind?

    /// Categorises in-flight taps so the view can disable other buttons
    /// while one is running.
    ///
    /// Marked `nonisolated` so the synthesized `Equatable` conformance is
    /// usable from any context. Without `nonisolated`, the project-default
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` lifts the nested enum
    /// into MainActor isolation, which makes its Equatable conformance
    /// MainActor-isolated and produces a Swift 6 language-mode warning at
    /// every consumer comparison site (instance 5 of the project-default-isolation
    /// pattern — V3 entry "Project-default-isolation pattern").
    nonisolated enum ActionKind: Equatable {
        case start
        case pause
        case resume
        case requestStop
        case undoStop
        case newTranscript
        case requestPermission
    }

    // MARK: - Init

    /// Designated initializer. Every closure is explicit so production
    /// wiring and tests share the same shape; the two factories below
    /// (``disabled()`` / ``wiring(coordinator:now:)``) cover both
    /// canonical call sites.
    init(
        phase: @escaping () -> MeetingSessionPhase,
        permissionStatus: @escaping () -> MicrophonePermissionStatus,
        level: @escaping () -> Float,
        now: @escaping () -> Date,
        onStart: @escaping @Sendable () async throws -> Void,
        onPause: @escaping @Sendable () async throws -> Void,
        onResume: @escaping @Sendable () async throws -> Void,
        onRequestStop: @escaping @Sendable () async throws -> Void,
        onUndoStop: @escaping @Sendable () async throws -> Void,
        onFinalizeStop: @escaping @Sendable () async throws -> Void,
        onNewTranscript: @escaping @Sendable () async throws -> Void,
        onOpenSettings: @escaping () -> Void,
        onRequestPermission: @escaping @Sendable () async -> Void = {},
        onAppear: (@Sendable () async -> Void)? = nil
    ) {
        self.phase = phase
        self.permissionStatus = permissionStatus
        self.level = level
        self.now = now
        self.onStart = onStart
        self.onPause = onPause
        self.onResume = onResume
        self.onRequestStop = onRequestStop
        self.onUndoStop = onUndoStop
        self.onFinalizeStop = onFinalizeStop
        self.onNewTranscript = onNewTranscript
        self.onOpenSettings = onOpenSettings
        self.onRequestPermission = onRequestPermission
        self.onAppear = onAppear
    }

    // MARK: - Factories

    /// Returns a no-op placeholder VM. Always reports
    /// ``MicrophonePermissionStatus/notDetermined`` and
    /// ``MeetingSessionPhase/idle``; every action closure is a no-op.
    /// Used by previews, by ``ContentView`` until Step 8 wires
    /// ``wiring(coordinator:now:)``, and by tests that only exercise
    /// view-body rendering.
    static func disabled() -> MeetingControlsViewModel {
        MeetingControlsViewModel(
            phase: { .idle },
            permissionStatus: { .notDetermined },
            level: { 0 },
            now: Date.init,
            onStart: {},
            onPause: {},
            onResume: {},
            onRequestStop: {},
            onUndoStop: {},
            onFinalizeStop: {},
            onNewTranscript: {},
            onOpenSettings: {},
            onRequestPermission: {}
        )
    }

    /// Returns a production-wired VM that routes every read closure
    /// through `coordinator`'s session / capture view model and every
    /// action closure through the matching coordinator method.
    ///
    /// Called for the first time in **Step 8** when
    /// ``AppBootstrapper`` constructs the live ``MeetingCoordinator``.
    /// Step 7 only defines the factory; ``ContentView`` ships
    /// ``disabled()`` until Step 8 swaps in this call.
    ///
    /// - Parameters:
    ///   - coordinator: The live wiring layer.
    ///   - now: Wall-clock source. Defaults to `Date.init`; tests can
    ///     inject a deterministic clock.
    static func wiring(
        coordinator: MeetingCoordinator,
        now: @escaping () -> Date = Date.init
    ) -> MeetingControlsViewModel {
        // Closures capture the coordinator by reference. The coordinator
        // itself is `@MainActor` so closure bodies remain main-actor-
        // safe when invoked from the main actor.
        MeetingControlsViewModel(
            phase: { coordinator.session.phase },
            permissionStatus: { coordinator.captureViewModel.permissionStatus },
            level: { coordinator.captureViewModel.level },
            now: now,
            onStart: { @MainActor in try await coordinator.startMeeting(at: now()) },
            onPause: { @MainActor in try await coordinator.pauseMeeting(at: now()) },
            onResume: { @MainActor in try await coordinator.resumeMeeting(at: now()) },
            onRequestStop: { @MainActor in try await coordinator.requestStop(at: now()) },
            onUndoStop: { @MainActor in try await coordinator.undoStop() },
            onFinalizeStop: { @MainActor in try await coordinator.finalizeStop(at: now()) },
            onNewTranscript: { @MainActor in try await coordinator.newTranscript() },
            onOpenSettings: { coordinator.captureViewModel.openSettings() },
            onRequestPermission: { @MainActor in await coordinator.captureViewModel.requestPermission() },
            onAppear: { @MainActor in await coordinator.captureViewModel.onAppear() }
        )
    }

    // MARK: - Tap methods

    /// Runs the `onStart` closure, capturing any thrown error into
    /// ``lastError`` and tracking ``inFlightAction`` while the closure
    /// is awaited. See the type-level scheduling-assumption note for
    /// concurrency semantics.
    func tapStart() async {
        inFlightAction = .start
        defer { inFlightAction = nil }
        do {
            try await onStart()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Runs the `onPause` closure with the same in-flight + error
    /// pattern as ``tapStart()``.
    func tapPause() async {
        inFlightAction = .pause
        defer { inFlightAction = nil }
        do {
            try await onPause()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Runs the `onResume` closure with the same in-flight + error
    /// pattern as ``tapStart()``.
    func tapResume() async {
        inFlightAction = .resume
        defer { inFlightAction = nil }
        do {
            try await onResume()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Runs the `onRequestStop` closure with the same in-flight + error
    /// pattern as ``tapStart()``.
    func tapRequestStop() async {
        inFlightAction = .requestStop
        defer { inFlightAction = nil }
        do {
            try await onRequestStop()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Runs the `onUndoStop` closure with the same in-flight + error
    /// pattern as ``tapStart()``.
    func tapUndo() async {
        inFlightAction = .undoStop
        defer { inFlightAction = nil }
        do {
            try await onUndoStop()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Runs the new-transcript flow.
    ///
    /// - When the current ``phase()`` is
    ///   ``MeetingSessionPhase/stoppingWithUndoWindow``, this **force-
    ///   commits** the undo window: it calls `onFinalizeStop` first,
    ///   then `onNewTranscript`. This is UI decision #8's "skip the
    ///   undo wait — finalize and start fresh" branch. If
    ///   `onFinalizeStop` throws, `onNewTranscript` is **not** called
    ///   and the thrown error lands in ``lastError``.
    /// - In any other phase (canonically ``MeetingSessionPhase/ended``),
    ///   this runs only `onNewTranscript`.
    func tapNewTranscript() async {
        inFlightAction = .newTranscript
        defer { inFlightAction = nil }
        if case .stoppingWithUndoWindow = phase() {
            // Force-commit branch: finalize then move to idle.
            do {
                try await onFinalizeStop()
                try await onNewTranscript()
                lastError = nil
            } catch {
                lastError = error
            }
        } else {
            do {
                try await onNewTranscript()
                lastError = nil
            } catch {
                lastError = error
            }
        }
    }

    /// Runs the `onRequestPermission` closure with the same in-flight
    /// pattern as ``tapStart()``, so the permission button participates in
    /// the cluster-wide `.disabled(inFlightAction != nil)` gating. The
    /// closure is non-throwing — permission requests surface their result
    /// through the published permission status, not through errors — so
    /// there is no error capture; `lastError` is cleared on completion to
    /// match the "cleared on the next successful action" contract.
    ///
    /// Note the view-level disable is best-effort (see the type-level
    /// scheduling-assumption note: tap methods are not internally
    /// serialized). The hard no-double-prompt guarantee lives in
    /// ``AudioCaptureViewModel/requestPermission()``'s single-flight
    /// contract, not here.
    func tapRequestPermission() async {
        inFlightAction = .requestPermission
        defer { inFlightAction = nil }
        await onRequestPermission()
        lastError = nil
    }
}

// MARK: - Formatter

/// Pure value-type derivation of the badge, primary button, and
/// secondary button surfaces from a ``MeetingSessionPhase`` (+ a `now`
/// `Date` for the elapsed timer).
///
/// `nonisolated` so the view body — which is implicitly main-actor —
/// can call these helpers from inside a `TimelineView`'s body without
/// any actor hop. The methods are pure functions of their inputs; tests
/// drive them directly without spinning up SwiftUI.
nonisolated enum MeetingControlsFormatter {
    /// Returns the badge surface for the given phase, or `nil` when
    /// no badge should render (i.e., ``MeetingSessionPhase/idle``).
    ///
    /// The `now` parameter is **only** consulted for the recording and
    /// stoppingWithUndoWindow phases. The paused phase reads its frozen
    /// `pausedAt - startedAt` and the ended phase reads its frozen
    /// `endedAt - startedAt`; both ignore `now`. This freeze contract
    /// is UI decision #3 and is locked by
    /// `formatter_badgeDisplay_paused_freezesAtPauseTime_evenIfNowIsLater`.
    static func badgeDisplay(for phase: MeetingSessionPhase, now: Date) -> BadgeDisplay? {
        switch phase {
        case .idle:
            return nil
        case let .recording(_, startedAt):
            return BadgeDisplay(
                kind: .recordingPulse,
                text: "REC " + formatElapsed(from: startedAt, to: now),
                isPulsing: true
            )
        case let .paused(_, startedAt, pausedAt):
            // Freeze contract: ignore `now`, render elapsed at the
            // moment of pause.
            return BadgeDisplay(
                kind: .paused,
                text: "PAUSED " + formatElapsed(from: startedAt, to: pausedAt),
                isPulsing: false
            )
        case let .stoppingWithUndoWindow(_, startedAt, _):
            // Badge continues to pulse during the undo window — the
            // meeting is "still recording" semantically until the
            // deadline fires (or undo lands).
            return BadgeDisplay(
                kind: .recordingPulse,
                text: "REC " + formatElapsed(from: startedAt, to: now),
                isPulsing: true
            )
        case let .ended(_, startedAt, endedAt):
            // Final duration, no pulse.
            return BadgeDisplay(
                kind: .ended,
                text: formatElapsed(from: startedAt, to: endedAt),
                isPulsing: false
            )
        }
    }

    /// Returns the primary-button spec for the given phase, or `nil`
    /// when no primary action is available (no such phase exists in the
    /// state machine — every reachable phase has a primary action).
    static func primaryButton(for phase: MeetingSessionPhase) -> PrimaryButtonSpec? {
        switch phase {
        case .idle:
            return PrimaryButtonSpec(label: "START", kind: .start)
        case .recording:
            return PrimaryButtonSpec(label: "PAUSE", kind: .pause)
        case .paused:
            return PrimaryButtonSpec(label: "RESUME", kind: .resume)
        case .stoppingWithUndoWindow:
            // The primary morphs to NEW TRANSCRIPT immediately when STOP
            // is tapped; the undo toast handles recovery (UI #8).
            return PrimaryButtonSpec(label: "NEW TRANSCRIPT", kind: .newTranscript)
        case .ended:
            return PrimaryButtonSpec(label: "NEW TRANSCRIPT", kind: .newTranscript)
        }
    }

    /// Returns the secondary-button spec for the given phase, or `nil`
    /// when no secondary action is available. Idle, the stopping window,
    /// and the ended phase all have no secondary action per the morphing
    /// table (UI #4) — the ended phase's Share is rendered as a toolbar
    /// icon on the active view per UI #9 Context A (B1.4 hardening),
    /// **not** as a button in this cluster.
    static func secondaryButton(for phase: MeetingSessionPhase) -> SecondaryButtonSpec? {
        switch phase {
        case .idle:
            return nil
        case .recording:
            return SecondaryButtonSpec(label: "STOP", kind: .stop)
        case .paused:
            return SecondaryButtonSpec(label: "STOP", kind: .stop)
        case .stoppingWithUndoWindow:
            return nil
        case .ended:
            // UI #9 Context A: Share moved to the active-view toolbar
            // (B1.4 / pre-MVP-1 hardening). The cluster offers no
            // secondary action in the ended phase — the primary button
            // alone carries `NEW TRANSCRIPT`.
            return nil
        }
    }

    /// Formats an elapsed interval as `mm:ss` (or `h:mm:ss` past one
    /// hour). Negative intervals clamp to zero — a downstream
    /// scheduling glitch where `now < startedAt` must not render
    /// `-00:01`.
    private static func formatElapsed(from startedAt: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(startedAt).rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension MeetingControlsFormatter {
    /// Pure value-type rendering of the status badge (UI #3).
    nonisolated struct BadgeDisplay: Equatable {
        /// Which icon variant to render. Drives the view's branch into
        /// pulse-circle vs system pause/stop SF Symbol.
        let kind: BadgeKind
        /// Trailing text payload — typically `REC mm:ss`, `PAUSED mm:ss`,
        /// or a bare `mm:ss` final duration.
        let text: String
        /// `true` when the badge should pulse to indicate live capture.
        let isPulsing: Bool
    }

    /// Badge icon variants. Driven entirely by phase.
    nonisolated enum BadgeKind: Equatable {
        /// Pulsing red dot used by recording and stoppingWithUndoWindow.
        case recordingPulse
        /// Static pause glyph used by the paused phase.
        case paused
        /// Static stop square used by the ended phase.
        case ended
    }

    /// Pure value-type rendering of the primary button (UI #4).
    nonisolated struct PrimaryButtonSpec: Equatable {
        /// Button label, e.g. `START`, `PAUSE`, `NEW TRANSCRIPT`.
        let label: String
        /// The tap kind. Drives ``MeetingControlsView``'s dispatch into
        /// the matching VM `tap*` method.
        let kind: MeetingControlsViewModel.ActionKind
    }

    /// Pure value-type rendering of the secondary button (UI #4).
    nonisolated struct SecondaryButtonSpec: Equatable {
        /// Button label, e.g. `STOP`.
        let label: String
        /// The secondary kind. Drives ``MeetingControlsView``'s dispatch
        /// of the matching VM action.
        let kind: SecondaryKind

        /// Secondary-button kinds.
        ///
        /// Pre-MVP-1 hardening (B1.4) dropped the prior `.share` case
        /// when Share moved to the active-view toolbar per UI #9 Context
        /// A. The cluster's secondary slot now carries only `.stop`
        /// (recording / paused phases); the ended phase emits `nil` from
        /// ``MeetingControlsFormatter/secondaryButton(for:)`` because
        /// the toolbar Share replaces it.
        enum SecondaryKind: Equatable {
            case stop
        }
    }
}

// MARK: - Previews

#if DEBUG

    /// Builds a transient `PersistentIdentifier` for preview construction
    /// of the non-`.idle` phases. The previews never read the ID — they
    /// only need a value-shaped argument to satisfy the phase enum's
    /// associated-value requirement. The in-memory `ModelContainer` is
    /// throwaway; if it fails to construct (vanishingly unlikely) we
    /// fall back to a pre-save identifier on a detached Meeting.
    @MainActor
    private func previewMeetingID() -> PersistentIdentifier {
        do {
            let container = try ModelContainer(
                for: Meeting.self, Sentence.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            let meeting = Meeting(
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                title: "Preview"
            )
            context.insert(meeting)
            try context.save()
            return meeting.persistentModelID
        } catch {
            // Pre-save persistentModelID — unstable but acceptable for
            // a preview-only sentinel.
            let meeting = Meeting(
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                title: "Preview"
            )
            return meeting.persistentModelID
        }
    }

    @MainActor
    private func previewControlsVM(phase: MeetingSessionPhase) -> MeetingControlsViewModel {
        MeetingControlsViewModel(
            phase: { phase },
            permissionStatus: { .granted },
            level: { 0 },
            now: { Date(timeIntervalSince1970: 1_700_000_000 + 222) },
            onStart: {},
            onPause: {},
            onResume: {},
            onRequestStop: {},
            onUndoStop: {},
            onFinalizeStop: {},
            onNewTranscript: {},
            onOpenSettings: {}
        )
    }

    #Preview("Light — idle") {
        MeetingControlsView(model: previewControlsVM(phase: .idle))
            .preferredColorScheme(.light)
            .padding()
    }

    #Preview("Dark — idle") {
        MeetingControlsView(model: previewControlsVM(phase: .idle))
            .preferredColorScheme(.dark)
            .padding()
    }

    #Preview("Light — recording") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(phase: .recording(meetingID: id, startedAt: started))
        )
        .preferredColorScheme(.light)
        .padding()
    }

    #Preview("Dark — recording") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(phase: .recording(meetingID: id, startedAt: started))
        )
        .preferredColorScheme(.dark)
        .padding()
    }

    #Preview("Light — paused") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let paused = started.addingTimeInterval(222)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(
                phase: .paused(meetingID: id, startedAt: started, pausedAt: paused)
            )
        )
        .preferredColorScheme(.light)
        .padding()
    }

    #Preview("Dark — paused") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let paused = started.addingTimeInterval(222)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(
                phase: .paused(meetingID: id, startedAt: started, pausedAt: paused)
            )
        )
        .preferredColorScheme(.dark)
        .padding()
    }

    #Preview("Light — stopping with undo") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = started.addingTimeInterval(227)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(
                phase: .stoppingWithUndoWindow(meetingID: id, startedAt: started, deadline: deadline)
            )
        )
        .preferredColorScheme(.light)
        .padding()
    }

    #Preview("Dark — stopping with undo") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = started.addingTimeInterval(227)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(
                phase: .stoppingWithUndoWindow(meetingID: id, startedAt: started, deadline: deadline)
            )
        )
        .preferredColorScheme(.dark)
        .padding()
    }

    #Preview("Light — ended") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(3012)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(
                phase: .ended(meetingID: id, startedAt: started, endedAt: ended)
            )
        )
        .preferredColorScheme(.light)
        .padding()
    }

    #Preview("Dark — ended") {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(3012)
        let id = previewMeetingID()
        return MeetingControlsView(
            model: previewControlsVM(
                phase: .ended(meetingID: id, startedAt: started, endedAt: ended)
            )
        )
        .preferredColorScheme(.dark)
        .padding()
    }

#endif
