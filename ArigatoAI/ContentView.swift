//
//  ContentView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/06.
//

import SwiftUI

/// Top-level app surface for Arigato AI. Phase 4 hosts the live
/// transcription experience via ``TranscriptLiveView``; the bootstrapper
/// flows in from ``ArigatoAIApp`` through the SwiftUI environment, so this
/// view is a thin wrapper.
struct ContentView: View {
    var body: some View {
        TranscriptLiveView()
    }
}

#Preview {
    ContentView()
        .environment(AppBootstrapper())
}
