//
//  UITestLaunchConfig.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/31.
//

#if DEBUG
    import Foundation

    /// DEBUG-only launch-argument reader for the XCUITest harness.
    ///
    /// The UI-test target launches the app with presence-based launch
    /// arguments (e.g. `app.launchArguments += ["-uiTestInMemoryStore"]`)
    /// rather than `UserDefaults`-style `-key value` pairs, so a flag is
    /// "set" purely by being present in `ProcessInfo.processInfo.arguments`.
    /// This namespace centralises the exact flag strings so the production
    /// wiring (``ArigatoAIApp/init()`` and
    /// ``AppBootstrapper/debugSeedSampleDataIfRequested()``) and the
    /// XCUITest driver agree on a single source of truth.
    ///
    /// > Important: Every value here is read from
    /// `ProcessInfo.processInfo.arguments` **at launch** (more precisely,
    /// at first access — which production code performs during
    /// ``ArigatoAIApp/init()``, before any window is shown). The launch
    /// arguments are fixed for the lifetime of the process, so the reads
    /// are effectively immutable after launch.
    ///
    /// This entire type is compiled **only** under `#if DEBUG`; Release
    /// builds contain zero references to it.
    ///
    /// ## Isolation
    /// `nonisolated` (a pure value namespace). The computed properties are
    /// stateless reads of `ProcessInfo` and touch no main-actor state, so
    /// they are callable from any execution context.
    nonisolated enum UITestLaunchConfig {
        /// `true` when the app was launched with the
        /// `-uiTestInMemoryStore` argument present.
        ///
        /// When set, ``ArigatoAIApp/init()`` builds its ``ModelContainer``
        /// with `isStoredInMemoryOnly: true` so each UI-test run starts
        /// from an empty, ephemeral store that leaves no on-disk artifacts
        /// and never collides with a developer's real recordings.
        ///
        /// Read from `ProcessInfo.processInfo.arguments` at launch.
        static var isInMemoryStoreRequested: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestInMemoryStore")
        }

        /// `true` when the app was launched with the `-uiTestSeed`
        /// argument present.
        ///
        /// When set, ``AppBootstrapper/debugSeedSampleDataIfRequested()``
        /// fills the (typically in-memory) store with
        /// ``DebugMeetingSeeder``'s three-meeting corpus once the store
        /// publishes, so the history / detail / search / export surfaces
        /// have representative data for the UI test to assert against.
        ///
        /// Read from `ProcessInfo.processInfo.arguments` at launch.
        static var isSeedRequested: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestSeed")
        }
    }
#endif
