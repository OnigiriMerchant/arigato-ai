//
//  ArigatoAIApp.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/06.
//

import SwiftData
import SwiftUI

@main
struct ArigatoAIApp: App {
    /// App-wide bootstrapper. Owns the Whisper loader, mirrors its state
    /// for the UI, and holds any container-construction error so the
    /// failure path renders ``StartupErrorView`` instead of crashing.
    @State private var bootstrapper: AppBootstrapper

    /// Optional SwiftData container. `nil` means construction threw at
    /// launch; the body switches to ``StartupErrorView`` in that case.
    private let sharedModelContainer: ModelContainer?

    init() {
        let container: ModelContainer?
        var containerError: Error?
        do {
            let schema = Schema([Item.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            container = nil
            containerError = error
        }
        sharedModelContainer = container

        // Construct the bootstrapper with the container error pre-seeded
        // (or nil on success), then assign through `_bootstrapper` to
        // honour the `@State` storage contract. The direct-mutation
        // pattern fails compilation here because `self` is not yet fully
        // initialized before `sharedModelContainer` is assigned.
        let boot = AppBootstrapper(containerError: containerError)
        _bootstrapper = State(wrappedValue: boot)

        // Kick off Whisper pre-warm regardless of container outcome. If
        // the container failed the user will see the error screen, but
        // the loader work doing nothing meaningful in the background is
        // cheaper than coupling the two lifecycles.
        boot.startPrewarm()
    }

    var body: some Scene {
        WindowGroup {
            if let sharedModelContainer, startupError == nil {
                ContentView()
                    .environment(bootstrapper)
                    .modelContainer(sharedModelContainer)
            } else {
                StartupErrorView(error: startupError)
                    .environment(bootstrapper)
            }
        }
    }

    /// Selects which startup error (if any) to surface in
    /// ``StartupErrorView``, in priority order:
    ///
    /// 1. SwiftData container construction error — terminal; without a
    ///    container the rest of the app cannot run.
    /// 2. Whisper loader failure — recording is the app's primary
    ///    function; if ASR is unavailable the user cannot capture
    ///    audio, so we treat this as terminal.
    /// 3. LFM2 loader failure — translation is the app's secondary
    ///    function but the post-handoff design treats both pipelines
    ///    as load-bearing for the meeting use case. Surfacing the
    ///    error at launch is honest about which capability the user
    ///    will be missing.
    ///
    /// Returns `nil` when no startup error is present, in which case
    /// the body renders ``ContentView``.
    private var startupError: Error? {
        if let containerError = bootstrapper.containerError {
            return containerError
        }
        if case let .failed(error) = bootstrapper.loaderState {
            return error
        }
        if case let .failed(error) = bootstrapper.lfm2LoaderState {
            return error
        }
        return nil
    }
}
