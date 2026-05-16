//
//  TranscriptSplitScreenViewTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import SwiftUI
import Testing

/// View-level behavioural tests for ``TranscriptSplitScreenView``.
///
/// ViewInspector is not a project dependency, so the view's body cannot be
/// asserted against directly. Per the Phase-2 trio precedent established
/// by ``MeetingListViewTests`` (Step 6) and ``MeetingControlsViewTests``
/// (Step 7), this file is intentionally thin — most coverage lives in the
/// view-model and formatter tests, both of which exercise the actual
/// branch logic the view body consumes.
///
/// What this file CAN test cheaply:
///   - The view-model state combinations that gate the view's three
///     mutually-exclusive branches (empty-state placeholder, populated
///     columns, return-arrow overlay).
///   - The view's init shape (host can pass either a `disabled()`-style
///     placeholder VM or a real one).
///
/// What this file CANNOT test without ViewInspector:
///   - That `.scrollPosition($viewModel.jaPosition)` is wired to the JA
///     ScrollView (verified by the production code's compile-time bind).
///   - That `.onScrollGeometryChange` fires the expected predicate.
///   - That the `withAnimation` block in `scrollBothToBottom()` produces
///     a single animation transaction (V3-deferred per the named test's
///     pre-authorized STOP — see `TranscriptSplitScreenViewModelTests`).
///   - That live-streaming partial chunks render in real time
///     (Step 9a does NOT integrate `liveChunks` display in the view —
///     the split-screen view reads `viewModel.sentences` exclusively;
///     V3 entry filed for "Live-chunk streaming display deferred").
@Suite("TranscriptSplitScreenView")
@MainActor
struct TranscriptSplitScreenViewTests {
    // MARK: - 1. Empty-state branch

    /// **D9a-T-view-1** — When the VM's ``TranscriptSplitScreenViewModel/sentences``
    /// array is empty, the view body's empty-state branch is the branch
    /// SwiftUI will pick. This test asserts the state condition; the
    /// SwiftUI view body's `if viewModel.sentences.isEmpty { emptyState
    /// } else { ScrollView ... }` branch directly mirrors the assertion.
    @Test func view_emptyState_rendersWhenNoSentences() async {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })
        await vm.reload()

        // The empty-state branch is the one the view body picks; we
        // assert the state predicate that drives the branch.
        #expect(vm.sentences.isEmpty)
        #expect(vm.loadError == nil)

        // Constructing the view must succeed with the empty VM (no
        // crash, no assertion). ViewInspector would let us assert the
        // rendered body; without it, "constructs cleanly" is the
        // testable contract.
        let view = TranscriptSplitScreenView(viewModel: vm)
        _ = view.body
    }

    // MARK: - 2. Return-arrow overlay gating

    /// **D9a-T-view-2** — The view body's
    /// `.overlay(alignment: .bottomTrailing)` gates the return-arrow
    /// button on ``TranscriptSplitScreenViewModel/arrowVisible``. The
    /// arrow appears iff the VM reports `arrowVisible == true`, which
    /// is true iff `!jaAtBottom || !enAtBottom`. We assert the gate's
    /// state composition matches the UI #2 contract.
    @Test func view_arrowOverlay_visibleWhenViewModelArrowVisibleIsTrue() {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })

        // Default state: both columns at bottom → arrow hidden.
        #expect(vm.arrowVisible == false)

        // Scroll one column up → arrow visible.
        vm.setJaAtBottom(false)
        #expect(vm.arrowVisible == true)

        // Both back at bottom → arrow hidden again.
        vm.setJaAtBottom(true)
        vm.setEnAtBottom(true)
        #expect(vm.arrowVisible == false)

        // Constructing the view across the gate transitions must
        // succeed without crash.
        let view = TranscriptSplitScreenView(viewModel: vm)
        _ = view.body
    }
}

// NOTE on test #15 disposition: The original brief enumerated
// `view_streamingPartialChunk_appearsInColumnImmediately` as a candidate
// view test. Step 9a's production work does NOT integrate `liveChunks`
// streaming display in the split-screen view — `TranscriptSplitScreenView`
// reads `viewModel.sentences` exclusively, which only contains persisted
// `.completed` sentences (per the D3-A option 2 contract). Live-token
// streaming display in the JA / EN columns would require an additional
// VM field that mirrors `MeetingSession.liveChunks` and an additional
// view-body branch. That work is V3-deferred ("Live-chunk streaming
// display in split-screen view — deferred from Step 9a"). Test #15 is
// therefore not implemented in this file; the V3 entry is filed in the
// docs commit.
