//
//  ContentView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/06.
//

import SwiftUI

/// Top-level app surface for Arigato AI. Phase 3 wires this to the
/// microphone capture view; later phases will replace it with the live
/// caption experience. The view model is constructed inside
/// ``AudioCaptureView`` so callers do not need to know about it.
struct ContentView: View {
    var body: some View {
        AudioCaptureView()
    }
}

#Preview {
    ContentView()
}
