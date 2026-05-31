//
//  SettingsFlowUITests.swift
//  ArigatoAIUITests
//
//  Created by Jose Castell on 2026/05/31.
//

import XCTest

/// XCUITest flows for the Settings surface: seeding the corpus from the
/// DEBUG "Developer" section, and deleting all transcripts back to the
/// empty state.
///
/// Both flows navigate History → Settings (gear) → History via the
/// nav-bar back button. The seed/delete buttons live below the fold in a
/// `List` and are not present in the XCUITest hierarchy until scrolled
/// into view, so ``tapPossiblyOffscreen(_:_:)`` drives a bounded
/// `swipeUp()` loop that scrolls the control into existence-and-hittable
/// range before tapping (no fixed `sleep`).
final class SettingsFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Shared

    /// Title of seed meeting M1 — the presence/absence sentinel for both
    /// flows.
    private static let m1Title = "Sprint planning sync"

    /// Resolves the single history row whose combined accessibility label
    /// contains `title`. Mirrors `HistoryFlowUITests.row(containing:in:)`;
    /// duplicated rather than shared because the two test classes are
    /// independent and the helper is a one-liner.
    @MainActor
    private func row(containing title: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "meeting.list.row", title
        )
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Opens Settings from the History screen via the gear toolbar item and
    /// waits for the Settings nav bar.
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let gear = app.buttons["settings.gear"]
        XCTAssertTrue(
            gear.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Settings gear never appeared in History."
        )
        gear.tap()

        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(
            settingsNavBar.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Settings nav bar never appeared after tapping the gear."
        )
    }

    /// Scrolls `element` into view, then taps it.
    ///
    /// ## Why a scroll loop, not a single `waitForExistence`
    /// The Settings `List` (a SwiftUI `List`, backed by `UICollectionView`)
    /// only materializes the cells currently near the viewport into the
    /// XCUITest accessibility hierarchy. The two controls this helper drives
    /// — `settings.storage.deleteAllButton` (last Storage row) and
    /// `settings.developer.seedButton` (first DEBUG Developer row) — sit
    /// **below the fold**: at the failing position in the full serial suite
    /// the snapshot shows only `BackButton` / "Project on GitHub" / "Clear
    /// cache" present, and the target reports `exists == false`. A single
    /// `waitForExistence` therefore times out *before any scroll happens* —
    /// the wait-before-scroll ordering is the bug this helper exists to fix.
    ///
    /// The loop instead checks existence-and-hittability each pass, swiping
    /// up to pull the next band of cells into the hierarchy, with a short
    /// per-iteration `waitForExistence` so each scroll settles without a
    /// fixed `sleep`. It is **bounded** (``scrollAttemptCap``): if the
    /// control is genuinely unreachable the loop exhausts and fails with a
    /// clear message instead of spinning forever.
    ///
    /// - Note: All caller assertions are preserved unchanged; this helper
    ///   only changes *how* the control is reached, never *whether* it must.
    @MainActor
    private func tapPossiblyOffscreen(_ app: XCUIApplication, _ element: XCUIElement) {
        // Fast path: already materialized and hittable (control above the
        // fold, or the prior scroll position already revealed it).
        if element.exists, element.isHittable {
            element.tap()
            return
        }

        // Scroll the List toward the control, re-checking each pass. The
        // per-iteration wait lets a just-triggered scroll settle and the
        // newly-materialized cell register in the hierarchy without a fixed
        // sleep; `swipeUp()` then pulls the next band into view.
        for _ in 0 ..< Self.scrollAttemptCap {
            if element.waitForExistence(timeout: Self.perScrollTimeout), element.isHittable {
                element.tap()
                return
            }
            app.swipeUp()
        }

        // One final check after the last swipe settled.
        if element.exists, element.isHittable {
            element.tap()
            return
        }

        XCTFail(
            "Expected control never became hittable in Settings after "
                + "\(Self.scrollAttemptCap) scroll attempts "
                + "(identifier: \(element.identifier.isEmpty ? "<none>" : element.identifier))."
        )
    }

    /// Maximum `swipeUp()` iterations ``tapPossiblyOffscreen(_:_:)`` will
    /// perform before failing. Six full-height swipes scroll well past the
    /// nine-row Settings `List`, so exhausting the cap means the control is
    /// genuinely unreachable — not merely slow to appear.
    private static let scrollAttemptCap = 6

    /// Short per-scroll existence wait inside ``tapPossiblyOffscreen(_:_:)``.
    /// Long enough for a settling scroll to materialize the next cell band,
    /// short enough that the bounded loop fails promptly when the control
    /// truly never appears.
    private static let perScrollTimeout: TimeInterval = 2

    /// Pops the current screen via the nav-bar back button.
    @MainActor
    private func tapBack(_ app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(
            backButton.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Nav-bar back button never appeared."
        )
        backButton.tap()
    }

    // MARK: - Seed from Settings populates History

    /// Launches WITHOUT a pre-seed, confirms History is empty, seeds via
    /// the Settings Developer section, pops back, and confirms the corpus
    /// now renders.
    @MainActor
    func testSeedFromSettings_populatesHistory() {
        let app = UITestHarness.launchSeeded(seed: false)
        UITestHarness.openHistory(app)

        // Empty store: the empty-state placeholder is present.
        let emptyState = UITestHarness.element(identifier: "meeting.list.emptyState", in: app)
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Empty-state placeholder never appeared in an unseeded History."
        )

        openSettings(app)

        let seedButton = app.buttons["settings.developer.seedButton"]
        tapPossiblyOffscreen(app, seedButton)

        tapBack(app)

        // History reload (the DEBUG `.onAppear` requestReload) surfaces the
        // freshly-seeded corpus.
        let m1Row = row(containing: Self.m1Title, in: app)
        XCTAssertTrue(
            m1Row.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Seeded M1 row never appeared in History after seeding from Settings."
        )
        let listRoot = UITestHarness.element(identifier: "meeting.list.root", in: app)
        XCTAssertTrue(
            listRoot.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Meeting-list root never appeared after seeding from Settings."
        )
    }

    // MARK: - Delete all returns History to empty

    /// Launches pre-seeded, confirms M1 is present, deletes all transcripts
    /// via Settings (confirming the destructive dialog), pops back, and
    /// confirms History is empty again.
    @MainActor
    func testDeleteAll_returnsHistoryToEmpty() {
        let app = UITestHarness.launchSeeded()
        UITestHarness.openHistory(app)

        let m1Row = row(containing: Self.m1Title, in: app)
        XCTAssertTrue(
            m1Row.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Seeded M1 row never appeared in History."
        )

        openSettings(app)

        let deleteAllButton = app.buttons["settings.storage.deleteAllButton"]
        tapPossiblyOffscreen(app, deleteAllButton)

        // The confirmation dialog's title text must be present before we
        // commit to the destructive action.
        let dialogTitle = app.staticTexts["Delete all transcripts?"]
        XCTAssertTrue(
            dialogTitle.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Delete-all confirmation dialog title never appeared."
        )

        // The system confirmation button is labelled "Delete".
        let confirmDelete = app.buttons["Delete"]
        XCTAssertTrue(
            confirmDelete.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Destructive 'Delete' button never appeared in the dialog."
        )
        confirmDelete.tap()

        // Synchronize on the delete actually landing before popping back.
        //
        // `confirmPending()` runs as a fire-and-forget `Task` off the dialog
        // button; the store delete + stats reload are async. The History
        // pop-back reload (the DEBUG `.onAppear { requestReload() }`) fires
        // ONCE on re-appearance and is not re-triggered when the async delete
        // later completes, so popping back before the delete lands would race
        // that single reload. We instead gate on the real user-visible
        // completion signal: the Settings "Transcripts" row updates to its
        // zero state via the row's `.task`-driven `load()` once the delete
        // commits. The element's combined accessibility label is
        // `"Transcripts, <count>"` (the `LabeledContent` label folds in), and
        // `SettingsFormatter.transcriptCountLabel(0)` is "No transcripts", so
        // the post-delete label is "Transcripts, No transcripts" — matched
        // here with a `CONTAINS "No transcripts"` predicate.
        let transcriptCount = UITestHarness.element(
            identifier: "settings.storage.transcriptCount", in: app
        )
        let countClearedPredicate = NSPredicate(
            format: "label CONTAINS %@", "No transcripts"
        )
        let countCleared = XCTNSPredicateExpectation(
            predicate: countClearedPredicate, object: transcriptCount
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [countCleared], timeout: UITestHarness.defaultTimeout),
            .completed,
            "Settings transcript count never reached its zero state after "
                + "confirming delete-all — the store delete did not commit."
        )

        tapBack(app)

        // History returns to the empty state, and the M1 title is gone.
        let emptyState = UITestHarness.element(identifier: "meeting.list.emptyState", in: app)
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Empty-state placeholder never appeared after deleting all transcripts."
        )

        let m1RowAfter = row(containing: Self.m1Title, in: app)
        XCTAssertTrue(
            m1RowAfter.waitForNonExistence(timeout: UITestHarness.defaultTimeout),
            "M1 row still present after deleting all transcripts."
        )
    }
}
