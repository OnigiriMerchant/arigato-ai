---
name: swiftui-design
description: Arigato AI's design system — color tokens, typography, spacing, component patterns. Use when creating or modifying any SwiftUI view to ensure visual consistency.
---

# Arigato AI design system

## Design principles (in priority order)
1. **Caption-first hierarchy** — captions are the product, controls recede
2. **Calm color, intentional accent** — restraint over decoration
3. **Glanceable status, no chrome** — minimal UI during a session
4. **Liquid Glass aesthetic** — translucent overlays, generous spacing
5. **Dark mode parity** — every view works in both light and dark

## Color tokens
```swift
extension Color {
    // Recording state — the only chromatic accent in the app
    static let recordingActive = Color(red: 0.94, green: 0.27, blue: 0.27)  // muted red
    static let recordingIdle = Color(white: 0.5, opacity: 1.0)              // mid gray
    
    // Caption emphasis
    static let captionPrimary = Color.primary                  // English (target)
    static let captionSecondary = Color.secondary              // Japanese (source)
    
    // Surfaces (Liquid Glass)
    static let surfaceFloating = Color(.systemBackground).opacity(0.85)
    static let surfaceBackground = Color(.systemBackground)
}
```

## Typography
- Headlines: SF Pro Display, `.title2`, `.semibold`
- Captions (live): SF Pro Display, `.title`, `.regular` for translations; `.title3` for source
- Body: SF Pro Text, `.body`
- Metadata (timestamps): SF Pro Text, `.caption`, `.secondary`
- ALL text uses Dynamic Type — no fixed font sizes

## Spacing scale
- 4, 8, 12, 16, 24, 32, 48 — use these only
- Section padding: 16
- View edge padding: 20 (gives breathing room from screen edges)
- Caption line spacing: 1.4× font line height

## Component patterns

### Live caption row (the most important component)
```swift
struct CaptionRow: View {
    let japanese: String
    let english: String
    let direction: TranslationDirection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Source language (smaller, secondary)
            Text(japanese)
                .font(.title3)
                .foregroundStyle(.secondary)
            // Target language (larger, primary)
            Text(english)
                .font(.title)
                .fontWeight(.regular)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 8)
    }
}
```

### Recording button
- 64pt circle when idle (gray), 80pt + pulse animation when active (red)
- Centered at bottom of live view
- Long press = stop, single tap = pause/resume

## Dark mode rules
- Use semantic colors (.primary, .secondary, Color(.systemBackground)) — never hardcoded hex
- Test EVERY view in both modes via SwiftUI Preview
- Liquid Glass effects (.ultraThinMaterial) handle dark mode automatically

## Accessibility floor
- Dynamic Type support up to .accessibility3 minimum
- VoiceOver labels on every interactive element
- 44x44pt minimum tap targets
- Reduce Motion respected for the recording button pulse

## What NOT to do
- No emoji icons. SF Symbols only.
- No custom font files. SF Pro family only.
- No fixed-pixel layouts. Use HStack/VStack with spacing tokens.
- No more than 2-3 colors per screen.
- No drop shadows. Use Material/blur for depth instead.
