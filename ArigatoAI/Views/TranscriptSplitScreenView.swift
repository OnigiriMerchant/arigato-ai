//
//  TranscriptSplitScreenView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

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
/// ## Styling
///
/// Per-row timestamps render in
/// ``DesignSystem/Colors/timestampForeground`` (Step 9b token). The
/// return-arrow background uses
/// ``DesignSystem/Colors/returnArrowBackground``. Body text uses
/// stock SwiftUI semantic colors so the JA/EN columns adapt to dark
/// mode without ceremony (UI decisions #17 + #18 — system fonts handle
/// CJK fallback automatically).
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
            rowFor: TranscriptSplitScreenFormatter.japaneseRow(for:),
            scrollPosition: $viewModel.jaPosition,
            isAtBottom: { self.viewModel.jaAtBottom },
            atBottomChanged: viewModel.setJaAtBottom(_:)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Bottom half — English rows. Mirrors ``japaneseColumn`` with the
    /// English-side projection + binding.
    private var englishColumn: some View {
        column(
            rowFor: TranscriptSplitScreenFormatter.englishRow(for:),
            scrollPosition: $viewModel.enPosition,
            isAtBottom: { self.viewModel.enAtBottom },
            atBottomChanged: viewModel.setEnAtBottom(_:)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shared column builder.
    ///
    /// - Parameters:
    ///   - rowFor: Projection from a `SentenceProjection` to its
    ///     ``RowDisplay`` for this column (JA or EN).
    ///   - scrollPosition: The column-specific `ScrollPosition` binding
    ///     into the view model.
    ///   - isAtBottom: Closure returning the column's current at-bottom
    ///     flag. Closure rather than value so it re-reads on every
    ///     `.onChange` invocation (the flag may have been updated by
    ///     the geometry callback between renders).
    ///   - atBottomChanged: Setter the geometry callback drives whenever
    ///     the column's bottom-edge predicate flips.
    @ViewBuilder
    private func column(
        rowFor: @escaping (MeetingDetail.SentenceProjection) -> RowDisplay,
        scrollPosition: Binding<ScrollPosition>,
        isAtBottom: @escaping () -> Bool,
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
                // content's lower edge.
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - geometry.contentInsets.bottom
            } action: { _, atBottom in
                atBottomChanged(atBottom)
            }
            .onChange(of: viewModel.sentences) { _, _ in
                // Auto-follow per UI #2: when the column is at the
                // bottom and new content arrives, scroll-to-bottom in
                // a short animation. When scrolled up, leave position
                // alone (stay-put). Each column reads its own flag so
                // a JA-scrolled-up + EN-at-bottom user sees only the
                // EN column auto-follow.
                if isAtBottom() {
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

/// Single split-screen row: text on the left, timestamp on the right.
///
/// `private` because the row's shape is implementation detail of the
/// split-screen view. Tests assert through the formatter's `RowDisplay`
/// (which the row consumes verbatim).
private struct SplitScreenRow: View {
    let display: RowDisplay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(display.text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(display.timestamp)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(DesignSystem.Colors.timestampForeground)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(display.text). \(display.timestamp).")
    }
}
