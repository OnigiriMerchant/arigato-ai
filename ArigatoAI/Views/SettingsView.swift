//
//  SettingsView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import SwiftUI

/// Settings surface — UI #19's minimal two-section MVP-1 scope.
///
/// **About** (3 rows): version, fully-on-device privacy reassurance,
/// link to the project's GitHub page.
///
/// **Storage** (4 rows): LFM2 cache size, transcript count, "Clear
/// cache" destructive action (D15-1 — **prompt cache only**, NOT the
/// model file; clearing the model would brick translation until V3
/// `b851dad` portal fix lands), "Delete all transcripts" destructive
/// action.
///
/// Out of scope for this view per UI #19: diagnostic logs toggle,
/// default export format, retention policy, model selection,
/// re-onboarding affordance (V3-tracked under
/// "Re-onboarding from Settings"; deferred to Phase 7).
///
/// ## Navigation
/// Reachable from ``MeetingListView``'s top-leading toolbar gear. No
/// own `NavigationStack` — the host stack (in ``ContentView``) carries
/// the push.
///
/// ## Styling
/// Stock SwiftUI: system fonts (UI #18), semantic colors (UI #17),
/// destructive role for the two actions. ``Design/DesignSystem`` is
/// intentionally untouched per the dispatch brief's MAY-NOT-modify
/// scope — Phase 7 V3 #22 design pass remains the surface for visual
/// polish.
struct SettingsView: View {
    /// Backing view-model. Owns the reload pipeline + destructive-op
    /// re-entry guard. `@State` so SwiftUI retains it across re-renders.
    @State private var model: SettingsViewModel

    /// Production initializer — closes over the bootstrapper-resolved
    /// ``StorageStatsProviding`` + ``MeetingStore``. Called from
    /// ``MeetingListView``'s gear-icon toolbar item.
    ///
    /// - Parameters:
    ///   - statsProvider: Production provider from ``AppBootstrapper``.
    ///   - meetingStore: The actor used for the delete-all path.
    init(statsProvider: any StorageStatsProviding, meetingStore: MeetingStore) {
        _model = State(
            initialValue: SettingsViewModel(
                statsProvider: statsProvider,
                meetingStore: meetingStore
            )
        )
    }

    /// Test-only initializer that accepts a pre-built view-model so
    /// previews and tests can drive every state without owning a real
    /// ``MeetingStore`` actor or live filesystem.
    init(model: SettingsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            aboutSection
            storageSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .confirmationDialog(
            "Clear LFM2 prompt cache?",
            isPresented: clearCacheDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task { await model.confirmPending() }
            }
            Button("Cancel", role: .cancel) {
                model.cancelPending()
            }
        } message: {
            Text("Translation will rebuild context on the next sentence. No transcripts are affected.")
        }
        .confirmationDialog(
            "Delete all transcripts?",
            isPresented: deleteAllDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await model.confirmPending() }
            }
            Button("Cancel", role: .cancel) {
                model.cancelPending()
            }
        } message: {
            Text(
                "This cannot be undone. All \(model.stats?.transcriptCount ?? 0) meetings will be permanently removed."
            )
        }
    }

    /// Binding for the Clear-cache confirmation dialog. Reads `true`
    /// when ``SettingsViewModel/pending`` equals `.clearCache`; writes
    /// `false` (dialog dismissal) route through
    /// ``SettingsViewModel/cancelPending()``.
    private var clearCacheDialogBinding: Binding<Bool> {
        Binding(
            get: { model.pending == .clearCache },
            set: { newValue in
                if !newValue { model.cancelPending() }
            }
        )
    }

    /// Binding for the Delete-all confirmation dialog. Symmetric with
    /// ``clearCacheDialogBinding``.
    private var deleteAllDialogBinding: Binding<Bool> {
        Binding(
            get: { model.pending == .deleteAll },
            set: { newValue in
                if !newValue { model.cancelPending() }
            }
        )
    }

    /// About section — version, privacy promise, project link.
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: SettingsFormatter.versionString())
            Text("Fully on-device. Your conversations stay on your iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = URL(string: "https://github.com/OnigiriMerchant/arigato-ai") {
                Link("Project on GitHub", destination: url)
            }
        }
    }

    /// Storage section — cache size, transcript count, two destructive
    /// actions with confirmation dialogs attached at the view root.
    private var storageSection: some View {
        Section("Storage") {
            LabeledContent("LFM2 cache size") {
                Text(cacheSizeLabel)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Transcripts") {
                Text(SettingsFormatter.transcriptCountLabel(model.stats?.transcriptCount ?? 0))
                    .foregroundStyle(.secondary)
            }
            Button("Clear cache", role: .destructive) {
                model.requestClearCache()
            }
            .disabled(model.isClearingCache || model.isDeletingAll)

            Button("Delete all transcripts", role: .destructive) {
                model.requestDeleteAll()
            }
            .disabled(model.isClearingCache || model.isDeletingAll)
        }
    }

    /// Em-dash placeholder while the initial ``SettingsViewModel/load()``
    /// is in flight; otherwise the formatted byte count.
    private var cacheSizeLabel: String {
        guard let stats = model.stats else { return "—" }
        return SettingsFormatter.bytes(stats.lfm2CacheBytes)
    }
}
