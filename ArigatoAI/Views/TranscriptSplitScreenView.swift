//
//  TranscriptSplitScreenView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData
import SwiftUI

/// Split-screen transcript surface — Japanese column on top, English
/// column on bottom, divided by a thin separator (UI decision #1).
/// Replaces ``TranscriptLiveView``'s middle region under Step 9a.
///
/// ## Layout (UI decision #1)
///
/// `VStack(spacing: 0)` with two equal halves:
/// 1. **Top — Japanese column.** Scrollable list of rows projected via
///    ``TranscriptSplitScreenFormatter/japaneseRow(for:)``.
/// 2. **Divider.** Uses ``DesignSystem/Colors/columnDivider`` (Step 9b
///    token) so the divider adapts to light/dark appearance.
/// 3. **Bottom — English column.** Scrollable list of rows projected
///    via ``TranscriptSplitScreenFormatter/englishRow(for:)``.
///
/// Each column owns an independent `ScrollPosition` + at-bottom boolean
/// (see ``TranscriptSplitScreenViewModel``) so per-column scrollback +
/// auto-follow is independent per UI decision #2.
///
/// ## Auto-follow scroll (UI decision #2)
///
/// When the user is at the bottom of a column, new sentences scroll
/// into view automatically. When the user scrolls up to re-read,
/// incoming sentences arrive in the data layer but the view does NOT
/// yank back. A unified "return arrow" overlay appears whenever
/// **either** column is scrolled up; tapping the arrow scrolls both
/// columns back to bottom inside one animation transaction.
///
/// The follow decision is **owned by the view model**, not recomputed in
/// the view body. Each column's `.onChange(of: sentences)` observer asks
/// ``TranscriptSplitScreenViewModel/shouldFollow(column:)`` whether to
/// scroll. The VM captures that decision (``FollowIntent``) from the
/// at-bottom flags in the same non-suspending window it assigns
/// `sentences` (see the VM's capture-before-mutation invariant). This
/// removes a real ordering bug: the geometry callback driving the
/// at-bottom flags can flip a flag `false` (new `contentSize`, old
/// `contentOffset`) the instant `sentences` changes, and SwiftUI
/// documents no ordering between `.onScrollGeometryChange` and
/// `.onChange(of:)`. Reading a pre-captured intent makes the result
/// independent of which callback fires first. The geometry predicate
/// applies ``TranscriptSplitScreenViewModel/atBottomEpsilon`` (2pt) to
/// absorb resting-`contentOffset` float-exactness, biased toward
/// following.
///
/// ## Data flow
///
/// The view binds to a ``TranscriptSplitScreenViewModel`` and:
/// 1. Re-runs ``TranscriptSplitScreenViewModel/reload()`` whenever
///    ``TranscriptSplitScreenViewModel/refreshTrigger`` changes (driven
///    by the `sentencesDidUpdate` callback wired in ``ContentView``).
///    `.task(id:)` cancellation gives last-query-wins semantics — see
///    the type-level scheduling assumption on the VM.
/// 2. Reports per-column scroll geometry via
///    `.onScrollGeometryChange(for: Bool.self, of: { ... })` so the VM
///    can compose ``TranscriptSplitScreenViewModel/arrowVisible``.
///
/// ## Styling (Phase 7 token-aligned)
///
/// Body and timestamp text route through the Phase 7
/// ``DesignSystem/Typography`` tokens — ``transcriptText`` (`.body`) for
/// the row text and ``metadataText`` (SF Mono `.caption2`) for the
/// timestamp. Both columns stay **equal-weight** (`.primary`): the
/// split-screen has no source/translation tonal hierarchy (UI decision
/// #1 keeps the two languages spatially separated, not interleaved — so
/// the detail view's source-led primary/secondary split does NOT apply
/// here). The per-row timestamp flows **inline** as a trailing suffix
/// after the caption's last wrapped line (not in a reserved right-hand
/// column — see ``SplitScreenRow``) and renders in
/// ``DesignSystem/Colors/metadataForeground``, the canonical tertiary
/// metadata-role token. (This converges the per-row timestamp tint onto
/// `metadataForeground`; the former ``DesignSystem/Colors/timestampForeground``
/// token resolved to the same `.tertiaryLabel` value and is left defined
/// but no longer consumed by this view — D6.) The return-arrow background
/// uses ``DesignSystem/Colors/returnArrowBackground``. Colors are semantic
/// system colors so the JA/EN columns adapt to dark mode automatically
/// (UI decisions #17 + #18 — system fonts handle CJK fallback).
///
/// ## Concurrency
///
/// View body is main-actor-isolated by SwiftUI's render machinery. The
/// VM is `@MainActor @Observable`. No bridging or hops are required at
/// this layer; the actor-hop semantics live inside the VM's fetcher
/// closure.
struct TranscriptSplitScreenView: View {
    /// The split-screen view model. Held as `@Bindable` so SwiftUI can
    /// route the `ScrollPosition` bindings to
    /// `.scrollPosition($viewModel.jaPosition)` /
    /// `.scrollPosition($viewModel.enPosition)`.
    @Bindable var viewModel: TranscriptSplitScreenViewModel

    var body: some View {
        VStack(spacing: 0) {
            japaneseColumn
            Divider().background(DesignSystem.Colors.columnDivider)
            englishColumn
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.arrowVisible {
                returnArrowButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .accessibilityLabel("Scroll to bottom of both columns")
            }
        }
        .task(id: viewModel.refreshTrigger) {
            await viewModel.reload()
        }
    }

    // MARK: - Columns

    /// Top half — Japanese rows. Renders the empty-state placeholder
    /// when ``TranscriptSplitScreenViewModel/sentences`` is empty;
    /// otherwise iterates the projection and renders rows.
    private var japaneseColumn: some View {
        column(
            column: .japanese,
            rowFor: TranscriptSplitScreenFormatter.japaneseRow(for:),
            scrollPosition: $viewModel.jaPosition,
            atBottomChanged: viewModel.setJaAtBottom(_:)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Bottom half — English rows. Mirrors ``japaneseColumn`` with the
    /// English-side projection + binding.
    private var englishColumn: some View {
        column(
            column: .english,
            rowFor: TranscriptSplitScreenFormatter.englishRow(for:),
            scrollPosition: $viewModel.enPosition,
            atBottomChanged: viewModel.setEnAtBottom(_:)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shared column builder.
    ///
    /// The auto-follow decision is NOT recomputed here. When `sentences`
    /// changes, the `.onChange` observer asks the VM
    /// (``TranscriptSplitScreenViewModel/shouldFollow(column:)``) whether
    /// this column should scroll. That answer is a snapshot the VM
    /// captured from the at-bottom flags in the same non-suspending window
    /// it assigned the new `sentences` value — capturing the intent
    /// *before* the mutation, rather than reading a live flag here, is the
    /// fix for the ordering bug where the geometry callback flips the flag
    /// `false` (new `contentSize`, old `contentOffset`) before this
    /// `.onChange` runs (SwiftUI documents no ordering between
    /// `.onScrollGeometryChange` and `.onChange(of:)`). The geometry
    /// predicate still drives the at-bottom flags (for the arrow + the
    /// *next* reload's intent capture) and applies
    /// ``TranscriptSplitScreenViewModel/atBottomEpsilon`` to absorb
    /// resting-`contentOffset` float-exactness.
    ///
    /// - Parameters:
    ///   - column: Identifies this column (JA or EN) so the `.onChange`
    ///     observer reads the matching per-column follow intent from the
    ///     VM.
    ///   - rowFor: Projection from a `SentenceProjection` to its
    ///     ``RowDisplay`` for this column (JA or EN).
    ///   - scrollPosition: The column-specific `ScrollPosition` binding
    ///     into the view model.
    ///   - atBottomChanged: Setter the geometry callback drives whenever
    ///     the column's bottom-edge predicate flips.
    @ViewBuilder
    private func column(
        column: TranscriptColumn,
        rowFor: @escaping (MeetingDetail.SentenceProjection) -> RowDisplay,
        scrollPosition: Binding<ScrollPosition>,
        atBottomChanged: @escaping (Bool) -> Void
    ) -> some View {
        if viewModel.sentences.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.sentences, id: \.id) { sentence in
                        SplitScreenRow(display: rowFor(sentence))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollPosition(scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // At-bottom predicate per DR-4 §iOS 18+ canonical: the
                // visible viewport's lower edge meets or exceeds the
                // content's lower edge, minus a small epsilon to absorb
                // resting-contentOffset float-exactness (biased toward
                // following — see atBottomEpsilon).
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - geometry.contentInsets.bottom
                    - TranscriptSplitScreenViewModel.atBottomEpsilon
            } action: { _, atBottom in
                atBottomChanged(atBottom)
            }
            .onChange(of: viewModel.sentences) { _, _ in
                // Auto-follow per UI #2: when new content arrives, scroll
                // this column to the bottom only if the VM's captured
                // follow intent says so. The decision was snapshotted by
                // reload() from the at-bottom flags in the same
                // non-suspending window it assigned `sentences` — reading
                // a pre-captured intent here (rather than a live flag)
                // removes the dependency on whether the geometry callback
                // or this .onChange fires first. Each column reads its own
                // intent, so a JA-scrolled-up + EN-at-bottom user sees
                // only the EN column auto-follow.
                if viewModel.shouldFollow(column: column) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollPosition.wrappedValue.scrollTo(edge: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    /// Empty-state placeholder shared by both columns when no sentences
    /// have been persisted yet. The text is intentionally bilingual —
    /// the split panes themselves communicate "JA on top, EN on bottom"
    /// before any data arrives.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No sentences yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for first translated sentence.")
    }

    // MARK: - Return arrow

    /// Unified "scroll both to bottom" affordance. Visible whenever
    /// either column is scrolled up. Tap calls
    /// ``TranscriptSplitScreenViewModel/scrollBothToBottom()`` which
    /// emits both column scrolls inside one animation transaction.
    private var returnArrowButton: some View {
        Button {
            viewModel.scrollBothToBottom()
        } label: {
            Image(systemName: "arrow.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(10)
                .background(DesignSystem.Colors.returnArrowBackground, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

/// Single split-screen row: caption text with the timestamp flowing
/// **inline** as a trailing suffix after the caption's last wrapped line.
///
/// The timestamp is composed as part of the same wrapping paragraph via
/// styled-`Text` interpolation rather than living in its own trailing
/// column. A two-column `HStack` reserved a fixed timestamp column on the
/// right and squeezed long captions; flowing the timestamp inline lets the
/// caption use the full row width and drops the timestamp immediately
/// after the final line. The caption and timestamp are each built as a
/// `Text` value carrying its own `.font` / `.foregroundStyle`, then
/// interpolated into one outer `Text` (`Text("\(caption)  \(stamp)")`).
/// SwiftUI preserves each interpolated `Text` segment's styling, so the
/// two roles stay distinct inside a single wrapping paragraph (this
/// replaces the deprecated `Text + Text` concatenation operator; styling
/// lives on the inner segments, never on the outer Text):
///   - caption → ``DesignSystem/Typography/transcriptText`` (`.body`),
///     `.primary` (both JA/EN columns stay equal-weight — UI decision #1).
///   - timestamp → ``DesignSystem/Typography/metadataText`` (SF Mono) in
///     ``DesignSystem/Colors/metadataForeground`` (the generalised
///     metadata role token — D6 convergence; see below).
///
/// The separator is two spaces (`"  "`). The Japanese column's text has no
/// inter-word spaces, so a visible gap between the CJK caption and the
/// monospaced timestamp matters; two spaces render a clear break in both
/// columns without reserving layout the inline flow is meant to avoid.
///
/// **D6 token convergence.** This row previously tinted the timestamp with
/// ``DesignSystem/Colors/timestampForeground``; it now uses
/// ``DesignSystem/Colors/metadataForeground``. Both resolve to
/// `UIColor.tertiaryLabel`, so this is a role-name convergence, not a
/// visual change — the per-row timestamp is metadata, and
/// `metadataForeground` is the canonical metadata-role token (Phase 7
/// Decision 5). `timestampForeground` is left defined for now (it has no
/// other production view consumer after this change) rather than deleted —
/// see the convergence note on ``DesignSystem``.
///
/// `private` because the row's shape is implementation detail of the
/// split-screen view. Tests assert through the formatter's `RowDisplay`
/// (which the row consumes verbatim).
private struct SplitScreenRow: View {
    let display: RowDisplay

    var body: some View {
        // Compose the caption + inline timestamp via styled-Text
        // interpolation (Apple-sanctioned; replaces the deprecated
        // Text + Text operator). Each segment is wrapped in `Text`
        // BEFORE interpolation so it enters the outer Text as a styled
        // Text value (preserving its own font/foregroundStyle) rather
        // than as a raw String subject to format-specifier
        // reinterpretation. Styling stays on the inner Text values —
        // outer modifiers would restyle the whole row.
        let caption = Text(display.text)
            .font(DesignSystem.Typography.transcriptText)
            .foregroundStyle(.primary)
        let stamp = Text(display.timestamp)
            .font(DesignSystem.Typography.metadataText)
            .foregroundStyle(DesignSystem.Colors.metadataForeground)
        return Text("\(caption)  \(stamp)")
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(display.text). \(display.timestamp).")
    }
}

#if DEBUG
    /// Preview fixture for ``TranscriptSplitScreenView``. `PersistentIdentifier`
    /// has no public initializer, so the sample
    /// ``MeetingDetail/SentenceProjection`` values are minted from real
    /// `Sentence` rows inserted into a throwaway in-memory container (distinct
    /// per-row identifiers, so `ForEach(id:)` renders every row). Lines mix
    /// `ja`- and `en`-source so both columns show original-vs-translation
    /// content. Verification aid for the Phase 7 token-align — the split-screen
    /// had no preview previously. (Does NOT touch the `TranscriptLiveView`
    /// `PopulatedPreviewWrapper`; V3 #40 concern 6 stays open.)
    @MainActor
    private enum TranscriptSplitScreenPreviewFixture {
        static func make() -> [MeetingDetail.SentenceProjection]? {
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: Meeting.self, Sentence.self,
                    configurations: config
                )
                let context = ModelContext(container)
                let started = Date(timeIntervalSince1970: 1_700_000_000)
                let meeting = Meeting(startedAt: started, title: "Live preview")
                context.insert(meeting)

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

                return inserted.map { s in
                    MeetingDetail.SentenceProjection(
                        id: s.persistentModelID,
                        timestamp: s.timestamp,
                        sourceLanguage: s.sourceLanguage,
                        sourceText: s.sourceText,
                        translatedText: s.translatedText,
                        sourceSegmentID: s.sourceSegmentID
                    )
                }
            } catch {
                return nil
            }
        }
    }

    #Preview("Split-screen — light") {
        if let sentences = TranscriptSplitScreenPreviewFixture.make() {
            TranscriptSplitScreenView(
                viewModel: TranscriptSplitScreenViewModel(fetcher: { sentences })
            )
            .preferredColorScheme(.light)
        } else {
            Text("Preview fixture unavailable")
        }
    }

    #Preview("Split-screen — dark") {
        if let sentences = TranscriptSplitScreenPreviewFixture.make() {
            TranscriptSplitScreenView(
                viewModel: TranscriptSplitScreenViewModel(fetcher: { sentences })
            )
            .preferredColorScheme(.dark)
        } else {
            Text("Preview fixture unavailable")
        }
    }
#endif
