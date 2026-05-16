//
//  TranscriptLiveView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import SwiftUI

/// Top-level live transcription surface for Phase 4. Replaces the Phase-3
/// ``AudioCaptureView`` root and renders three vertical regions:
///
/// 1. **Top — language indicator chrome.** Reads
///    ``LanguageRouter/currentLanguage`` (the *authoritative* signal,
///    chosen for stability over momentary noise). Also surfaces the
///    Whisper warmup pill bound to ``AppBootstrapper/loaderState``.
/// 2. **Middle — scrollable transcript list.** Iterates
///    ``LanguageRouter/routedHistory`` and renders each row through
///    ``TranscriptRowDisplay``. Per-row badges read
///    ``RoutedTranscript/detectedLanguage`` (the *honest* per-window
///    signal). When ``RoutedTranscript/detectedLanguage`` differs from
///    ``RoutedTranscript/authoritativeLanguage`` (a SEAM-2 divergence
///    window) the row shows a small fallback marker — that one-window
///    mismatch is information, not noise.
/// 3. **Bottom — meeting controls surface.** A ``MeetingControlsView``
///    bound to a ``MeetingControlsViewModel``. Step 7 swapped the prior
///    `RecordControl` / `RecordButton` / `VUMeter` cluster for this new
///    surface (D7-2 option a — surgical swap). The host view ships a
///    `.disabled()` placeholder VM by default; ``ContentView`` overrides
///    it with `MeetingControlsViewModel.disabled()` until Step 8 swaps
///    in `MeetingControlsViewModel.wiring(coordinator:)`. The previous
///    audio-capture wiring through `AudioCaptureViewModel.router` is
///    dormant under Group D's design (tracked in the V3 dead-router-
///    drain entry); the live meeting pipeline reaches the router via
///    ``MeetingPipeline`` from Step 4.
///
/// ## Binding contract (locked)
///
/// - **Chrome** binds to ``LanguageRouter/currentLanguage`` (authoritative).
/// - **Per-row badge** binds to ``RoutedTranscript/detectedLanguage``
///   (per-window honest signal).
///
/// Picking the wrong field would produce two distinct UX bugs: a chrome
/// that flickers on every transient detection (binding the per-row signal
/// to chrome), or a row list that lies about what was heard for a given
/// window (binding chrome's authoritative signal to rows). The contract is
/// locked by test **D4-T-binding-detectedVsAuthoritative** in
/// ``TranscriptLiveViewTests``, which constructs a SEAM-2 divergence row
/// (`detectedLanguage = .en`, `authoritativeLanguage = .ja`) and asserts
/// the row's display badge reads "EN", not "JA".
///
/// ## Concurrency
///
/// All `@Observable` reads on ``LanguageRouter`` (``routedHistory``,
/// ``currentLanguage``) and on ``AppBootstrapper`` (``loaderState``)
/// happen from SwiftUI's MainActor render context. The router and
/// bootstrapper are themselves `@MainActor`-isolated, so this is the only
/// legal access pattern under Swift 6 strict concurrency. Cross-actor
/// reads are rejected at compile time, so no runtime violation test is
/// required.
struct TranscriptLiveView: View {
    /// App-wide bootstrapper carrying the shared loader, transcriber, and
    /// router. Resolved from the SwiftUI environment so tests can inject a
    /// pre-configured fake.
    @Environment(AppBootstrapper.self) private var bootstrapper

    /// Meeting controls VM for the bottom region. Defaults to the no-op
    /// ``MeetingControlsViewModel/disabled()`` placeholder so previews
    /// and tests that don't care about the controls surface continue to
    /// build. Production callers (``ContentView``) pass a non-default
    /// VM. Step 8 swaps the placeholder for
    /// ``MeetingControlsViewModel/wiring(coordinator:now:)``.
    let controlsModel: MeetingControlsViewModel

    /// Default initializer — ships a disabled placeholder VM for the
    /// controls surface so historical call sites (previews, the Phase-4
    /// `RecordControl` regression suite) compile unchanged.
    init() {
        controlsModel = MeetingControlsViewModel.disabled()
    }

    /// Override initializer — accepts a pre-built controls VM.
    /// ``ContentView`` calls this to inject the
    /// ``MeetingControlsViewModel/disabled()`` placeholder explicitly so
    /// the Step 8 swap site is single-line.
    init(controlsModel: MeetingControlsViewModel) {
        self.controlsModel = controlsModel
    }

    // MARK: - Empty-state copy (Concern 6 regression boundary)

    /// Primary "we're waiting" copy. Owned by the middle-region empty
    /// placeholder only. The chrome no longer renders this string —
    /// duplicating it across both surfaces produced a "is the app stuck?"
    /// reading on first launch (gate review Concern 6, 2026-05-10). The
    /// chrome's "no language yet" signal is the em-dash badge alone.
    /// Locked by D4-T-concern6 in `TranscriptLiveViewTests`.
    static let emptyStateHintPrimary = "listening…"

    /// Secondary detail line under the primary hint.
    static let emptyStateHintDetail = "Spoken Japanese or English will appear here."

    var body: some View {
        VStack(spacing: 0) {
            indicatorChrome
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            transcriptList

            MeetingControlsView(model: controlsModel)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceBackground)
    }

    // MARK: - Chrome

    /// Top region: persistent language indicator plus warmup-state pill.
    private var indicatorChrome: some View {
        let chrome = IndicatorChromeDisplay(
            currentLanguage: bootstrapper.router.currentLanguage,
            loaderState: bootstrapper.loaderState
        )

        return HStack(spacing: 12) {
            // Language badge — bound to currentLanguage (authoritative).
            HStack(spacing: 6) {
                Text(chrome.languageBadge)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.meterTrack, in: Capsule())
                    .accessibilityLabel(chrome.languageAccessibilityLabel)

                // Concern 6 (gate review 2026-05-10): the "listening…" hint
                // lives only in the middle-region empty placeholder. The
                // chrome's `showsListeningHint` flag still carries the
                // semantic ("router has not detected a language yet") for
                // accessibility / future use, but the chrome view body no
                // longer renders text for it — that produced a duplicated
                // "listening…" on first launch. Locked by D4-T-concern6.
            }

            Spacer(minLength: 8)

            // Warmup pill — bound to loaderState.
            warmupPill(for: chrome)
        }
    }

    @ViewBuilder
    private func warmupPill(for chrome: IndicatorChromeDisplay) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(chrome.warmupColor)
                .frame(width: 6, height: 6)
            Text(chrome.warmupLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.meterTrack.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chrome.warmupAccessibilityLabel)

        if let errorText = chrome.warmupErrorText {
            // V3 #40 concern 2 (Step 9b): error text uses semantic
            // `.secondary` rather than `Color.recordingActive` so the
            // red warmup dot alone carries the failed-state signal.
            // Adjacent red dot + red text overloaded the chrome region
            // and competed with captions for attention.
            Text(errorText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .accessibilityLabel("Whisper load failed: \(errorText)")
        }
    }

    // MARK: - Transcript list

    /// Middle region: scrollable transcript log or empty-state placeholder.
    @ViewBuilder
    private var transcriptList: some View {
        if bootstrapper.router.routedHistory.isEmpty {
            emptyState
        } else {
            // V3 #40 concern 4 (Step 9b): match the 20pt horizontal
            // inset that the chrome and footer carry so right-edge
            // row badges line up with the chrome's language badge
            // rather than running edge-to-edge.
            List(bootstrapper.router.routedHistory) { routed in
                TranscriptRow(display: TranscriptRowDisplay(routed: routed))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(Self.emptyStateHintPrimary)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(Self.emptyStateHintDetail)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Listening. No transcript yet.")
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Audio never leaves your iPhone.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Row display value (testability lever)

/// Pure value-type rendering of a single ``RoutedTranscript`` row, derived
/// entirely from the routed transcript's fields.
///
/// Factored out from the SwiftUI body so unit tests can assert the binding
/// contract (rows read ``RoutedTranscript/detectedLanguage``, not
/// ``LanguageRouter/currentLanguage``) without spinning up SwiftUI render
/// machinery. ``TranscriptRow`` consumes this value to lay out its body.
///
/// `internal` access lets the test target read it via
/// `@testable import ArigatoAI`.
struct TranscriptRowDisplay: Equatable {
    /// Concatenated text from the underlying window.
    let text: String

    /// Two-letter badge string. Reads ``RoutedTranscript/detectedLanguage``,
    /// **not** ``RoutedTranscript/authoritativeLanguage`` — this is the
    /// honest per-window signal the brief surfaces (test
    /// **D4-T-binding-detectedVsAuthoritative**).
    let badge: String

    /// `true` when ``RoutedTranscript/detectedLanguage`` differs from
    /// ``RoutedTranscript/authoritativeLanguage`` (a SEAM-2 divergence
    /// window). Drives the small fallback marker on the row.
    let showsFallbackMarker: Bool

    /// Composed accessibility label used by the row body.
    let accessibilityLabel: String
}

extension TranscriptRowDisplay {
    /// Derives a display value from a ``RoutedTranscript``. Pure — no
    /// SwiftUI dependency, safe to call from tests.
    init(routed: RoutedTranscript) {
        text = routed.text
        badge = TranscriptRowDisplay.badgeString(for: routed.detectedLanguage)
        showsFallbackMarker = routed.detectedLanguage != routed.authoritativeLanguage
        let detectedDisplay = routed.detectedLanguage.displayName
        if showsFallbackMarker {
            let authoritativeDisplay = routed.authoritativeLanguage.displayName
            accessibilityLabel = "\(routed.text). Detected \(detectedDisplay), gate held \(authoritativeDisplay)."
        } else {
            accessibilityLabel = "\(routed.text). \(detectedDisplay)."
        }
    }

    /// Two-letter UI badge — uppercased ISO 639-1 code.
    static func badgeString(for language: SpokenLanguage) -> String {
        language.rawValue.uppercased()
    }
}

// MARK: - Row view

/// Single transcript row: text on the left, language badge plus optional
/// fallback marker on the right.
private struct TranscriptRow: View {
    let display: TranscriptRowDisplay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(display.text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                if display.showsFallbackMarker {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Language fallback")
                }
                Text(display.badge)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.meterTrack, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.accessibilityLabel)
    }
}

// MARK: - Indicator chrome display value

/// Pure value-type rendering of the language indicator chrome. Derived
/// entirely from ``LanguageRouter/currentLanguage`` and
/// ``AppBootstrapper/loaderState`` so tests can assert binding contracts
/// (chrome reads ``LanguageRouter/currentLanguage``, NOT any per-row
/// data) without rendering the view.
struct IndicatorChromeDisplay: Equatable {
    /// Two-letter badge: "JA", "EN", or em-dash.
    let languageBadge: String

    /// Accessibility label for the language badge.
    let languageAccessibilityLabel: String

    /// Whether to render the "listening…" hint next to the dash badge.
    let showsListeningHint: Bool

    /// Short label for the warmup pill ("idle", "warming…", "ready",
    /// "failed").
    let warmupLabel: String

    /// Color token for the warmup pill dot.
    let warmupColor: Color

    /// Accessibility label for the warmup pill.
    let warmupAccessibilityLabel: String

    /// Trailing error text rendered next to the pill on `.failed`. `nil`
    /// otherwise.
    let warmupErrorText: String?

    /// `true` when the failed-state ``warmupErrorText`` region should
    /// render with the semantic `.secondary` foreground rather than
    /// the red ``Color/recordingActive`` token. Locked by V3 #40
    /// concern 2 (Step 9b) — the red warmup dot alone carries the
    /// failed semantic; doubling red on the adjacent text overloaded
    /// the chrome region. The view body honors this flag by switching
    /// `.foregroundStyle(.secondary)` for the error text when `true`.
    let warmupErrorTextUsesSecondaryForeground: Bool

    /// `true` when the record control should be disabled (failed loader).
    let recordButtonDisabled: Bool

    init(currentLanguage: SpokenLanguage?, loaderState: LoaderState) {
        if let currentLanguage {
            languageBadge = currentLanguage.rawValue.uppercased()
            languageAccessibilityLabel = "Current language: \(currentLanguage.displayName)"
            showsListeningHint = false
        } else {
            languageBadge = "—"
            languageAccessibilityLabel = "Current language: not yet detected"
            showsListeningHint = true
        }

        switch loaderState {
        case .idle:
            warmupLabel = "idle"
            warmupColor = Color.recordingIdle
            warmupAccessibilityLabel = "Whisper warmup idle"
            warmupErrorText = nil
            warmupErrorTextUsesSecondaryForeground = true
            recordButtonDisabled = false
        case .loading:
            warmupLabel = "warming…"
            warmupColor = Color.recordingActive
            warmupAccessibilityLabel = "Whisper warming up"
            warmupErrorText = nil
            warmupErrorTextUsesSecondaryForeground = true
            recordButtonDisabled = false
        case .loaded:
            warmupLabel = "ready"
            // V3 #40 concern 1 (Step 9b): replaces the prior ad-hoc
            // `Color.green` with the canonical `recordingReady` token
            // (calm green at RGB 0.26, 0.66, 0.45 — chromatically
            // distinct from `recordingActive`'s red, locked by
            // `DesignSystemTests.recordingReady_hueDistinctFromRecordingActive`).
            warmupColor = DesignSystem.Colors.recordingReady
            warmupAccessibilityLabel = "Whisper ready"
            warmupErrorText = nil
            warmupErrorTextUsesSecondaryForeground = true
            recordButtonDisabled = false
        case let .failed(error):
            warmupLabel = "failed"
            warmupColor = Color.recordingActive
            warmupErrorTextUsesSecondaryForeground = true
            warmupAccessibilityLabel = "Whisper warmup failed"
            warmupErrorText = error.errorDescription ?? "Unknown error"
            recordButtonDisabled = true
        }
    }
}

// Step 7 (2026-05-16) — Surgical D7-2 swap. `RecordControl`,
// `RecordButton`, and `VUMeter` were deleted here; the bottom region
// now hosts ``MeetingControlsView`` driven by a
// ``MeetingControlsViewModel`` injected via ``TranscriptLiveView/init``.
// The deleted controls were the Phase-3 single-button capture surface;
// the new surface morphs through five meeting states per UI #3 + #4.
// The `RecordControl` was the only call site for
// `AudioCaptureViewModel(router:)`'s drain path — that path is dormant
// under Group D and tracked by the V3 "dead router-drain" entry.

// MARK: - Preview support

#if DEBUG

    import Darwin.Mach
    import os

    /// Test-only Whisper client used by the SwiftUI previews. Returns a
    /// pre-configured language code per call so previews can populate
    /// ``LanguageRouter/routedHistory`` deterministically.
    ///
    /// Mirrors the pattern in ``LanguageRouterTests`` so previews and tests
    /// share the same shape of fake. Kept file-private and gated under
    /// `#if DEBUG` so it is excluded from release builds.
    private final nonisolated class PreviewWhisperClient: WhisperClient, @unchecked Sendable {
        private struct State {
            var languages: [String]
            var nextIndex: Int = 0
        }

        private let state: OSAllocatedUnfairLock<State>
        private let scriptedText: [String]

        init(languages: [String], scriptedText: [String]) {
            state = OSAllocatedUnfairLock(initialState: State(languages: languages))
            self.scriptedText = scriptedText
        }

        func prewarmModels() async throws {}

        func transcribe(
            audio _: [Float],
            anchorHostTime: UInt64
        ) async throws -> WhisperWindowResult {
            let (code, text) = state.withLock { snapshot -> (String, String) in
                let index = min(snapshot.nextIndex, max(0, snapshot.languages.count - 1))
                let language = snapshot.languages.isEmpty ? "" : snapshot.languages[index]
                let textIndex = min(snapshot.nextIndex, max(0, scriptedText.count - 1))
                let text = scriptedText.isEmpty ? "" : scriptedText[textIndex]
                snapshot.nextIndex += 1
                return (language, text)
            }
            let segment = WhisperRawSegment(
                text: text,
                startSeconds: 0,
                endSeconds: 5,
                avgLogprob: 0
            )
            return WhisperWindowResult(
                language: code,
                windowAnchorHostTime: anchorHostTime,
                segments: [segment]
            )
        }
    }

    /// Helpers for ``TranscriptLiveView``'s SwiftUI previews. Builds an
    /// ``AppBootstrapper`` whose router has been pre-driven through a
    /// ``PreviewWhisperClient`` so ``LanguageRouter/routedHistory`` is
    /// populated and ``LanguageRouter/currentLanguage`` reflects a
    /// realistic gate state.
    enum TranscriptLiveViewPreviewSupport {
        /// Three-window divergence script: `[ja, en, en]` flips authoritative
        /// to `.en` on the third window. Window 2 is the SEAM-2 divergence
        /// (detected = en, authoritative = ja).
        @MainActor
        static func divergenceSample() -> [RoutedTranscript] {
            populate(
                bootstrapperWith: ["ja", "en", "en"],
                scriptedText: [
                    "おはようございます",
                    "Good morning everyone",
                    "Let's get started",
                ]
            )
        }

        /// 50-row long-scrollback sample alternating Japanese and English
        /// in 5-window blocks so the preview exercises the gate's flip
        /// behaviour multiple times. Useful for verifying scrolling, row
        /// height, and divergence-marker density.
        @MainActor
        static func longScrollbackSample() -> [RoutedTranscript] {
            var languages: [String] = []
            var texts: [String] = []
            let jaPhrases = [
                "次の話題に移ります",
                "数字を確認しましょう",
                "それは興味深いですね",
                "後で連絡します",
                "ありがとうございます",
            ]
            let enPhrases = [
                "Moving to the next topic",
                "Let's review the numbers",
                "That's an interesting point",
                "I'll follow up after this",
                "Thanks everyone",
            ]
            for block in 0 ..< 10 {
                let isJaBlock = block % 2 == 0
                for entry in 0 ..< 5 {
                    languages.append(isJaBlock ? "ja" : "en")
                    let phrase = isJaBlock
                        ? jaPhrases[entry % jaPhrases.count]
                        : enPhrases[entry % enPhrases.count]
                    texts.append(phrase)
                }
            }
            return populate(bootstrapperWith: languages, scriptedText: texts)
        }

        /// Builds an ``AppBootstrapper`` for use as a SwiftUI preview
        /// environment. When `history` is non-empty the helper writes
        /// directly through ``LanguageRouter``'s scripted upstream so the
        /// preview observes a realistic state. When `history` is empty
        /// the bootstrapper's router is left untouched (empty-state
        /// preview).
        @MainActor
        static func makeBootstrapper(history: [RoutedTranscript]) -> AppBootstrapper {
            // Even when the caller supplies a pre-baked `history` array,
            // we cannot mutate `LanguageRouter.routedHistory` directly —
            // it is `private(set)`. The intended preview path is to drive
            // the router through a `PreviewWhisperClient` (see
            // `divergenceSample()` and `longScrollbackSample()` which call
            // `populate(...)` to do exactly that). The `history` argument
            // exists so call sites can express intent ("show me the empty
            // state" vs "show me a populated state"); the populated case
            // returns a bootstrapper whose router was already driven.
            //
            // For the empty-state callers the supplied `history` is
            // unused and we hand back a fresh bootstrapper.
            _ = history
            return AppBootstrapper(loader: WhisperModelLoader(factory: { _ in
                PreviewWhisperClient(languages: [], scriptedText: [])
            }))
        }

        /// Builds a bootstrapper whose router has been driven through
        /// `languages` (one upstream window per code), then returns the
        /// resulting `routedHistory` so callers can also pass it through
        /// `makeBootstrapper(history:)` if they want both shapes. Kept
        /// internal so the populated-preview helpers can synthesise the
        /// same routed-history snapshot without the type-system
        /// gymnastics of returning two values from one helper.
        @MainActor
        private static func populate(
            bootstrapperWith languages: [String],
            scriptedText: [String]
        ) -> [RoutedTranscript] {
            // Driving the router synchronously inside a preview helper
            // would require awaiting `transcribe(frames:)`, which is
            // async. Instead we run the drain inline using an
            // unsafe-blocking `DispatchSemaphore`-free pattern: the
            // helper returns the synthesised `RoutedTranscript` array
            // computed by replaying the same gate logic inline.
            //
            // This is safe because (a) the gate is pure, (b) we have the
            // full language script up front, and (c) previews are not the
            // contract surface for the gate — `LanguageRouterTests` is.
            // We mirror the gate's state machine here verbatim so the
            // shape of the array matches what the production router
            // would produce.
            //
            // Phase 7 may replace this with a real router drain via a
            // `.task` modifier on a wrapper preview view; until then this
            // pure replay keeps the preview synchronous and trivial.
            return synthesiseRoutedHistory(
                languages: languages,
                scriptedText: scriptedText
            )
        }

        /// Pure replay of ``LanguageRouter``'s gate state machine for a
        /// preview script. Keeps SwiftUI previews synchronous — driving
        /// the real router would require an async drain that previews
        /// cannot easily await. Mirrors the rules in
        /// ``LanguageRouter/process(window:)``:
        ///
        /// 1. Unsupported codes drop silently.
        /// 2. First supported code establishes authoritative.
        /// 3. Agreement resets the disagreement counter.
        /// 4. Disagreement bumps the counter; on threshold the gate flips.
        ///
        /// The contract this method exists to satisfy is "previews look
        /// realistic", not "this method is correct". The router itself
        /// is the source of truth and is locked by
        /// ``LanguageRouterTests``.
        private static func synthesiseRoutedHistory(
            languages: [String],
            scriptedText: [String]
        ) -> [RoutedTranscript] {
            var history: [RoutedTranscript] = []
            var authoritative: SpokenLanguage?
            var counter = 0
            let confirmationsRequired = LanguageRouter.defaultConfirmationsRequired

            for (index, code) in languages.enumerated() {
                guard let detected = SpokenLanguage(whisperCode: code) else {
                    // Unsupported code — drop silently.
                    continue
                }
                let text = index < scriptedText.count ? scriptedText[index] : ""
                let didFlip: Bool
                let resolvedAuthoritative: SpokenLanguage
                if let current = authoritative {
                    if detected == current {
                        counter = 0
                        resolvedAuthoritative = current
                        didFlip = false
                    } else {
                        let next = counter + 1
                        if next >= confirmationsRequired {
                            authoritative = detected
                            resolvedAuthoritative = detected
                            counter = 0
                            didFlip = true
                        } else {
                            counter = next
                            resolvedAuthoritative = current
                            didFlip = false
                        }
                    }
                } else {
                    authoritative = detected
                    resolvedAuthoritative = detected
                    counter = 0
                    didFlip = false
                }
                history.append(
                    RoutedTranscript(
                        id: UUID(),
                        text: text,
                        detectedLanguage: detected,
                        authoritativeLanguage: resolvedAuthoritative,
                        didFlip: didFlip,
                        windowAnchorHostTime: UInt64(index),
                        windowStartSeconds: Double(index),
                        windowEndSeconds: Double(index) + 5,
                        isFinal: false
                    )
                )
            }
            return history
        }
    }

    /// Wrapper view that lets a preview render a populated routed history
    /// without mutating the underlying ``LanguageRouter`` (whose
    /// ``LanguageRouter/routedHistory`` setter is `private(set)`). The
    /// wrapper feeds a synthesised history directly into a stand-in
    /// view that mirrors ``TranscriptLiveView``'s middle region. The
    /// chrome and bottom regions remain bound to the real bootstrapper.
    private struct PopulatedPreviewWrapper: View {
        let bootstrapper: AppBootstrapper
        let history: [RoutedTranscript]

        var body: some View {
            VStack(spacing: 0) {
                // Top: language chrome derived directly from the supplied
                // history so previews look right even though the
                // underlying router is empty.
                let lastAuthoritative = history.last?.authoritativeLanguage
                let chrome = IndicatorChromeDisplay(
                    currentLanguage: lastAuthoritative,
                    loaderState: bootstrapper.loaderState
                )
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(chrome.languageBadge)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.meterTrack, in: Capsule())
                        if chrome.showsListeningHint {
                            Text("listening…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Circle().fill(chrome.warmupColor).frame(width: 6, height: 6)
                        Text(chrome.warmupLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.meterTrack.opacity(0.6), in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Middle: synthesised list using the same TranscriptRow.
                List(history) { routed in
                    TranscriptRow(display: TranscriptRowDisplay(routed: routed))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom: footer only — the real RecordControl needs a
                // real microphone permission flow which is irrelevant to
                // the layout-focused preview.
                Text("Audio never leaves your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfaceBackground)
        }
    }

    // MARK: - Previews

    #Preview("Light — empty") {
        TranscriptLiveView()
            .environment(TranscriptLiveViewPreviewSupport.makeBootstrapper(history: []))
            .preferredColorScheme(.light)
    }

    #Preview("Dark — empty") {
        TranscriptLiveView()
            .environment(TranscriptLiveViewPreviewSupport.makeBootstrapper(history: []))
            .preferredColorScheme(.dark)
    }

    #Preview("Light — divergence") {
        PopulatedPreviewWrapper(
            bootstrapper: TranscriptLiveViewPreviewSupport.makeBootstrapper(history: []),
            history: TranscriptLiveViewPreviewSupport.divergenceSample()
        )
        .preferredColorScheme(.light)
    }

    #Preview("Dark — divergence") {
        PopulatedPreviewWrapper(
            bootstrapper: TranscriptLiveViewPreviewSupport.makeBootstrapper(history: []),
            history: TranscriptLiveViewPreviewSupport.divergenceSample()
        )
        .preferredColorScheme(.dark)
    }

    #Preview("Light — long scrollback") {
        PopulatedPreviewWrapper(
            bootstrapper: TranscriptLiveViewPreviewSupport.makeBootstrapper(history: []),
            history: TranscriptLiveViewPreviewSupport.longScrollbackSample()
        )
        .preferredColorScheme(.light)
    }

#endif
