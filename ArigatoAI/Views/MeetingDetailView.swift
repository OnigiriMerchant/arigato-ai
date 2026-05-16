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
/// - **#13** — full transcript displayed as a `List` of `(Japanese,
///   English, timestamp)` rows, oldest-first.
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
/// Stock SwiftUI: system fonts (UI decision #18), semantic colors (UI
/// decision #17). The empty state mirrors ``MeetingListView``'s
/// visual rhythm: SF Symbol + headline + subheadline, vertically
/// centered.
@MainActor
struct MeetingDetailView: View {
    /// The summary handed in as the `NavigationLink` value. Header
    /// renders from these fields with no extra fetch.
    let summary: MeetingSummary

    /// Backing view model — owns the reload pipeline and the
    /// sentences/loadError/refreshTrigger slice of state. Held as
    /// `@State` so SwiftUI retains it across re-renders.
    @State private var model: MeetingDetailViewModel

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
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.refreshTrigger) {
            await model.reload()
        }
        .toolbar {
            // MARK: - Step 13 — ShareLink lands here (UI #9 Context B)
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

    /// Main transcript list. Each row shows the Japanese text, the
    /// English text, and the per-sentence `HH:mm:ss` timestamp. Rows
    /// are read-only per UI decision #14.
    private var sentenceList: some View {
        List {
            ForEach(model.sentences, id: \.id) { sentence in
                let body = MeetingDetailFormatter.sentenceBody(for: sentence)
                VStack(alignment: .leading, spacing: 4) {
                    Text(body.japanese)
                        .font(.body)
                    Text(body.english)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(body.timestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
