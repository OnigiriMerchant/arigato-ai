//
//  MeetingDetailView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData
import SwiftUI

/// Detail screen for a single past meeting — the pushable destination
/// behind a row tap in ``MeetingListView``. **First step of Phase 3 of
/// Group D** (history detail / search / export / onboarding / settings).
///
/// ## Naming note (load-bearing)
///
/// This view's data source is ``MeetingDetail/SentenceProjection`` (the
/// DTO from Step 2). The two share the `MeetingDetail` prefix by
/// coincidence; they are distinct types — ``MeetingDetail`` is the
/// Sendable DTO container, ``MeetingDetailView`` is this view.
///
/// ## Surface
///
/// Renders the locked Group D UI decisions:
/// - **#5** — header layout (title + date + duration). Title is the
///   navigation-bar title; date + duration render in a metadata HStack
///   below the title.
/// - **#13** — full transcript displayed as a `List` of source-led
///   rows (spoken language, translation, metadata cluster), oldest-first.
/// - **#14** — read-only. **No delete, no rename, no edit, no inline
///   mutation.** Step 12 lands search; Step 13 lands the export
///   `ShareLink`; deletion lives in `MeetingListView`'s multi-select
///   mode (also Step 13).
/// - **#15** — timestamp consistency. The header date and per-row
///   timestamps are byte-identical to the same values rendered in
///   ``MeetingListRow`` (history list) and ``TranscriptSplitScreenView``
///   (live transcript). Enforced by ``MeetingDetailFormatter``'s
///   delegation to the existing formatters.
///
/// Step 13 ShareLink (UI #9 Context B) lands in the empty toolbar slot;
/// see the marker inside the body.
///
/// ## Read path
///
/// The header renders from the navigation value (``MeetingSummary``)
/// fields directly — no second store fetch. The body renders from
/// ``MeetingDetailViewModel/sentences``, populated by a single
/// `.task(id:)`-driven ``MeetingDetailViewModel/reload()`` call against
/// ``MeetingStore/fetchSentences(meetingID:)``.
///
/// ## Styling
///
/// **Phase 7 Decision 6 (2026-05-31): source-led monochrome layout.**
/// Transcript rows render via ``TranscriptCaptionRow`` consuming the
/// Phase 7 ``DesignSystem`` tokens — the spoken-language line leads
/// (``DesignSystem/Colors/transcriptSource``), the translation follows
/// (``DesignSystem/Colors/transcriptTranslation``, a colour-only
/// difference), and a tertiary SF Mono metadata cluster carries the
/// language tag + timestamp. The transcript sits on a solid
/// ``DesignSystem/Colors/surfaceContent`` surface — never glass. The
/// header, empty, and error states keep stock system fonts + semantic
/// colors (UI #17/#18); the toolbar's Liquid Glass chrome lands in the
/// next checkpoint.
@MainActor
struct MeetingDetailView: View {
    /// The summary handed in as the `NavigationLink` value. Header
    /// renders from these fields with no extra fetch.
    let summary: MeetingSummary

    /// Backing view model — owns the reload pipeline and the
    /// sentences/loadError/refreshTrigger slice of state. Held as
    /// `@State` so SwiftUI retains it across re-renders.
    @State private var model: MeetingDetailViewModel

    /// Incremented each time the Copy toolbar button fires. Drives
    /// `.sensoryFeedback(.success, trigger:)` — the only confirmation the
    /// copy succeeded (no "Copied" toast; dropped from scope).
    @State private var copyFeedbackTrigger = 0

    /// Production initializer — closes the VM over the actor-backed
    /// store via the convenience init on ``MeetingDetailViewModel``.
    ///
    /// - Parameters:
    ///   - summary: The navigation value handed in from
    ///     ``MeetingListView``. Header renders from this without a
    ///     second store fetch.
    ///   - store: The actor-backed read source.
    init(summary: MeetingSummary, store: MeetingStore) {
        self.summary = summary
        _model = State(
            wrappedValue: MeetingDetailViewModel(store: store, meetingID: summary.id)
        )
    }

    /// Test-only / preview initializer — accepts a pre-built view model
    /// so callers can drive success, failure, and ordering behavior
    /// without owning a real ``MeetingStore`` actor.
    ///
    /// - Parameters:
    ///   - summary: The navigation value. Drives the header.
    ///   - viewModel: A pre-built VM (typically with a closure-injected
    ///     fetcher).
    init(summary: MeetingSummary, viewModel: MeetingDetailViewModel) {
        self.summary = summary
        _model = State(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error = model.loadError {
                errorState(error)
            } else if model.sentences.isEmpty {
                emptyState
            } else {
                sentenceList
            }
        }
        .accessibilityIdentifier("meeting.detail.root")
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.refreshTrigger) {
            await model.reload()
        }
        .toolbar {
            // MVP-1 #11 — Copy the full transcript Markdown to the
            // pasteboard. Same exporter body as the ShareLink below, so
            // pasted text is byte-identical to the shared file. Gated
            // identically (UI decision #4 "buttons exist only when
            // usable."). Placed leading of the ShareLink so Share stays
            // trailing-most, matching iOS convention.
            ToolbarItem(placement: .topBarTrailing) {
                if !model.sentences.isEmpty {
                    Button {
                        model.copyTranscript(summary: summary)
                        copyFeedbackTrigger += 1
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .accessibilityLabel("Copy transcript")
                    }
                    .accessibilityIdentifier("meeting.detail.copyButton")
                }
            }

            // Step 13 — UI #9 Context B (detail-view share) + UI #10
            // (Markdown format). Hidden when the transcript is empty
            // (UI decision #4 "buttons exist only when usable.") OR
            // when `TranscriptExporter` fails to write the temp file.
            ToolbarItem(placement: .topBarTrailing) {
                if !model.sentences.isEmpty, let exportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel("Share transcript")
                    }
                    .accessibilityIdentifier("meeting.detail.shareButton")
                }
            }
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTrigger)
    }

    /// Synthesises the temp-file URL for the current transcript on
    /// demand. Returns `nil` if ``TranscriptExporter/writeTemporaryFile(markdown:filename:)``
    /// throws — the toolbar item then hides, matching UI decision #4
    /// "buttons exist only when usable."
    ///
    /// Write-on-recompute is acceptable for MVP 1 scale (30–60 KB body
    /// written in well under a render tick). The body is regenerated
    /// every time SwiftUI re-evaluates the toolbar; collision policy
    /// inside ``TranscriptExporter`` is the second-line defence against
    /// same-second re-renders. Post-MVP optimization candidate: cache the
    /// URL keyed off `(summary.id, model.sentences.count)` and invalidate
    /// on change.
    private var exportURL: URL? {
        do {
            let body = TranscriptExporter.markdownBody(
                summary: summary,
                sentences: model.sentences
            )
            let filename = TranscriptExporter.makeFilename(
                title: summary.title,
                startedAt: summary.startedAt
            )
            return try TranscriptExporter.writeTemporaryFile(
                markdown: body,
                filename: filename
            )
        } catch {
            return nil
        }
    }

    /// Header — date + duration. Title renders via `.navigationTitle`,
    /// so the metadata row sits flush at the top of the body.
    private var header: some View {
        HStack(spacing: 8) {
            Text(MeetingDetailFormatter.formattedDate(summary.startedAt))
            Text("·")
            Text(
                MeetingDetailFormatter.formattedDuration(
                    started: summary.startedAt,
                    ended: summary.endedAt
                )
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Empty-state placeholder shown when the store has no sentences
    /// for this meeting and no error has surfaced (e.g. a meeting that
    /// ended before any sentences were translated). Pure stock SwiftUI
    /// styling per UI decision #18.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No transcript captured")
                .font(.headline)
            Text("This meeting ended before any sentences were translated.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Inline error state. Errors are stored in
    /// ``MeetingDetailViewModel/loadError`` rather than thrown out of
    /// the view body; this branch renders the captured message.
    private func errorState(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Couldn't load transcript")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Main transcript list — **source-led** rows (Phase 7 Decision 6):
    /// each row leads with the spoken-language text, the translation
    /// follows (colour-only difference), and a tertiary SF Mono metadata
    /// cluster (language tag + `HH:mm:ss` timestamp) closes it. Styling
    /// flows from the Phase 7 ``DesignSystem`` tokens via
    /// ``TranscriptCaptionRow``. Rows are read-only per UI decision #14.
    ///
    /// `List` is retained — it lazily reuses rows, so a long transcript
    /// does not build every row up front. Its system chrome is stripped
    /// (plain style, hidden separators, clear row background) so the solid
    /// ``DesignSystem/Colors/surfaceContent`` surface shows through. Glass
    /// is **not** applied here; content surfaces stay solid (Decision 6 /
    /// `docs/PHASE_7_DESIGN_RESEARCH.md` collision A).
    private var sentenceList: some View {
        List {
            ForEach(model.sentences, id: \.id) { sentence in
                let body = MeetingDetailFormatter.sentenceBody(for: sentence)
                TranscriptCaptionRow(
                    source: body.source,
                    translation: body.translation,
                    languageTag: body.languageTag,
                    timestamp: body.timestamp
                )
                .listRowInsets(
                    EdgeInsets(
                        top: 0,
                        leading: DesignSystem.Spacing.contentHorizontalInset,
                        bottom: 0,
                        trailing: DesignSystem.Spacing.contentHorizontalInset
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.surfaceContent)
    }
}

#if DEBUG
    /// Preview fixture builder. `PersistentIdentifier` has no public
    /// initializer, so both ``MeetingSummary`` and
    /// ``MeetingDetail/SentenceProjection`` need a real identifier minted
    /// from an in-memory container — the same pattern the tests use. The
    /// throwing setup is isolated here and surfaced as an optional so the
    /// `#Preview` can branch to a diagnostic fallback rather than
    /// force-unwrap or silence the error.
    @MainActor
    private enum MeetingDetailPreviewFixture {
        /// A ready-to-render fixture: a summary plus sample projections.
        struct Sample {
            let summary: MeetingSummary
            let sentences: [MeetingDetail.SentenceProjection]
        }

        /// Mints a real identifier and builds 3 sample sentences spanning
        /// both source languages so the preview exercises the JA/EN row
        /// formatting. Returns `nil` if the in-memory container cannot be
        /// built (the `#Preview` then renders a diagnostic placeholder).
        static func make() -> Sample? {
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: Meeting.self, Sentence.self,
                    configurations: config
                )
                let context = ModelContext(container)
                let started = Date(timeIntervalSince1970: 1_700_000_000)
                let meeting = Meeting(startedAt: started, title: "Design sync")
                meeting.endedAt = started.addingTimeInterval(18 * 60)
                context.insert(meeting)

                // Insert three real Sentence rows so each projection gets a
                // DISTINCT `persistentModelID`. `ForEach(id: \.id)` dedupes
                // identical ids, so reusing the meeting's id (the only id
                // mintable without a public `PersistentIdentifier` init)
                // would collapse the list to a single repeated row. The
                // drafts deliberately mix ja-source and en-source lines so
                // the preview exercises the source-led layout's mixed tags.
                let drafts: [(offset: TimeInterval, lang: String, source: String, translation: String)] = [
                    (5, "ja", "おはようございます。始めましょう。", "Good morning. Let's begin."),
                    (20, "en", "Sounds good — I'll share my screen.", "いいですね。画面を共有します。"),
                    (42, "ja", "ありがとうございます。", "Thank you."),
                ]
                let inserted: [Sentence] = drafts.map { draft in
                    let s = Sentence(
                        timestamp: started.addingTimeInterval(draft.offset),
                        sourceLanguage: draft.lang,
                        sourceText: draft.source,
                        translatedText: draft.translation,
                        sourceSegmentID: UUID(),
                        searchableText: "\(draft.source) \(draft.translation)"
                    )
                    s.meeting = meeting
                    context.insert(s)
                    return s
                }
                try context.save()

                let sentences = inserted.map { s in
                    MeetingDetail.SentenceProjection(
                        id: s.persistentModelID,
                        timestamp: s.timestamp,
                        sourceLanguage: s.sourceLanguage,
                        sourceText: s.sourceText,
                        translatedText: s.translatedText,
                        sourceSegmentID: s.sourceSegmentID
                    )
                }
                return Sample(summary: MeetingSummary(from: meeting), sentences: sentences)
            } catch {
                return nil
            }
        }
    }

    #Preview {
        NavigationStack {
            if let sample = MeetingDetailPreviewFixture.make() {
                MeetingDetailView(
                    summary: sample.summary,
                    viewModel: MeetingDetailViewModel(
                        meetingID: sample.summary.id,
                        fetcher: { _ in sample.sentences }
                    )
                )
            } else {
                Text("Preview fixture unavailable")
            }
        }
    }
#endif
