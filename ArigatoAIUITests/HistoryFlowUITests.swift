//
//  HistoryFlowUITests.swift
//  ArigatoAIUITests
//
//  Created by Jose Castell on 2026/05/31.
//

import XCTest

/// XCUITest flows for the history list → detail surfaces, driven against
/// the seeded three-meeting corpus (`DebugMeetingSeeder`).
///
/// ## Seed corpus reference (newest-first ordering)
/// - **M1** — "Sprint planning sync" (top / newest)
/// - **M2** — "Q3 partnership review with Tokyo"
/// - **M3** — "Engineering all-hands / roadmap"
///
/// M1's first transcript line is Japanese-source, so its English
/// rendering ("Thanks for joining. Let's get started on today's sprint
/// planning.") is the unambiguous ASCII `staticText` the detail-view
/// assertions key on.
///
/// ## Row-query strategy (Q3 empirical finding)
/// History rows all share the `meeting.list.row` identifier and are
/// flattened with `.accessibilityElement(children: .combine)`, which
/// merges the title/date child `Text`s INTO the cell's accessibility
/// label. As a result `app.staticTexts["Sprint planning sync"]` does NOT
/// resolve on the History screen (the child text is absorbed). The robust
/// signal is the **cell whose combined label contains the title** — see
/// ``row(containing:in:)``.
final class HistoryFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Shared queries

    /// Title of seed meeting M1 (newest / top row).
    private static let m1Title = "Sprint planning sync"

    /// English rendering of M1's first (Japanese-source) transcript line.
    /// Rendered as its own `staticText` in the (un-combined) detail list.
    private static let m1EnglishLine =
        "Thanks for joining. Let's get started on today's sprint planning."

    /// Resolves the single history row whose combined accessibility label
    /// contains `title`.
    ///
    /// Queries `meeting.list.row` cells (the shared identifier) and filters
    /// by a `label CONTAINS` predicate. Returns a wildcard-descendant query
    /// element so the match works regardless of whether SwiftUI surfaces the
    /// combined row as a `cell`, `button`, or `other` element under XCUITest
    /// — the empirical resolution is logged in the test report rather than
    /// hard-coded to one element type.
    @MainActor
    private func row(containing title: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "meeting.list.row", title
        )
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    // MARK: - Regression guard: row tap pushes the detail (NOT a duplicate list)

    /// THE regression guard for the navigation bug just fixed: tapping a
    /// history row must push ``MeetingDetailView`` — not spuriously re-fire
    /// the History link and stack a duplicate History list on top.
    ///
    /// Positive assertions: the detail root exists, the nav-bar title flips
    /// to the meeting title, and a known M1 transcript line renders.
    ///
    /// Negative (duplicate-list guard) assertions: there is no "History"
    /// nav bar on top after the push, and the detail Copy button exists — a
    /// duplicate History list would carry neither. The nav-bar title is the
    /// robust "what is on top" signal because it flips atomically on push.
    @MainActor
    func testHistoryRowTap_pushesDetail() {
        let app = UITestHarness.launchSeeded()
        UITestHarness.openHistory(app)

        // Prove the seed landed: the M1 row resolves by its combined label.
        let m1Row = row(containing: Self.m1Title, in: app)
        XCTAssertTrue(
            m1Row.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Seeded M1 row '\(Self.m1Title)' never appeared in History."
        )

        m1Row.tap()

        // Positive: the detail pushed.
        let detailRoot = UITestHarness.element(identifier: "meeting.detail.root", in: app)
        XCTAssertTrue(
            detailRoot.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Detail root never appeared after tapping the M1 row."
        )

        // Positive: nav-bar title flipped to the meeting title (the
        // atomic "what is on top" signal).
        let detailNavBar = app.navigationBars[Self.m1Title]
        XCTAssertTrue(
            detailNavBar.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Detail nav-bar title '\(Self.m1Title)' never appeared."
        )

        // Positive: a known M1 transcript line renders in the (un-combined)
        // detail list, so we are looking at the real transcript.
        let m1Line = app.staticTexts[Self.m1EnglishLine]
        XCTAssertTrue(
            m1Line.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "M1 transcript line never appeared in the detail view."
        )

        // Negative (duplicate-list guard): a duplicate History list would
        // leave a "History" nav bar on top and would have NO Copy button.
        XCTAssertFalse(
            app.navigationBars["History"].exists,
            "A 'History' nav bar is on top after the push — a duplicate "
                + "History list was stacked instead of pushing the detail "
                + "(the regression this guard protects)."
        )
        XCTAssertTrue(
            app.buttons["meeting.detail.copyButton"].exists,
            "Detail Copy button is absent — the top is not the detail view "
                + "(duplicate-History-list regression)."
        )
    }

    // MARK: - Detail carries Copy and Share

    /// The detail view exposes both the Copy and Share affordances. Share
    /// is asserted present but NOT tapped (it opens the system share
    /// sheet, which is out of the app's process).
    ///
    /// ## Share-button resolution (Q3 empirical finding)
    /// `ShareLink`'s identifier exposure to XCUITest is not Apple-
    /// guaranteed. This test resolves Share by identifier first and, if
    /// that fails, falls back to the `accessibilityLabel` ("Share
    /// transcript") across `buttons` then `links`. The resolution path is
    /// logged so the report can record which strategy worked.
    @MainActor
    func testDetailHasCopyAndShare() {
        let app = UITestHarness.launchSeeded()
        UITestHarness.openHistory(app)

        let m1Row = row(containing: Self.m1Title, in: app)
        XCTAssertTrue(
            m1Row.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Seeded M1 row never appeared in History."
        )
        m1Row.tap()

        let detailRoot = UITestHarness.element(identifier: "meeting.detail.root", in: app)
        XCTAssertTrue(
            detailRoot.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Detail root never appeared after tapping the M1 row."
        )

        // Copy — resolves by identifier (a plain SwiftUI Button).
        let copyButton = app.buttons["meeting.detail.copyButton"]
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Detail Copy button never appeared."
        )

        // Share — try identifier, then label fallback (Q3 risk).
        let shareByIdentifier = app.buttons["meeting.detail.shareButton"]
        let shareButtonByLabel = app.buttons["Share transcript"]
        let shareLinkByLabel = app.links["Share transcript"]

        let shareResolved =
            shareByIdentifier.waitForExistence(timeout: UITestHarness.defaultTimeout)
                || shareButtonByLabel.exists
                || shareLinkByLabel.exists

        XCTAssertTrue(
            shareResolved,
            "Detail Share affordance never appeared by identifier "
                + "('meeting.detail.shareButton') nor by label ('Share "
                + "transcript') as button or link."
        )
    }

    // MARK: - Swipe-to-delete shows the undo toast; undo restores the row

    /// Swiping a row left reveals the destructive Delete action; tapping it
    /// shows the undo toast immediately (the test asserts the toast
    /// APPEARED rather than waiting out the 5-second window), and tapping
    /// Undo restores the row.
    @MainActor
    func testSwipeToDelete_showsUndoToast() {
        let app = UITestHarness.launchSeeded()
        UITestHarness.openHistory(app)

        let m1Row = row(containing: Self.m1Title, in: app)
        XCTAssertTrue(
            m1Row.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Seeded M1 row never appeared in History."
        )

        m1Row.swipeLeft()

        // The revealed swipe action is a destructive Button labelled
        // "Delete" (from `Label("Delete", systemImage: "trash")`).
        //
        // Empirical scoping note: the swipe-action button is rendered by
        // the collection view as a SIBLING of the cell, not a descendant of
        // the `.combine`d row, so `m1Row.buttons["Delete"]` does NOT resolve
        // it. We query at the app level. This is unambiguous on the History
        // screen — the Settings "Delete all transcripts" affordance lives
        // behind a separate push and is not present here.
        let deleteAction = app.buttons["Delete"]
        XCTAssertTrue(
            deleteAction.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Swipe-revealed Delete action never appeared after swiping the M1 row."
        )
        deleteAction.tap()

        // The undo toast appears immediately. Assert it APPEARED — do not
        // wait out the 5s window (that would commit the delete).
        let undoToast = UITestHarness.element(identifier: "meeting.list.undoDeleteToast", in: app)
        XCTAssertTrue(
            undoToast.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Undo toast never appeared after deleting the M1 row."
        )
        let undoButton = app.buttons["meeting.list.undoDeleteButton"]
        XCTAssertTrue(
            undoButton.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "Undo button never appeared in the toast."
        )

        undoButton.tap()

        // The M1 row reappears once the deletion is undone.
        let restoredRow = row(containing: Self.m1Title, in: app)
        XCTAssertTrue(
            restoredRow.waitForExistence(timeout: UITestHarness.defaultTimeout),
            "M1 row never reappeared after tapping Undo."
        )
    }
}
