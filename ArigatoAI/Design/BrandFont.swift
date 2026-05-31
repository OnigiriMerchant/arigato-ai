//
//  BrandFont.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/31.
//

import CoreText
import Foundation

/// Bundled brand-font registration (Phase 7 Step 5 — brand moments).
///
/// Two Latin-only, OFL-1.1 faces from `vercel/geist-font`, bundled in
/// `Resources/Fonts/` (license: `Resources/Fonts/OFL.txt`) and scoped to the
/// onboarding hero only. Both have **no CJK** and must never render
/// transcript / body / metadata text — those stay system fonts (see
/// ``DesignSystem/Typography``):
/// - **Geist Pixel** (``geistPixelWordmark``) — the "ARIGATO AI" wordmark.
/// - **Geist Mono** (``geistMonoTagline``) — the onboarding tagline (one line
///   of supporting copy). A deliberate Phase 7 expansion of the custom-font
///   scope beyond the wordmark, limited to this tagline.
///
/// ## Why programmatic registration (not `UIAppFonts`)
///
/// The project builds with `GENERATE_INFOPLIST_FILE = YES` (no `Info.plist`
/// file), and Xcode's `INFOPLIST_KEY_UIAppFonts` build setting is **not**
/// honoured — it is silently dropped from the generated `Info.plist` (verified:
/// `UIAppFonts` absent from the built product). So the bundled fonts are
/// registered at runtime via `CTFontManagerRegisterFontsForURL`. This also
/// makes `Font.custom` resolve inside SwiftUI Previews (which do not run the
/// app's launch path), which app-launch registration would not.
///
/// Registration runs exactly once per process (lazy, thread-safe `static let`).
enum BrandFont {
    /// PostScript name of the wordmark face, read from the file via CoreText
    /// (`CTFontCopyPostScriptName`) — not guessed. "ARIGATO AI" only.
    static let geistPixelWordmark = "GeistPixel-Square"

    /// PostScript name of the tagline face, read from the file via CoreText.
    /// The onboarding tagline only — never transcript / body text.
    static let geistMonoTagline = "GeistMono-Regular"

    /// Lazy one-shot registration of both bundled brand fonts.
    private static let registerOnce: Void = {
        for resource in ["GeistPixel-Square", "GeistMono-Regular"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registers the bundled brand fonts if not already registered. Call before
    /// rendering any `Font.custom(…)` brand text — e.g. from
    /// `OnboardingView.init`, so the fonts resolve before first render in both
    /// the app and Previews.
    static func registerIfNeeded() {
        _ = registerOnce
    }
}
