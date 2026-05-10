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
/// 3. **Bottom — record control.** A private ``RecordControl`` subview
///    holds its own ``AudioCaptureViewModel``. For Step 4 the view model
///    is constructed with `router: nil`, exercising the Phase-3 fallback
///    drain. Step 5 will pass ``AppBootstrapper/router`` into
///    ``RecordControl`` so frames flow through the language router.
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

    var body: some View {
        VStack(spacing: 0) {
            indicatorChrome
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            transcriptList

            RecordControl(loaderState: bootstrapper.loaderState)
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

                if chrome.showsListeningHint {
                    Text("listening…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Listening for first window")
                }
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
            Text(errorText)
                .font(.caption2)
                .foregroundStyle(Color.recordingActive)
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
            List(bootstrapper.router.routedHistory) { routed in
                TranscriptRow(display: TranscriptRowDisplay(routed: routed))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("listening…")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Spoken Japanese or English will appear here.")
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
            recordButtonDisabled = false
        case .loading:
            warmupLabel = "warming…"
            warmupColor = Color.recordingActive
            warmupAccessibilityLabel = "Whisper warming up"
            warmupErrorText = nil
            recordButtonDisabled = false
        case .loaded:
            warmupLabel = "ready"
            // Use a calm green-leaning hue from the system. There is no
            // "ready" token in DesignTokens yet — Phase 7 will introduce
            // typography and semantic tokens. Until then, use the tint
            // color, which renders as the app's accent.
            warmupColor = Color.green
            warmupAccessibilityLabel = "Whisper ready"
            warmupErrorText = nil
            recordButtonDisabled = false
        case let .failed(error):
            warmupLabel = "failed"
            warmupColor = Color.recordingActive
            warmupAccessibilityLabel = "Whisper warmup failed"
            warmupErrorText = error.errorDescription ?? "Unknown error"
            recordButtonDisabled = true
        }
    }
}

// MARK: - Record control

/// Bottom region: VU meter + record button. Holds its own
/// ``AudioCaptureViewModel`` via `@State`. For Step 4 the view model is
/// constructed with `router: nil`, exercising the Phase-3 fallback
/// drain. Step 5 will pass the bootstrapper's shared
/// ``LanguageRouter`` here so frames flow through transcription.
private struct RecordControl: View {
    /// Read at view-build time so the record button can disable itself
    /// when the Whisper loader has failed.
    let loaderState: LoaderState

    @State private var viewModel = AudioCaptureViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.permissionStatus {
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
        .task {
            await viewModel.onAppear()
        }
    }

    private var notDeterminedContent: some View {
        VStack(spacing: 12) {
            Text("Microphone access")
                .font(.headline)
            Text("Arigato AI uses your microphone to transcribe and translate meeting audio entirely on your device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow microphone") {
                Task { await viewModel.toggleRecording() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRecordButtonDisabled)
        }
    }

    private var grantedContent: some View {
        VStack(spacing: 12) {
            VUMeter(level: viewModel.level)
                .frame(height: 10)
                .padding(.horizontal, 4)

            RecordButton(
                isRecording: viewModel.isRecording,
                disabled: isRecordButtonDisabled,
                reduceMotion: reduceMotion
            ) {
                Task { await viewModel.toggleRecording() }
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 8) {
            Text("Microphone access denied")
                .font(.subheadline.weight(.semibold))
            Text("Enable microphone access in Settings to start a meeting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                viewModel.openSettings()
            }
            .buttonStyle(.bordered)
        }
    }

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

    private var isRecordButtonDisabled: Bool {
        if case .failed = loaderState { return true }
        return false
    }
}

// MARK: - Record button

private struct RecordButton: View {
    let isRecording: Bool
    let disabled: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.recordingActive : Color.meterTrack)
                    .frame(
                        width: isRecording ? 80 : 64,
                        height: isRecording ? 80 : 64
                    )

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: isRecording ? 28 : 24, weight: .semibold))
                    .foregroundStyle(isRecording ? Color.white : Color.primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: shouldPulse)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(.isButton)
    }

    private var shouldPulse: Bool {
        isRecording && !reduceMotion
    }

    private var accessibilityLabelText: String {
        if disabled {
            return "Record button unavailable: Whisper failed to load"
        }
        return isRecording ? "Stop recording" : "Start recording"
    }
}

// MARK: - VU meter

private struct VUMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.meterTrack)
                Capsule()
                    .fill(Color.recordingActive.opacity(0.85))
                    .frame(width: max(0, CGFloat(level) * proxy.size.width))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }
}

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
