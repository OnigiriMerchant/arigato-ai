//
//  DebugMeetingSeeder.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/30.
//

#if DEBUG
    import Foundation

    /// DEBUG-only developer tool that fills the SwiftData store with a small
    /// corpus of realistic Japanese↔English business meetings so the history
    /// list, detail view, copy / share / export, and swipe-to-delete can be
    /// evaluated against representative data in the simulator.
    ///
    /// > Important: This entire type is compiled **only** under `#if DEBUG`.
    /// It must never ship in a Release build. The companion Settings affordance
    /// (the "Developer" section in ``SettingsView``) is likewise `#if DEBUG`
    /// gated, and Release-configuration builds are verified to contain zero
    /// references to this type.
    ///
    /// ## Design
    /// A stateless namespace (a `nonisolated enum`, no cases). All seeding
    /// goes through ``MeetingStore`` — the single authoritative write path —
    /// so `searchableText` is normalized exactly as production sentences are.
    /// No `Meeting` / `Sentence` `@Model` instances are ever constructed
    /// directly here.
    ///
    /// ## Not idempotent
    /// Repeat seeding **stacks** data (it does not clear first). This is the
    /// deliberately safe choice for dev tooling: it never destroys real
    /// recordings the developer may have captured. Use the "Clear all sample
    /// data" Settings button (which calls ``MeetingStore/deleteAllMeetings()``)
    /// to reset.
    enum DebugMeetingSeeder {
        /// One transcript line in a sample meeting.
        ///
        /// `sourceLanguage` is the ISO 639-1 tag of `sourceText` (`"ja"` or
        /// `"en"`). When `"ja"`, `sourceText` is Japanese and `translatedText`
        /// is its English rendering; when `"en"`, the roles are reversed. This
        /// mirrors ``MeetingStore/appendSentence(meetingID:timestamp:sourceLanguage:sourceText:translatedText:sourceSegmentID:)``'s
        /// contract.
        struct SampleLine {
            /// ISO 639-1 tag of `sourceText` — `"ja"` or `"en"`.
            let sourceLanguage: String
            /// The original-language line (Japanese when `sourceLanguage == "ja"`).
            let sourceText: String
            /// The opposite-language rendering of `sourceText`.
            let translatedText: String
        }

        /// One sample meeting: a title, when it started relative to now, how
        /// long it ran, and its ordered transcript lines.
        struct SampleMeeting {
            /// Display title (becomes ``Meeting/title``).
            let title: String
            /// Offset from `Date.now` at seed time to the meeting's start.
            /// **Negative** — the meeting started in the past.
            let startOffsetFromNow: TimeInterval
            /// Wall-clock duration of the meeting. Sentence timestamps are
            /// spread strictly-increasing across `[startedAt, endedAt]`.
            let duration: TimeInterval
            /// Ordered transcript lines, oldest first.
            let lines: [SampleLine]
        }

        /// Seeds the three Decision-B sample meetings into `store`.
        ///
        /// For each ``SampleMeeting``: computes `startedAt = .now +
        /// startOffsetFromNow` and `endedAt = startedAt + duration`, calls
        /// ``MeetingStore/startMeeting(startedAt:title:)``, appends each line
        /// via ``MeetingStore/appendSentence(meetingID:timestamp:sourceLanguage:sourceText:translatedText:sourceSegmentID:)``
        /// with a strictly-increasing timestamp interpolated linearly across
        /// the meeting's span (and a fresh `UUID()` per `sourceSegmentID`),
        /// then calls ``MeetingStore/endMeeting(meetingID:endedAt:)``.
        ///
        /// ## Scheduling assumption (Concurrency design discipline)
        /// Inserts are sequential and `await`ed against the `@ModelActor`
        /// store; this method **assumes no concurrent invocation**. Because
        /// seeding is intentionally **not** idempotent (it never clears
        /// first), concurrent invocation would simply produce duplicate
        /// meeting sets — there is no dedupe and no corruption, just stacked
        /// data. The caller **must** serialize invocations; the production
        /// caller (``SettingsViewModel/seedSampleData()``) does so via its
        /// `isSeeding` re-entry guard, and the Settings buttons are
        /// `.disabled` while any busy flag is set.
        ///
        /// A forced-overlap concurrency violation test is **deliberately
        /// skipped** for this throwaway DEBUG tooling per the user's
        /// option-(b) decision: the UI-level `.disabled` gating plus the
        /// `isSeeding` guard are the defenses, and the only failure mode
        /// (duplicate data) is harmless for a dev seeder. See the
        /// `docs/V3_BACKLOG.md` entry "DEBUG seeder — concurrency violation
        /// test deliberately skipped" for the trigger to revisit.
        ///
        /// - Parameter store: The actor-backed persistence to seed into.
        /// - Throws: Re-throws anything ``MeetingStore`` throws (save errors,
        ///   `meetingNotFound` — though the latter cannot occur here since the
        ///   identifier comes straight from `startMeeting`).
        static func seed(into store: MeetingStore) async throws {
            let now = Date.now
            for sample in samples {
                let startedAt = now.addingTimeInterval(sample.startOffsetFromNow)
                let endedAt = startedAt.addingTimeInterval(sample.duration)

                let meetingID = try await store.startMeeting(
                    startedAt: startedAt,
                    title: sample.title
                )

                for (index, line) in sample.lines.enumerated() {
                    try await store.appendSentence(
                        meetingID: meetingID,
                        timestamp: timestamp(
                            forLineAt: index,
                            of: sample.lines.count,
                            startedAt: startedAt,
                            duration: sample.duration
                        ),
                        sourceLanguage: line.sourceLanguage,
                        sourceText: line.sourceText,
                        translatedText: line.translatedText,
                        sourceSegmentID: UUID()
                    )
                }

                try await store.endMeeting(meetingID: meetingID, endedAt: endedAt)
            }
        }

        /// Interpolates a strictly-increasing timestamp for the line at
        /// `index` (0-based) of `count` lines, spread linearly across
        /// `[startedAt, startedAt + duration]`.
        ///
        /// Guards the `count == 1` divide-by-zero edge: a single-line meeting
        /// places its one sentence at `startedAt`. For `count > 1`, line `i`
        /// lands at `startedAt + duration * i / (count - 1)`, so the first
        /// line is at the start and the last at the end, strictly increasing
        /// in between.
        private static func timestamp(
            forLineAt index: Int,
            of count: Int,
            startedAt: Date,
            duration: TimeInterval
        ) -> Date {
            guard count > 1 else { return startedAt }
            let fraction = TimeInterval(index) / TimeInterval(count - 1)
            return startedAt.addingTimeInterval(duration * fraction)
        }

        /// The Decision-B / Decision-D corpus: exactly three coherent,
        /// on-theme bilingual business meetings.
        ///
        /// Direction is mixed per-line via ``SampleLine/sourceLanguage``.
        /// Several Japanese lines carry hiragana so the
        /// ``SearchTextNormalizer`` hiragana→katakana folding path is
        /// genuinely exercised by the seeded `searchableText`.
        static let samples: [SampleMeeting] = [
            // M1 — Sprint planning sync. ~2h ago, ~5 min, 8 lines, JA→EN dominant.
            SampleMeeting(
                title: "Sprint planning sync",
                startOffsetFromNow: -2 * 60 * 60,
                duration: 5 * 60,
                lines: [
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "お疲れ様です。本日のスプリント計画を始めさせていただきます。",
                        translatedText: "Thanks for joining. Let's get started on today's sprint planning."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "まず、前回のスプリントで残ったタスクを確認しましょう。",
                        translatedText: "First, let's go over the tasks left over from the last sprint."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "The login screen redesign is still in review. I can wrap it up by Wednesday.",
                        translatedText: "ログイン画面のリデザインはまだレビュー中です。水曜日までには仕上げられます。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "承知しました。では、それを今回のスプリントに引き継ぎます。",
                        translatedText: "Understood. Then we'll carry that over into this sprint."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "新しい通知機能の見積もりはどのくらいになりそうですか。",
                        translatedText: "Roughly how much do you estimate the new notification feature will take?"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "I'd put it at five story points. The backend API is the bigger unknown.",
                        translatedText: "5ストーリーポイントくらいだと思います。バックエンドのAPIの方が不確実性が大きいです。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "わかりました。リスクの高い部分から着手するようにしましょう。",
                        translatedText: "Got it. Let's tackle the higher-risk part first."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "それでは、本日はここまでとします。よろしくお願いいたします。",
                        translatedText: "Alright, let's wrap up here for today. Thank you, everyone."
                    ),
                ]
            ),
            // M2 — Q3 partnership review with Tokyo. ~2 days ago, ~20 min,
            // 22 lines, mixed direction.
            SampleMeeting(
                title: "Q3 partnership review with Tokyo",
                startOffsetFromNow: -2 * 24 * 60 * 60,
                duration: 20 * 60,
                lines: [
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "本日はお時間をいただき、誠にありがとうございます。",
                        translatedText: "Thank you very much for making the time today."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Of course. We're glad to finally review the third-quarter numbers together.",
                        translatedText: "もちろんです。第3四半期の数字をようやく一緒に確認できて嬉しく思います。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "それでは、まず売上の概況からご説明いたします。",
                        translatedText: "Then allow me to start with an overview of the sales figures."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "第3四半期の売上は、前年同期比で12パーセント増加いたしました。",
                        translatedText: "Third-quarter revenue grew 12 percent compared with the same period last year."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "That's encouraging. Which product line drove most of that growth?",
                        translatedText: "それは心強いですね。その成長の大半はどの製品ラインが牽引したのでしょうか。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "主に、新しい検査装置の保守契約が伸びております。",
                        translatedText: "It was mainly driven by growth in maintenance contracts for the new testing equipment."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "既存のお客様からの追加発注も堅調に推移しています。",
                        translatedText: "Follow-on orders from existing customers have also remained solid."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Good to hear. On our side, the integration work took a bit longer than planned.",
                        translatedText: "それは何よりです。こちらでは、統合作業が当初の計画より少し時間がかかりました。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "その点について、もう少し詳しくお聞かせいただけますか。",
                        translatedText: "Could you tell us a little more about that point?"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "The data migration had more edge cases than we expected, but it's stable now.",
                        translatedText: "データ移行で想定より多くのエッジケースがありましたが、今は安定しています。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "ご対応いただき、ありがとうございます。安心いたしました。",
                        translatedText: "Thank you for handling that. We're reassured to hear it."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "次に、第4四半期の共同マーケティング施策についてご相談させてください。",
                        translatedText: "Next, we'd like to discuss the joint marketing initiatives for the fourth quarter."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "We were thinking of co-hosting a webinar for hospital lab directors in November.",
                        translatedText: "11月に、病院の検査室長向けの共催ウェビナーを開催してはどうかと考えていました。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "良い案だと思います。弊社の技術担当も登壇させたいと考えております。",
                        translatedText: "I think that's a great idea. We'd like to have one of our technical leads present as well."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Perfect. Could you send over a few candidate dates by the end of next week?",
                        translatedText: "完璧です。来週末までに候補日をいくつか送っていただけますか。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "かしこまりました。明日中に日程の素案をお送りいたします。",
                        translatedText: "Certainly. I'll send over a draft schedule by the end of tomorrow."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "契約更新の件についても、本日確認させていただけますでしょうか。",
                        translatedText: "May we also confirm the matter of the contract renewal today?"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Yes. Our legal team has reviewed the draft and has only minor comments.",
                        translatedText: "はい。当社の法務チームがドラフトを確認し、軽微なコメントのみとなっています。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "それでは、修正点をいただき次第、最終版をご用意いたします。",
                        translatedText: "Then once we receive the revisions, we'll prepare the final version."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Sounds good. We'd like to have everything signed before the holidays.",
                        translatedText: "それで結構です。年末の休暇前にすべて署名を済ませたいと考えています。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "承知いたしました。スケジュールに余裕を持って進めてまいります。",
                        translatedText: "Understood. We'll proceed with enough room in the schedule."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "本日は実りある議論ができました。引き続きよろしくお願いいたします。",
                        translatedText: "We had a productive discussion today. We look forward to continuing to work with you."
                    ),
                ]
            ),
            // M3 — Engineering all-hands / roadmap. ~9 days ago, ~40 min,
            // 40 lines, mixed leaning EN→JA.
            SampleMeeting(
                title: "Engineering all-hands / roadmap",
                startOffsetFromNow: -9 * 24 * 60 * 60,
                duration: 40 * 60,
                lines: [
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Good morning, everyone. Thanks for joining the engineering all-hands.",
                        translatedText: "皆さん、おはようございます。エンジニアリング全体会議にご参加いただきありがとうございます。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Today I want to walk through the roadmap for the next two quarters.",
                        translatedText: "本日は、これから2四半期分のロードマップについてご説明したいと思います。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "その前に、先月リリースした新機能の状況を共有させてください。",
                        translatedText: "Before that, let me share the status of the new feature we released last month."
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "おかげさまで、リアルタイム翻訳機能は大きな不具合なく稼働しています。",
                        translatedText: "I'm glad to report the real-time translation feature is running without any major issues."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "That's a great result. The crash rate stayed well under our target.",
                        translatedText: "素晴らしい結果です。クラッシュ率は目標値を十分に下回ったままでした。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Let's start with the first theme: improving on-device latency.",
                        translatedText: "では最初のテーマ、オンデバイスのレイテンシ改善から始めましょう。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "現在、音声認識から翻訳表示までの遅延はどのくらいでしょうか。",
                        translatedText: "Right now, how much latency is there from speech recognition to displaying the translation?"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "On the latest devices we're seeing around four hundred milliseconds end to end.",
                        translatedText: "最新の端末では、エンドツーエンドでおよそ400ミリ秒となっています。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "We'd like to bring that down below three hundred by the end of Q3.",
                        translatedText: "第3四半期末までに、それを300ミリ秒以下に下げたいと考えています。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "モデルの量子化を進めれば、ある程度は短縮できると思います。",
                        translatedText: "I think we can cut it down somewhat if we push further on quantizing the model."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Agreed. Let's prototype that and measure before committing to a target.",
                        translatedText: "賛成です。目標を確定する前に、まず試作して計測しましょう。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "計測用のベンチマークは、私の方で来週までに用意します。",
                        translatedText: "I'll have the measurement benchmark ready on my end by next week."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "The second theme is stability. We still see occasional audio glitches on older phones.",
                        translatedText: "2つ目のテーマは安定性です。古い端末では今でもまれに音声の乱れが発生します。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "その不具合は、特定の機種で再現しやすいのでしょうか。",
                        translatedText: "Is that glitch easier to reproduce on particular models?"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Mostly on two-generation-old hardware. We've reproduced it in the lab.",
                        translatedText: "主に2世代前のハードウェアです。社内で再現できています。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "I'll assign a small task force to that this sprint.",
                        translatedText: "今スプリントで、その対応に小さなタスクフォースを割り当てます。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "ありがとうございます。検証用の端末はこちらで手配します。",
                        translatedText: "Thank you. We'll arrange the test devices on our side."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Third, let's talk about the offline summary feature requests we've been getting.",
                        translatedText: "3つ目に、最近いただいているオフライン要約機能の要望について話しましょう。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "要約機能は需要が高いですが、端末上のメモリが課題になりそうです。",
                        translatedText: "Demand for the summary feature is high, but on-device memory looks like it'll be a challenge."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Right. Let's scope a smaller model and see if quality holds up.",
                        translatedText: "そうですね。より小さなモデルを検討して、品質が維持できるか見てみましょう。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "プライバシーの観点からも、すべて端末内で完結させたいところです。",
                        translatedText: "From a privacy standpoint as well, we'd want to keep everything entirely on the device."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Absolutely. On-device processing stays a hard requirement for this product.",
                        translatedText: "もちろんです。オンデバイス処理は、この製品にとって譲れない要件です。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Let's move to hiring. We have two open positions on the platform team.",
                        translatedText: "次は採用についてです。プラットフォームチームに2つの空きポジションがあります。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "音声処理の経験がある方を優先的に探していただけると助かります。",
                        translatedText: "It would help if you could prioritize finding candidates with audio-processing experience."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Noted. I'll work with the recruiting team to refine the job description.",
                        translatedText: "承知しました。採用チームと協力して、募集要項を見直します。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "面接にはぜひ現場のエンジニアも参加させてください。",
                        translatedText: "Please be sure to include hands-on engineers in the interviews as well."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Good idea. Peer interviews tend to give us the most signal.",
                        translatedText: "良い考えです。同僚による面接が最も判断材料になる傾向があります。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Next, a quick note on technical debt. The audio pipeline needs refactoring.",
                        translatedText: "次に、技術的負債について簡単に。音声パイプラインはリファクタリングが必要です。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "リファクタリングのために、各スプリントで二割ほど時間を確保しませんか。",
                        translatedText: "How about we set aside about twenty percent of each sprint for refactoring?"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "That's reasonable. Let's formalize a twenty-percent allocation for cleanup.",
                        translatedText: "妥当ですね。クリーンアップに2割を割り当てることを正式に決めましょう。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "テストカバレッジについても、目標を設定したほうが良いと思います。",
                        translatedText: "I think we should set a target for test coverage as well."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Agreed. Let's aim for eighty percent on the core modules first.",
                        translatedText: "賛成です。まずはコアモジュールで80パーセントを目指しましょう。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Before we wrap, are there any questions from the team?",
                        translatedText: "終わる前に、チームから何か質問はありますか。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "ロードマップの優先順位は、どのくらいの頻度で見直す予定でしょうか。",
                        translatedText: "How often do you plan to revisit the roadmap priorities?"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "We'll revisit priorities at the end of every sprint and adjust as needed.",
                        translatedText: "各スプリントの終わりに優先順位を見直し、必要に応じて調整します。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "ドキュメントはどこで共有されますか。後ほど見返したいです。",
                        translatedText: "Where will the documents be shared? I'd like to review them later."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "I'll post the slides and notes in the shared channel right after this.",
                        translatedText: "この後すぐに、スライドとメモを共有チャンネルに投稿します。"
                    ),
                    SampleLine(
                        sourceLanguage: "ja",
                        sourceText: "ありがとうございます。とても分かりやすい説明でした。",
                        translatedText: "Thank you. That was a very clear explanation."
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "Thank you all for the great questions and the hard work this quarter.",
                        translatedText: "皆さん、素晴らしい質問と今四半期の努力に感謝します。"
                    ),
                    SampleLine(
                        sourceLanguage: "en",
                        sourceText: "That wraps up the all-hands. Let's keep the momentum going.",
                        translatedText: "以上で全体会議を終わります。この勢いを保っていきましょう。"
                    ),
                ]
            ),
        ]
    }
#endif
