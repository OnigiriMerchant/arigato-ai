# Phase 5 Group D — Pre-flight Doc-Researcher Findings

**Status:** Pre-flight gate before Step 1 of Group D implementation. Required per V3 #41 and CLAUDE.md "External dependency configuration" rule.

**Dispatched:** 2026-05-16, four parallel `@doc-researcher` runs (DR-1 through DR-4) covering load-bearing uncertainties surfaced in the Group D plan.

**Authority:** Apple Developer Documentation, WWDC session transcripts, Apple Developer Forums (DTS engineer responses), `mcp__xcode__DocumentationSearch` against the local Xcode 26 doc index, SQLite official docs (sqlite.org) for the FTS5 question.

---

## Headline finding (read first)

**DR-3 (SwiftData `localizedStandardContains` performance + correctness) surfaces a "DECISION #14 TRIGGER LIKELY FIRES ON DAY ONE" warning.** Three compounding problems, only one of which is latency:

1. **Correctness:** `localizedStandardContains` is documented as case- and diacritic-insensitive but is **not** documented to match hiragana ↔ katakana. The hiragana↔katakana transform is a separate `StringTransform`, not part of `localizedStandardContains`'s option set. A search for "とうきょう" (hiragana) will likely not match "トウキョウ" (katakana). For a Japanese transcript app, this is a correctness gap independent of speed.

2. **Architecture:** The relationship-traversal predicate `Meeting.sentences.contains { $0.sourceText.localizedStandardContains(query) }` (which the Step 12 plan implies) has **documented runtime failures** in SwiftData. Apple Developer Forums threads 731609, 747226, 758449 + Swift Forums 73565 report `"to-many key not allowed here"` errors from the CoreData SQLite layer for this pattern. DTS engineer in thread 758449 confirms `contains()` in a predicate "only works with string comparisons or to-many relationships (converted to subqueries)" — and the conversion is fragile for `localizedStandardContains` inside the closure.

3. **Latency unconfirmed:** Apple has published zero benchmarks for `localizedStandardContains` at any row count on any hardware. SQLite's optimizer overview confirms `LIKE '%term%'` patterns cannot use a B-tree index. SwiftData's `#Index` macro (iOS 18+) creates B-tree indexes only — declaring `#Index` on `Sentence.sourceText` will **not** accelerate `localizedStandardContains`. The 200ms budget is plausible for a flat SQLite scan but at unknown risk if SwiftData falls back to in-memory evaluation (which the relationship-traversal pattern is documented to do under iOS 18).

**Implication for the Group D plan:**

- Step 12's predicate architecture must be **restructured to a flat `Sentence` fetch** (no relationship-contains), with results joined to `Meeting` in Swift via DTO projection. This changes the `MeetingStore.fetchAll(searchText:)` shape surfaced in Step 2.
- A pre-computed `searchableText` field on `Sentence` (normalized: hiragana→katakana, lowercased, diacritic-stripped) is **required for Japanese correctness**, not optional. This adds a small `@Model` field + an insert-time normalization step.
- Step 12's violation test must include an **on-device benchmark** that seeds 15K rows and asserts sub-200ms latency on iPhone 17 Pro Max. If it fails, Decision #14 fires immediately and FTS5 migration is in-scope for MVP 1, not deferred.

**Recommendation:** Revise the Group D plan before Step 1 dispatches. Specifically Steps 1, 2, and 12. Details in §DR-3 below + §Plan Amendments.

---

## DR-1 — SwiftData `@ModelActor` + Swift 6 Sendable

### Findings

**1a. `@ModelActor` is Apple's documented pattern.** "Concurrency support" (developer.apple.com/documentation/swiftdata/concurrencysupport) names `@ModelActor` as the macro for safe, isolated SwiftData access. Apple Developer Forums thread 805409 carries a DTS engineer (Ziqiao Chen) response describing the canonical two-tier pattern: light tasks on `@MainActor`, heavy tasks on `@ModelActor`, exchange via `Sendable` types, `@Query` observes the data store. Hand-rolling an actor that owns a `ModelContext` is a community workaround for the bug below, not an Apple-recommended alternative.

**1b. `@ModelActor` generates:**

```swift
nonisolated let modelExecutor: any SwiftData.ModelExecutor
nonisolated let modelContainer: SwiftData.ModelContainer
init(modelContainer: SwiftData.ModelContainer)  // synthesized
```

The init creates a `ModelContext` from the container, wraps it in `DefaultSerialModelExecutor`, and pins the context to a single serial queue. `modelContext` is accessible inside the actor via `ModelExecutor.modelContext`.

**1c. Open background-execution bug (iOS 17 — iOS 18+, no iOS 26 fix confirmation).** When a `@ModelActor` instance is created from a `Task` already running on `@MainActor`, the actor's executor can inherit the main thread as its execution context, causing background writes to block the UI. Documented in Apple Developer Forums threads 736226, 770416 + Feedback Assistant IDs FB13038621, FB13399899.

**Workaround:** Initialize the `MeetingStore` from a `Task.detached { ... }` block, or from `App.init` off the main-actor path. The bug has not been confirmed fixed in iOS 26 by any Apple source.

**2. `@Model` types are NOT Sendable.** Apple engineer in thread 735805: "model classes are not internally thread safe, so you should not do this. You can pass the `persistentModelID` between actors. `PersistentIdentifier` is sendable." DTS in 805409: "Do not return SwiftData Models from your ModelActor … Only return sole properties and the `persistentModelID` to identify models."

Under Swift 6 strict concurrency: returning a `@Model` instance across actor boundaries produces a **compiler error**, not a warning. Adding `@unchecked Sendable` is explicitly warned against. The required pattern is DTO projection — return `MeetingSummary { id: PersistentIdentifier, title: String, ... }` from the actor, or return only `PersistentIdentifier` and re-fetch on the main context.

**3. Cascade delete timing is officially undocumented.** WWDC23 session 10195 implies same-save deletion. Forums thread 740649 (FB13640004) reports cases where explicit `save()` prevents cascade. Apple has not published a fix. **Test design must verify cascade with a single `save()` call** and ideally a second test exercising the FB13640004 failure mode.

### Impact on the plan

- **Decision D-1 (`@ModelActor` macro) confirmed correct** — this is Apple's documented path.
- **New constraint for Step 8 (Bootstrapper wiring):** `MeetingStore` must be initialized inside `Task.detached { ... }`, not on the main actor. Step 8 (and Step 1/Step 2 tests) must document this scheduling assumption + add a violation test that asserts writes do not block the main thread.
- **New constraint for Step 2 (MeetingStore DTOs):** `MeetingSummary` and `MeetingDetail` DTOs are mandatory, not stylistic. Returning `Meeting` directly from any `MeetingStore` method will fail Swift 6 strict concurrency.
- **New test for Step 1:** Cascade delete with single `save()` (happy path) + a second test that exercises the FB13640004 failure mode (explicit pre-delete save), to detect regression if Apple re-introduces the bug.

### Sources

- [Concurrency support — SwiftData](https://developer.apple.com/documentation/swiftdata/concurrencysupport)
- [ModelActor protocol](https://developer.apple.com/documentation/swiftdata/modelactor)
- [Apple Developer Forums 805409 — Correct SwiftData Concurrency Logic (DTS Ziqiao Chen)](https://developer.apple.com/forums/thread/805409)
- [Apple Developer Forums 735805 — Is it safe to mark @Model as Sendable?](https://developer.apple.com/forums/thread/735805)
- [Apple Developer Forums 736226 — SwiftData does not work on background thread](https://developer.apple.com/forums/thread/736226)
- [Apple Developer Forums 740649 — SwiftData cascade delete FB13640004](https://developer.apple.com/forums/thread/740649)
- [Model your schema with SwiftData — WWDC23 session 10195](https://developer.apple.com/videos/play/wwdc2023/10195/)

---

## DR-2 — `ShareLink` payload shape on iOS 26.4+

### Findings

**Single-URL share (Contexts A + B):**
```swift
nonisolated init(item: URL, subject: Text? = nil, message: Text? = nil)
    where Data == CollectionOfOne<URL>
```
iOS 16+, no `preview:` required. Source: `developer.apple.com/documentation/swiftui/sharelink/init(item:subject:message:)-9ap6z`.

**Single-String share:**
```swift
nonisolated init(item: String, subject: Text? = nil, message: Text? = nil)
    where Data == CollectionOfOne<String>
```
iOS 16+, no `preview:` required. Source: `-49l2l` overload.

**Multi-URL share (Context C — the plan's load-bearing question):**
```swift
nonisolated init(items: Data, subject: Text? = nil, message: Text? = nil)
    where Data: RandomAccessCollection, Data.Element == URL
```
iOS 16+, **no `preview:` required, single share sheet invocation**. Source: `-8p4sn` overload. `[String]` array shares similarly via `-7e7e0` overload.

**Custom `Transferable` arrays** (not needed for plain `.txt` export) require `init(_:items:subject:message:preview:)` with a synchronous `SharePreview` closure — confirmed by Apple Developer Forums thread 745611.

**Recommended payload for transcript export:** Write a temp `.txt` to `FileManager.default.temporaryDirectory`, share via `ShareLink(item: fileURL)` (single) or `ShareLink(items: urlArray)` (multi). This preserves filename + MIME type (`text/plain` from the `.txt` extension), and recipients can save / forward / open in Files.app.

**No iOS 26 changes to `ShareLink`.** WWDC25 session 256 ("What's new in SwiftUI") does not mention `ShareLink`. iOS 26.5 release notes have no `ShareLink` content. No deprecations or new convenience initializers found.

### Impact on the plan

- **Decision D-6 + Step 13 (Export) confirmed correct as planned.** `ShareLink(items: [URL])` natively handles Context C; no `UIActivityViewController` wrapper needed.
- **No revisions required.** Implementation proceeds as Step 13 planned.

### Sources

- [ShareLink — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/sharelink)
- [init(items:subject:message:) URL variant -8p4sn](https://developer.apple.com/documentation/swiftui/sharelink/init(items:subject:message:)-8p4sn)
- [init(item:subject:message:) URL single -9ap6z](https://developer.apple.com/documentation/swiftui/sharelink/init(item:subject:message:)-9ap6z)
- [Apple Developer Forums 745611 — Share multiple Transferables with ShareLink](https://developer.apple.com/forums/thread/745611)
- [Meet Transferable — WWDC22 session 10062](https://developer.apple.com/videos/play/wwdc2022/10062/)

---

## DR-3 — SwiftData `#Predicate` with `localizedStandardContains` performance & correctness

### Findings (in order of severity)

**A. Hiragana ↔ katakana matching is not part of `localizedStandardContains` — CORRECTNESS GAP.**

Apple's `NSString.localizedStandardContains` doc (developer.apple.com/documentation/foundation/nsstring/1416328-localizedstandardcontains): "a case and diacritic insensitive, locale-aware search." Width-insensitive comparison is a **separate** `NSStringCompareOptions` flag (`widthInsensitive`, doc 1409350). Hiragana↔katakana matching is a **separate** `StringTransform` (`hiraganaToKatakana`, doc 1411617), not part of any `localizedStandardContains` option set.

`StringProtocol.localizedStandardContains` doc verbatim: "The exact list of search options applied may change over time." Apple deliberately leaves the set open — but as of iOS 26.4, hiragana↔katakana inclusion is **not documented**.

For a Japanese meeting transcript app, this means "とうきょう" (hiragana) likely does not match "トウキョウ" (katakana) under `localizedStandardContains`. Confirmation requires an on-device test, but the documentation does not support the cross-script claim.

**B. Relationship-traversal predicates have documented runtime failures — ARCHITECTURE GAP.**

The Step 12 plan implies the predicate shape `Meeting.sentences.contains { $0.sourceText.localizedStandardContains(query) }`. Multiple Apple Developer Forums threads + a Swift Forums thread report runtime failures for this pattern:

- Thread 747226 (apple): `unsupportedKeyPath` on `contains(where:)` with `localizedStandardContains`.
- Thread 731609 (apple): DTS confirms `"to-many key not allowed here"` is a CoreData-layer SQLite error.
- Thread 758449 (apple): DTS engineer states `contains()` in a predicate "only works with string comparisons or to-many relationships (converted to subqueries)" — but the conversion is fragile for `localizedStandardContains` inside the closure.
- forums.swift.org/t/73565: "CoreData: error: SQLCore dispatchRequest: exception handling request… to-many key not allowed here" on `contains(where:)` over to-many relationships.

The reliable fallback: fetch `Sentence` rows directly with a flat predicate, then group/join to `Meeting` in Swift.

**C. Latency unconfirmed — RISK.**

Apple has published zero benchmarks for `localizedStandardContains` at any row count. WWDC25 session 291 demonstrates `localizedStandardContains` in a predicate with no performance figures. WWDC24 session 10137 introduces the `#Index` macro but does not claim it accelerates substring search.

SQLite optimizer overview (sqlite.org/optoverview.html) is unambiguous: "if the right-hand side begins with a wildcard character then this optimization is not attempted." A `LIKE '%term%'` pattern cannot use a B-tree index. SwiftData's `#Index` macro creates B-tree indexes (WWDC24 doc verbatim: "additional metadata which SwiftData generates and saves … binary indices") — therefore `#Index` on `Sentence.sourceText` does **not** accelerate `localizedStandardContains`.

Apple Developer Forums thread 740517 carries a developer note that SwiftData "seems not built for big data batches" and recommends pagination for 100K+ rows. Thread 761522 documents an iOS 18 regression where `.count` on relationship arrays loaded the entire array into memory. If SwiftData's relationship-traversal predicate evaluation falls back to in-memory iteration, 15K rows × per-row NSString `localizedStandardContains` call easily exceeds 200ms.

**D. No SwiftData-native escape hatch.**

`#Index` does not help (see C). A pre-computed `searchableText` field on `Sentence` (normalized text) reduces per-row comparison cost (drop locale overhead, drop case folding) and fixes the correctness gap (manual hiragana→katakana conversion at insert time). It does not change O(n) scan complexity but is structurally sound and not in conflict with any Apple documentation.

### Impact on the plan

**This requires plan revisions before Step 1 dispatches.** Surfaced for user approval below.

### Sources

- [WWDC24 session 10137 — What's new in SwiftData (#Index macro)](https://developer.apple.com/videos/play/wwdc2024/10137/)
- [WWDC25 session 291 — SwiftData: Dive into inheritance and schema migration](https://developer.apple.com/videos/play/wwdc2025/291/)
- [localizedStandardContains — NSString doc 1416328](https://developer.apple.com/documentation/foundation/nsstring/1416328-localizedstandardcontains)
- [localizedStandardContains — StringProtocol doc](https://developer.apple.com/documentation/swift/stringprotocol/localizedstandardcontains(_:))
- [NSStringCompareOptions.widthInsensitive doc 1409350](https://developer.apple.com/documentation/foundation/nsstring/compareoptions/1409350-widthinsensitive)
- [StringTransform.hiraganaToKatakana doc 1411617](https://developer.apple.com/documentation/foundation/stringtransform/1411617-hiraganatokatakana)
- [SwiftData Index(_:) macro doc -74ia2](https://developer.apple.com/documentation/swiftdata/index(_:)-74ia2)
- [SQLite Query Optimizer Overview](https://www.sqlite.org/optoverview.html)
- [SQLite FTS5 Extension](https://www.sqlite.org/fts5.html)
- [Apple Developer Forums 747226 — SwiftData Predicates and .contains](https://developer.apple.com/forums/thread/747226)
- [Apple Developer Forums 731609 — Predicate based on relationship](https://developer.apple.com/forums/thread/731609)
- [Apple Developer Forums 758449 — Tokenised text search in SwiftData](https://developer.apple.com/forums/thread/758449)
- [Apple Developer Forums 740517 — SwiftData slow with large data](https://developer.apple.com/forums/thread/740517)
- [Apple Developer Forums 761522 — SwiftData iOS 18 extreme memory](https://developer.apple.com/forums/thread/761522)
- [Swift Forums 73565 — Complex Predicates in SwiftData](https://forums.swift.org/t/complex-predicates-in-swiftdata/73565)

---

## DR-4 — SwiftUI `ScrollView` programmatic scroll + at-bottom detection on iOS 26

### Findings

**Programmatic scroll-to-bottom (Step 9 + decision #2):** Use `ScrollPosition` struct + `.scrollPosition(_:anchor:)` modifier (iOS 18+). The `ScrollPosition.scrollTo(edge: .bottom)` mutating method is content-size-agnostic and does not require tagging a last-item `id`. `ScrollViewReader` + `proxy.scrollTo(id:)` is not deprecated but is superseded for new iOS 26 code.

**At-bottom detection (decision #2 OR-across-both-halves):** Use `.onScrollGeometryChange(for:of:action:)` (iOS 18+). `ScrollGeometry` exposes `contentOffset: CGPoint`, `contentSize: CGSize`, `containerSize: CGSize`, `contentInsets: EdgeInsets`. The "at bottom" boolean is computed from those four values:

```swift
let atBottom = geometry.contentOffset.y + geometry.containerSize.height
               >= geometry.contentSize.height - geometry.contentInsets.bottom
```

WWDC24 session 10144 demonstrates the exact structural pattern for "show button when scrolled away from an edge" — Apple's example detects "scrolled away from top" to show a back button; same shape for "scrolled away from bottom."

**Two independent ScrollViews in a VStack (Step 9):** Each gets its own `@State var ScrollPosition` and its own `.onScrollGeometryChange` modifier attached directly to its content subtree. No shared `ScrollViewReader` parent needed. The documented gotcha: `.onScrollGeometryChange` only fires for the **first** scroll view in a hierarchy that contains the modifier — so each modifier must be attached inside each `ScrollView`'s subtree, not at a common ancestor. Boolean composition via `var arrowVisible: Bool { !jaAtBottom || !enAtBottom }` is plain `@State` composition and has no documented restriction.

**Synchronized dual-scroll animation (decision #2 unified arrow):**

```swift
Button {
    withAnimation(.easeInOut(duration: 0.35)) {
        jaPosition.scrollTo(edge: .bottom)
        enPosition.scrollTo(edge: .bottom)
    }
}
```

Both mutations in the same `withAnimation` block apply a single animation transaction. Apple does not document pixel-identical frame timing if content sizes differ, but the same curve + duration apply.

**No iOS 26-specific scroll APIs.** WWDC25 session 256 does not mention scroll APIs. iOS 18 (`ScrollPosition`, `onScrollGeometryChange`, `defaultScrollAnchor`) remains canonical for iOS 26.

### Impact on the plan

- **Step 9 (TranscriptLiveView split-screen layout) confirmed correct with API selection.** Use `.scrollPosition($position)` for programmatic scroll, `.onScrollGeometryChange(for:of:action:)` for at-bottom detection. Two independent ScrollViews in a VStack; each owns its own state.
- **TranscriptViewModel** (Step 6) needs `jaPosition: ScrollPosition`, `enPosition: ScrollPosition`, `jaAtBottom: Bool`, `enAtBottom: Bool` — slightly more state than the plan implied, but no architectural change.
- **No revisions required.**

### Sources

- [ScrollPosition — SwiftUI](https://developer.apple.com/documentation/swiftui/scrollposition)
- [ScrollPosition.scrollTo(edge:)](https://developer.apple.com/documentation/swiftui/scrollposition/scrollto(edge:))
- [onScrollGeometryChange(for:of:action:)](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:))
- [ScrollGeometry](https://developer.apple.com/documentation/swiftui/scrollgeometry)
- [What's new in SwiftUI — WWDC24 session 10144](https://developer.apple.com/videos/play/wwdc2024/10144/)
- [What's new in SwiftUI — WWDC25 session 256](https://developer.apple.com/videos/play/wwdc2025/256/)

---

## Plan amendments required before Step 1

Surfaced for user approval. Three amendments, all driven by DR-3 (the latency/correctness/architecture findings) plus one by DR-1 (the `@ModelActor` background-thread bug).

### Amendment 1 — Add `searchableText` field to `Sentence` (Step 1 scope change)

Add a non-relationship field to the `Sentence` entity:

```swift
@Model final class Sentence {
    // ... existing fields ...
    var searchableText: String   // normalized: hiragana→katakana, lowercased, diacritic-stripped
}
```

Populated at insert time (Step 2's `MeetingStore.appendSentence`) by a new helper `SearchTextNormalizer.normalize(_:)`:

```swift
enum SearchTextNormalizer {
    static func normalize(_ s: String) -> String {
        var mutable = s as NSString
        mutable = mutable.applyingTransform(.hiraganaToKatakana, reverse: false) as NSString? ?? mutable
        return (mutable as String)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }
}
```

**Why:** Fixes hiragana↔katakana correctness gap. Reduces per-row comparison cost (drop locale-aware NSString call → plain Swift `contains`). Adds one `@Model` field; the wipe-on-schema-mismatch migration policy (decision #20) absorbs the schema change.

**New test in Step 1:** `SearchTextNormalizerTests` — hiragana input → katakana output, full-width digits → half-width, diacritic stripping, idempotence.

### Amendment 2 — Restructure Step 12 to flat `Sentence` fetch + DTO join

The Step 12 `MeetingStore.fetchAll(searchText:)` plan implied a relationship-traversal predicate. **That pattern fails per DR-3 §B.** Restructure to:

```swift
// Inside MeetingStore (@ModelActor):
func fetchAll(searchText: String?) async throws -> [MeetingSummary] {
    guard let raw = searchText, !raw.isEmpty else {
        // No search — flat Meeting fetch newest-first.
        let descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map { MeetingSummary(from: $0) }
    }
    let needle = SearchTextNormalizer.normalize(raw)
    // Step 1: fetch Sentence rows matching the normalized needle.
    var sentDescriptor = FetchDescriptor<Sentence>(
        predicate: #Predicate<Sentence> { $0.searchableText.contains(needle) || $0.meeting.title.localizedStandardContains(raw) }
    )
    // NOTE: $0.meeting.title traversal is a to-ONE relationship — DR-3 §B failures are documented for to-MANY only.
    let matchingSentences = try modelContext.fetch(sentDescriptor)
    // Step 2: group by meeting, project to MeetingSummary with firstMatchSnippet.
    let grouped = Dictionary(grouping: matchingSentences, by: { $0.meeting.persistentModelID })
    return grouped.compactMap { (_, sentences) in
        guard let m = sentences.first?.meeting else { return nil }
        return MeetingSummary(from: m, firstMatchSnippet: sentences.first?.translatedText)
    }.sorted { $0.startedAt > $1.startedAt }
}
```

Notes:
- **To-one** (`Sentence.meeting.title`) is safe per DR-3 §B (documented failures are for to-many `contains(where:)`).
- The predicate uses plain `String.contains(needle)` on the normalized field — no locale call, cheap full-table scan.
- The deduplication + projection happens in Swift, off the actor's heaviest path.

**Step 12 plan update:**
- Decision #14 trigger logic stands as planned (target: 200ms on real device).
- The violation test `historyViewModelTests.search_rapidTyping_firesOnlyOneQueryAfter300msQuiet` is unchanged.
- **New benchmark test in Step 12:** `historyViewModelTests.search_15kRowsOnDevice_completesUnder200ms` — seed 100 meetings × 150 sentences with synthetic Japanese + English text, fire one search, assert latency < 200ms on iPhone 17 Pro Max via XCTest measurement.
- **If the benchmark fails:** Decision #14 fires for MVP 1. FTS5 migration becomes a new Step 12.5 (or replaces Step 12 entirely). User approves the call when the benchmark result is known, not pre-emptively.

### Amendment 3 — `MeetingStore` initialization off the main actor (Step 8 scope change)

Per DR-1 §1c, `@ModelActor` initialized from a `@MainActor` Task can inherit the main thread. Step 8's `AppBootstrapper` wiring must initialize `MeetingStore` via `Task.detached`:

```swift
// AppBootstrapper.swift
nonisolated init() {
    self.container = try! ModelContainer(for: Meeting.self, Sentence.self)
    // Defer store creation to a detached task so the actor's executor
    // does not inherit the main thread (per FB13399899 / forums 736226).
    Task.detached { [container] in
        let store = MeetingStore(modelContainer: container)
        await MainActor.run { self.meetingStore = store }
    }
}
```

**New scheduling-assumption doc-comment** on `AppBootstrapper.meetingStore`: "Initialized via `Task.detached` to avoid main-actor executor inheritance per Apple Developer Forums 736226 / FB13399899. Assumed-published-iOS-26 status: unconfirmed."

**New violation test in Step 8:** `AppBootstrapperTests.meetingStoreWrites_doNotBlockMainThread` — fire 100 `appendSentence` calls via the bootstrapper-attached subscriber, assert main-thread is responsive (measured via `RunLoop.main.run(until:)` heartbeat) throughout the burst.

### Amendment 4 — Cascade-delete regression test (Step 1 scope addition)

Per DR-1 §3 (FB13640004), add a second cascade test to `MeetingEntityTests`:

- `cascadeDelete_afterExplicitPreDeleteSave_stillRemovesOrphanSentences` — perform `modelContext.save()`, then `modelContext.delete(meeting)`, then `modelContext.save()` again; assert sentences are gone. Documents the FB13640004 failure mode as a regression test so if Apple re-introduces the bug, we catch it locally before shipping.

---

## Updated step scope

| Step | Plan (original) | Plan (with amendments) |
|---|---|---|
| 1 | `Meeting` + `Sentence` entities | + `Sentence.searchableText` field + `SearchTextNormalizer` helper + FB13640004 regression test |
| 2 | `MeetingStore` @ModelActor + DTOs | + `appendSentence` populates `searchableText` via `SearchTextNormalizer.normalize` |
| 8 | Bootstrapper wiring | + `Task.detached` init for `MeetingStore` + main-thread-not-blocked violation test |
| 12 | History search w/ `localizedStandardContains` | + flat `Sentence` fetch + DTO join + on-device 15K-row benchmark; Decision #14 trigger evaluated when benchmark runs |

Steps 3, 4, 5, 6, 7, 9, 10, 11, 13, 14, 15 unchanged.

Plan size grows from ~15 to ~15 steps (no new steps added; existing steps gain 1-2 sub-tasks each).

---

## Pre-flight gate status

| Question | Outcome | Plan impact |
|---|---|---|
| DR-1 (@ModelActor + Sendable) | Confirmed pattern + 1 open Apple bug | Amendments 3 + 4 |
| DR-2 (ShareLink) | Clean, no changes | None |
| DR-3 (Predicate perf + correctness) | Three compounding concerns | Amendments 1 + 2 |
| DR-4 (ScrollView iOS 26) | Confirmed API selection | None (state additions to Step 6) |

**All four researchers ran on 2026-05-16 against Apple Developer Documentation + Apple Developer Forums + WWDC transcripts + Xcode 26 doc index + sqlite.org (for SQLite optimizer + FTS5 facts).**

**Gate disposition:** Plan amendments 1–4 surfaced for user approval. Step 1 does **not** dispatch until the amendments are confirmed or revised.
