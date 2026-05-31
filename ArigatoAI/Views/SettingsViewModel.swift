//
//  SettingsViewModel.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation

/// Observable view-model for ``SettingsView`` (UI #19).
///
/// Owns the small slice of state SwiftUI binds to: the latest
/// ``StorageStats`` snapshot, an in-flight load/load-error pair, a
/// pending destructive ``PendingAction``, two per-action busy flags,
/// and the last action's result for surfacing inline.
///
/// ## Scheduling assumption — re-entry guard
///
/// ``confirmPending(_:)`` is **re-entry guarded**. If a clear-cache or
/// delete-all call is already in flight (`isClearingCache ||
/// isDeletingAll`), a subsequent invocation is a no-op. The action is
/// captured **synchronously at the dialog button tap** and passed in,
/// rather than read from ``pending`` — SwiftUI dismisses the
/// confirmation dialog by flipping the `isPresented` binding, whose
/// setter synchronously runs ``cancelPending()`` (`pending = nil`)
/// BEFORE the button's deferred `Task` runs `confirmPending`. Reading
/// `pending` inside the method would therefore observe `nil` and
/// no-op. Passing the snapshot in side-steps that dismiss-cancel race.
///
/// SwiftUI's confirmation-dialog button cannot in practice produce
/// concurrent taps, but a test-driven race that calls
/// `confirmPending(_:)` twice from independent tasks must observe
/// exactly one downstream call (one `clearPromptCache` on the provider
/// OR one `deleteAllMeetings` on the store). The re-entry safety now
/// rests on the busy-flag guard (`isClearingCache || isDeletingAll`,
/// checked as the first line) combined with `@MainActor` serialization
/// — `performClearCache`/`performDeleteAll` set their busy flag with no
/// intervening `await`, so a second `@MainActor` invocation that runs
/// before the first suspends still observes the flag set. Named
/// violation test: ``confirmPending_whileInFlight_isNoOp`` — spawns two
/// concurrent `confirmPending(.clearCache)` calls against a fake
/// provider whose `clearPromptCache` blocks until externally signaled,
/// and asserts the provider observed exactly one invocation.
///
/// ## Scheduling assumption — stats reload sequencing
///
/// After a successful destructive op, ``confirmPending(_:)`` calls
/// ``load()`` to refresh ``stats``. APFS metadata-cache lag may cause
/// the immediately-subsequent ``StorageStatsProviding/currentStats()``
/// to report non-zero `lfm2CacheBytes` for a few hundred milliseconds
/// after a cache clear; the next refresh (or any subsequent settings
/// open) will reflect the deletion. No named violation test — FS
/// metadata lag is not testably observable from Swift Testing under
/// the project's harness.
@MainActor
@Observable
final class SettingsViewModel {
    /// Pending destructive action awaiting user confirmation.
    ///
    /// Two cases match the two confirmation dialogs in ``SettingsView``.
    /// `Equatable` + `Sendable` so SwiftUI's `confirmationDialog` can
    /// drive a `Binding` against it.
    enum PendingAction: Equatable {
        case clearCache
        case deleteAll
    }

    /// Result of the most recent destructive action. Surfaced inline
    /// so the user receives feedback after dialog dismissal.
    ///
    /// `Equatable` + `Sendable` for Swift Testing assertion ergonomics.
    enum ActionResult: Equatable {
        /// Successful cache clear; carries the number of bytes
        /// reclaimed (pre-clear ``StorageStats/lfm2CacheBytes``).
        case cleared(reclaimedBytes: Int64)

        /// Successful transcript delete; carries the count returned
        /// by ``MeetingStore/deleteAllMeetings()``.
        case deleted(count: Int)

        /// Either action failed. Carries the failure's
        /// `localizedDescription` so the UI can render it.
        case failure(message: String)
    }

    /// Latest stats snapshot. `nil` while loading or after a failed load.
    private(set) var stats: StorageStats?

    /// Last load error, `nil` on success.
    private(set) var loadError: Error?

    /// Pending destructive action — drives the two confirmation
    /// dialogs in ``SettingsView``. Mutated by ``requestClearCache()``,
    /// ``requestDeleteAll()``, and ``cancelPending()``. The view reads
    /// this synchronously at the destructive button's tap to capture the
    /// action to hand to ``confirmPending(_:)`` (the dialog dismissal
    /// clears it via ``cancelPending()`` before the deferred confirm
    /// `Task` runs).
    private(set) var pending: PendingAction?

    /// `true` while a clear-cache call is in flight. Re-entry guard
    /// on ``confirmPending(_:)`` consults this + ``isDeletingAll``.
    private(set) var isClearingCache: Bool = false

    /// `true` while a delete-all-transcripts call is in flight.
    private(set) var isDeletingAll: Bool = false

    /// Most recent destructive-action result. Cleared lazily — the
    /// next `requestX` cycle does not reset it so the inline feedback
    /// can persist until the user acts again.
    private(set) var lastActionResult: ActionResult?

    private let statsProvider: any StorageStatsProviding
    private let meetingStore: MeetingStore

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - statsProvider: The provider injected from ``AppBootstrapper``
    ///     (production) or a fake (tests). Production: a
    ///     ``FileManagerStorageStatsProvider``.
    ///   - meetingStore: The actor-backed persistence used by
    ///     ``confirmPending(_:)`` for the delete-all path. Same actor the
    ///     stats provider reads transcript count from per D15-3.
    init(statsProvider: any StorageStatsProviding, meetingStore: MeetingStore) {
        self.statsProvider = statsProvider
        self.meetingStore = meetingStore
    }

    /// Pulls a fresh ``StorageStats`` from the provider. Errors are
    /// stored in ``loadError`` rather than thrown — SwiftUI views
    /// cannot throw, and the contract routes failures through the
    /// observable error state.
    ///
    /// On success: ``stats`` is updated and ``loadError`` is cleared.
    /// On failure: ``stats`` is left unchanged (so a transient error
    /// during a refresh after a destructive op does not erase the
    /// pre-refresh figure) and ``loadError`` is set.
    func load() async {
        do {
            let next = try await statsProvider.currentStats()
            stats = next
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// Sets ``pending`` to ``PendingAction/clearCache`` so the
    /// view's confirmation dialog presents. No-op when another
    /// destructive op is already in flight.
    func requestClearCache() {
        guard !isClearingCache, !isDeletingAll else { return }
        pending = .clearCache
    }

    /// Sets ``pending`` to ``PendingAction/deleteAll``. Same gating
    /// as ``requestClearCache()``.
    func requestDeleteAll() {
        guard !isClearingCache, !isDeletingAll else { return }
        pending = .deleteAll
    }

    /// Clears ``pending``. Bound to both dialogs' Cancel buttons.
    /// Idempotent.
    func cancelPending() {
        pending = nil
    }

    /// Executes the supplied destructive action.
    ///
    /// - Parameter action: The action to perform, captured
    ///   **synchronously at the dialog button tap** by ``SettingsView``
    ///   and passed in. It is NOT read from ``pending`` because SwiftUI
    ///   dismisses the confirmation dialog by flipping the `isPresented`
    ///   binding, whose setter synchronously runs ``cancelPending()``
    ///   (`pending = nil`) BEFORE this method's deferred `Task` runs.
    ///   Reading `pending` here would therefore observe `nil` and no-op;
    ///   passing the snapshot in side-steps that dismiss-cancel race.
    ///
    /// **Re-entry guard.** No-op when any destructive op is already in
    /// flight (`isClearingCache || isDeletingAll`). This busy-flag check
    /// is the FIRST line; combined with `@MainActor` serialization and
    /// the fact that `performClearCache`/`performDeleteAll` set their
    /// busy flag with no intervening `await`, a second `@MainActor`
    /// invocation that runs before the first suspends still observes the
    /// flag set and short-circuits. Named violation test:
    /// ``confirmPending_whileInFlight_isNoOp``.
    ///
    /// **Reload after success.** Calls ``load()`` so the UI reflects
    /// the post-op state. APFS metadata-cache lag (documented on the
    /// type's scheduling-assumption section) may make the immediate
    /// reload still show non-zero cache bytes; the next user-initiated
    /// refresh clears the residual.
    ///
    /// **Failure surface.** A throwing provider/store call populates
    /// ``lastActionResult`` with `.failure(message:)` and leaves
    /// ``stats`` intact (subsequent `load()` runs unconditionally).
    func confirmPending(_ action: PendingAction) async {
        // Re-entry guard: ignore concurrent invocations. Must stay the
        // first line — it is the sole re-entry defense now that the
        // action no longer comes from `pending`.
        guard !isClearingCache, !isDeletingAll else { return }
        // Defensively clear any lingering pending value (idempotent —
        // the dialog dismiss already cleared it via cancelPending()).
        pending = nil

        switch action {
        case .clearCache:
            await performClearCache()
        case .deleteAll:
            await performDeleteAll()
        }
    }

    private func performClearCache() async {
        isClearingCache = true
        defer { isClearingCache = false }
        let preBytes = stats?.lfm2CacheBytes ?? 0
        do {
            try await statsProvider.clearPromptCache()
            lastActionResult = .cleared(reclaimedBytes: preBytes)
        } catch {
            lastActionResult = .failure(message: error.localizedDescription)
        }
        await load()
    }

    private func performDeleteAll() async {
        isDeletingAll = true
        defer { isDeletingAll = false }
        do {
            let count = try await meetingStore.deleteAllMeetings()
            lastActionResult = .deleted(count: count)
        } catch {
            lastActionResult = .failure(message: error.localizedDescription)
        }
        await load()
    }

    #if DEBUG
        /// `true` while a developer-tool seed is in flight. Re-entry guard for
        /// ``seedSampleData()`` and a disable signal for the DEBUG "Developer"
        /// section buttons in ``SettingsView``.
        ///
        /// DEBUG-only — the entire developer-seeding surface (this flag plus
        /// ``seedSampleData()`` and ``clearAllData()``) is compiled out of
        /// Release builds, alongside ``DebugMeetingSeeder`` itself.
        private(set) var isSeeding: Bool = false

        /// Seeds the simulator store with ``DebugMeetingSeeder``'s sample
        /// meetings so the history list / detail view / copy-share-export /
        /// swipe-to-delete can be evaluated against realistic JA↔EN data.
        ///
        /// **Re-entry guarded** on ``isSeeding`` (set true on entry, reset via
        /// `defer`) so a stray double-tap cannot drive two overlapping seeds.
        /// This is the serialization ``DebugMeetingSeeder/seed(into:)``
        /// documents it requires; the Settings buttons are additionally
        /// `.disabled` while any busy flag is set. Kept fully separate from
        /// the production ``PendingAction`` / ``confirmPending(_:)`` path — this
        /// is throwaway dev tooling, not a user-facing destructive action.
        ///
        /// Seeding is intentionally **not** idempotent: repeat invocations
        /// stack data rather than clearing first, so a real recording is never
        /// destroyed. Use ``clearAllData()`` to reset.
        ///
        /// Failures surface through ``lastActionResult`` as `.failure(message:)`
        /// (matching the production destructive-op idiom); on completion the
        /// transcript-count stat is refreshed via ``load()``.
        func seedSampleData() async {
            guard !isSeeding, !isClearingCache, !isDeletingAll else { return }
            isSeeding = true
            defer { isSeeding = false }
            do {
                try await DebugMeetingSeeder.seed(into: meetingStore)
            } catch {
                lastActionResult = .failure(message: error.localizedDescription)
            }
            await load()
        }

        /// Deletes **all** meetings (the DEBUG "Clear all sample data" button).
        ///
        /// Calls the existing ``MeetingStore/deleteAllMeetings()``. Note this
        /// removes *every* meeting, not only seeded ones — acceptable for
        /// throwaway dev tooling. Re-entry guarded on the same busy flags as
        /// ``seedSampleData()``; surfaces success as `.deleted(count:)` and
        /// failure as `.failure(message:)`, matching the production idiom, then
        /// refreshes the stat via ``load()``.
        func clearAllData() async {
            guard !isSeeding, !isClearingCache, !isDeletingAll else { return }
            isSeeding = true
            defer { isSeeding = false }
            do {
                let count = try await meetingStore.deleteAllMeetings()
                lastActionResult = .deleted(count: count)
            } catch {
                lastActionResult = .failure(message: error.localizedDescription)
            }
            await load()
        }
    #endif
}
