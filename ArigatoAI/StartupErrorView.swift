//
//  StartupErrorView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import SwiftUI

/// Terminal failure surface shown when the SwiftData ``ModelContainer``
/// cannot be constructed at app launch.
///
/// Replaces the old `fatalError` path: users see a calm, legible screen
/// explaining that the app cannot start, plus a Quit affordance, instead
/// of a process abort. The view is intentionally minimal — there is no
/// "retry" because retrying without changing on-disk state would fail
/// the same way.
struct StartupErrorView: View {
    /// The error raised by `ModelContainer.init`, propagated from
    /// ``AppBootstrapper/containerError``. `nil` is treated as an unknown
    /// error so the UI never displays an empty body.
    let error: Error?

    var body: some View {
        ZStack {
            Color.surfaceBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("App can't start")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(error?.localizedDescription ?? "Unknown error")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(role: .destructive) {
                    // exit(0) is acceptable here: the SwiftData container
                    // failed; retrying without on-disk state changes will
                    // fail again. There is no recoverable in-process path.
                    exit(0)
                } label: {
                    Text("Quit")
                        .fontWeight(.medium)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                // Let `role: .destructive` resolve to the system destructive
                // color rather than overloading the recording accent. The
                // recording-active hue is reserved for live mic state — see
                // ui-reviewer note 2026-05-10.
                .padding(.top, 8)
                .accessibilityHint("Closes the app. Re-open after the underlying issue is resolved.")
            }
            .padding(.horizontal, 32)
        }
    }
}

#Preview("Container failure") {
    struct PreviewError: LocalizedError {
        var errorDescription: String? {
            "ModelContainer failed: store at /var/mobile/.../ArigatoAI.sqlite is corrupt."
        }
    }
    return StartupErrorView(error: PreviewError())
}

#Preview("Unknown error") {
    StartupErrorView(error: nil)
}

#Preview("LFM2 warmup failure") {
    StartupErrorView(
        error: TranslationError.warmupFailed("Canary inference timed out after 30s.")
    )
}
