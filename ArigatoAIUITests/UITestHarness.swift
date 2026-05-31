//
//  UITestHarness.swift
//  ArigatoAIUITests
//
//  Created by Jose Castell on 2026/05/31.
//

import XCTest

/// Shared launch + navigation helpers for the Arigato AI XCUITest flows.
///
/// The UI-test target runs **out-of-process** and therefore cannot import
/// the app module: the launch-argument strings below are **duplicated
/// literals**, not references. They are the exact counterparts of the
/// app-side reader `UITestLaunchConfig` (in
/// `ArigatoAI/Debug/UITestLaunchConfig.swift`) plus the onboarding-skip
/// `UserDefaults` pair. If either of those changes, this file must be kept
/// in lock-step by hand.
///
/// ## Launch-argument contract (landed in Group A/B)
///
/// - `-uiTestInMemoryStore` — presence-based. Builds the `ModelContainer`
///   with `isStoredInMemoryOnly: true`, so each run starts from a fresh,
///   ephemeral store that never collides with a developer's real data.
/// - `-uiTestSeed` — presence-based. After the store publishes, the app
///   seeds `DebugMeetingSeeder`'s three-meeting corpus.
/// - `-hasCompletedOnboarding 1` — `UserDefaults` `-key value` form (TWO
///   array elements). Skips the onboarding gate so the harness lands
///   directly on the active-meeting root.
///
/// Seeded data is asynchronous (it lands after the store publishes), so
/// every assertion that depends on it **must** wait via
/// `waitForExistence(timeout:)` against ``Self/defaultTimeout`` — never a
/// fixed `sleep`.
enum UITestHarness {
    /// Presence-based flag (duplicated literal — see
    /// `UITestLaunchConfig.isInMemoryStoreRequested`). Requests a fresh
    /// in-memory `ModelContainer` for the run.
    static let inMemoryStoreArgument = "-uiTestInMemoryStore"

    /// Presence-based flag (duplicated literal — see
    /// `UITestLaunchConfig.isSeedRequested`). Requests the app seed the
    /// three-meeting corpus once the store publishes.
    static let seedArgument = "-uiTestSeed"

    /// `UserDefaults` override key that skips onboarding. Paired with
    /// ``onboardingSkipValue`` as TWO separate launch-argument elements.
    static let onboardingSkipKey = "-hasCompletedOnboarding"

    /// Value half of the onboarding-skip `UserDefaults` override.
    static let onboardingSkipValue = "1"

    /// Timeout for every seed-dependent / navigation-dependent wait. Seed
    /// inserts run sequentially against the `@ModelActor` store after the
    /// store publishes, so the corpus can take a few seconds to surface on
    /// a cold simulator. Generous enough to absorb that without flaking;
    /// short enough that a genuine failure still fails the run promptly.
    static let defaultTimeout: TimeInterval = 15

    /// Builds and launches the app configured for a UI-test flow.
    ///
    /// Always passes the onboarding-skip pair and `-uiTestInMemoryStore`
    /// so the run starts onboarding-free against a fresh ephemeral store.
    /// When `seed` is `true` (the default), also appends `-uiTestSeed` so
    /// the app populates the three-meeting corpus once the store
    /// publishes.
    ///
    /// - Parameter seed: Whether to request the seeded corpus. Pass
    ///   `false` for flows that must start from an empty store (e.g.
    ///   seeding from Settings, asserting the empty state first).
    /// - Returns: The launched ``XCUIApplication``.
    @MainActor
    static func launchSeeded(seed: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            onboardingSkipKey, onboardingSkipValue,
            inMemoryStoreArgument,
        ]
        if seed {
            app.launchArguments.append(seedArgument)
        }
        app.launch()
        return app
    }

    /// Taps the History toolbar button and waits for the meeting-list
    /// root to appear.
    ///
    /// - Parameters:
    ///   - app: The launched application.
    ///   - file/line: Forwarded so a wait failure points at the call site.
    @MainActor
    static func openHistory(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let historyButton = app.buttons["history.toolbarButton"]
        XCTAssertTrue(
            historyButton.waitForExistence(timeout: defaultTimeout),
            "History toolbar button never appeared.",
            file: file,
            line: line
        )
        historyButton.tap()

        // The History nav bar flips atomically on push — the most robust
        // "we are on the History screen" signal, independent of which
        // element type SwiftUI projects the `List` root as under XCUITest
        // (a SwiftUI `List` surfaces as a `collectionView`, not an
        // `otherElement`, so an identifier-only query against
        // `otherElements` does not resolve it).
        let historyNavBar = app.navigationBars["History"]
        XCTAssertTrue(
            historyNavBar.waitForExistence(timeout: defaultTimeout),
            "History screen never appeared after tapping History.",
            file: file,
            line: line
        )
    }

    /// Resolves a single element by accessibility `identifier` regardless
    /// of which XCUITest element type SwiftUI projects it as.
    ///
    /// SwiftUI container identifiers do not land on a fixed element type:
    /// a `List` carrying `.accessibilityIdentifier` surfaces as a
    /// `collectionView` (iOS 16+ `List` is backed by `UICollectionView`),
    /// while a `VStack` with `.accessibilityElement(children: .combine)`
    /// surfaces as an `other` element. Typed accessors
    /// (`app.otherElements[...]`, `app.collectionViews[...]`) only resolve
    /// when the guess matches. A wildcard-descendant query keyed on the
    /// identifier resolves the element whichever type it lands as — the
    /// project's standard container-resolution path for these flows.
    @MainActor
    static func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }
}
