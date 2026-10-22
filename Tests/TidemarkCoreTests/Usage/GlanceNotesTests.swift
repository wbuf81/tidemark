import Foundation
import Testing
@testable import TidemarkCore

/// What the widget says about a plan, in words (B19, S1.1, S1.5): the week note per state, a window that
/// hasn't started as a real 0%, the VoiceOver sentence, the strip's note and the menu line.
/// The moment is `designNow` (Tue 6 Oct 2026, 11:32 AM, New York); the week resets Fri 9 Oct, 4 AM.
@Suite struct GlanceTests {
    let friday = local(2026, 10, 9, 4)

    func glance(week: Double, resets: Date? = local(2026, 10, 9, 4), session: Double = 0, sessionResets: Date? = nil) -> Glance {
        Glance.make(reading(week: week, weekResetsAt: resets, session: session, sessionResetsAt: sessionResets),
                    history: [], now: designNow)
    }

    func note(_ g: Glance, asOf: Date? = nil) -> Copy.WeekNote {
        Copy.weekNote(g.week, asOf: asOf, now: designNow, formatting: fmt)
    }

    @Test func noteWordsPerState() {
        // Fine, with room: said in words, with the reset.
        #expect(note(glance(week: 40)).text == "~35% would go unused · Fri 4 AM")
        #expect(note(glance(week: 40)).lead == "~35%")
        // Amber: runs out before it resets.
        let amber = note(glance(week: 63))
        #expect(amber.lead == "runs out")
        #expect(amber.text.hasPrefix("runs out Fri 12:2"))
        // Red: out at 100%, nearly out below the red threshold.
        #expect(note(glance(week: 100)).text == "out until Fri 4 AM")
        #expect(note(glance(week: 94)).text == "nearly out · 6% left")
        // On pace with little left over: just when it resets.
        #expect(note(glance(week: 60)).text == "resets Fri 4 AM")
    }

    @Test func oldReadingsSayAsOf() {
        let read = local(2026, 10, 6, 10, 42)
        #expect(note(glance(week: 40), asOf: read).text == "as of 10:42 AM")
        #expect(note(glance(week: 63), asOf: read).text.hasSuffix(" · as of 10:42 AM"))
        #expect(note(glance(week: 63), asOf: read).text.hasPrefix("runs out "))
    }

    // S1.5: nothing used is a real number.
    @Test func notStartedIsZeroNotADash() {
        let g = glance(week: 0, resets: nil)
        #expect(g.session.used == 0 && g.week.used == 0)
        #expect(Copy.glanceNote(g.session, now: designNow, formatting: fmt, capitalized: false) == "not started")
        #expect(note(g).text == "0% week not started")
        #expect(Formatting.percent(g.session.used ?? -1) == "0%")
    }

    // L13: when the 5-hour window is why a plan is amber or red, the sentence says so.
    @Test func voiceOverSaysWhyTheFiveHourWindowIsHot() {
        // Late in its window and filling no faster than it resets: amber at 85%, red at 96%.
        let resets = local(2026, 10, 6, 11, 40)
        func sentence(_ session: Double) -> String {
            Copy.widgetSummary("Personal", glance: glance(week: 40, session: session, sessionResets: resets), now: designNow, formatting: fmt)
        }
        #expect(sentence(85).contains("5-hour window 85 percent, close to full, resets 11:40 AM"))
        #expect(sentence(96).contains("5-hour window 96 percent, nearly full, resets 11:40 AM"))
        #expect(sentence(20).contains("5-hour window 20 percent, resets 11:40 AM"))
    }

    @Test func voiceOverSentence() {
        let g = glance(week: 40, session: 34, sessionResets: local(2026, 10, 6, 16, 20))
        #expect(Copy.widgetSummary("Personal", glance: g, now: designNow, formatting: fmt)
                == "Personal: week 40 percent used, about 35 percent would go unused, resets Friday 4 AM; 5-hour window 34 percent, resets 4:20 PM")
        #expect(Copy.widgetSummary("Personal", glance: g, readAt: local(2026, 10, 6, 10, 42), now: designNow, formatting: fmt)
                .hasSuffix(", reading from 10:42 AM"))
        #expect(Copy.widgetSummary("Harbor Labs", glance: glance(week: 100, session: 0), now: designNow, formatting: fmt)
                == "Harbor Labs: week 100 percent used, out until Friday 4 AM; 5-hour window not started")
        #expect(Copy.widgetSummary("Harbor Labs", glance: nil, now: designNow, formatting: fmt) == "Harbor Labs: no reading yet.")
    }

    @Test func stripNoteNamesItsLimit() {
        let filling = glance(week: 40, session: 84, sessionResets: local(2026, 10, 6, 14, 20))
        #expect(GlanceCopy.stripNote(filling, now: designNow, formatting: fmt) == "5h full 11:57 AM")
        #expect(GlanceCopy.stripNote(glance(week: 63), now: designNow, formatting: fmt).hasPrefix("wk runs out "))
        #expect(GlanceCopy.stripNote(glance(week: 40, session: 100, sessionResets: local(2026, 10, 6, 14, 20)), now: designNow, formatting: fmt)
                == "5h back 2:20 PM")
    }

    @Test func menuLineSaysWhatMatters() {
        #expect(GlanceCopy.menuLine(personal, glance: glance(week: 58, session: 34, sessionResets: local(2026, 10, 6, 16, 20)),
                                    now: designNow, formatting: fmt) == "Personal  week 58% · 5h 34%")
        #expect(GlanceCopy.menuLine(harbor, glance: glance(week: 63), now: designNow, formatting: fmt).hasPrefix("Harbor Labs  runs out "))
        #expect(GlanceCopy.menuLine(harbor, glance: nil) == "Harbor Labs")
    }

    // H2: the same reading gives the same words in Glance and in the Usage detail.
    @Test func glanceAndDetailAgreeAboutTheFiveHourWindow() throws {
        // 34% used 12 minutes into the window: too early for either to forecast a fill time.
        let early = reading(week: 10, weekResetsAt: friday, session: 34,
                            sessionResetsAt: designNow.addingTimeInterval(5 * 3600 - 12 * 60))
        let g = Glance.make(early, history: [], now: designNow)
        let d = try #require(LimitDetails.make(LimitID(org: "personal", kind: .session), reading: early, history: [],
                                               now: designNow, calendar: newYork))
        #expect(g.session.tone == .green)
        #expect(Copy.glanceNote(g.session, now: designNow, formatting: fmt, capitalized: true).hasPrefix("↺"))
        #expect(d.runsOutAt == nil && d.runsOut == nil && d.lockedFromX == nil)
        let stats = UsageCopy.stats(d, now: designNow, formatting: fmt)
        #expect(!stats.contains { $0.label.hasPrefix("Runs out") })

        // An hour in at the same pace the fill is forecast by both, at the same time.
        let later = reading(week: 10, weekResetsAt: friday, session: 80,
                            sessionResetsAt: designNow.addingTimeInterval(4 * 3600))
        let g2 = Glance.make(later, history: [], now: designNow)
        let d2 = try #require(LimitDetails.make(LimitID(org: "personal", kind: .session), reading: later, history: [],
                                                now: designNow, calendar: newYork))
        guard case .fullAt(let fullAt) = g2.session.note else { Issue.record("no fill time"); return }
        #expect(d2.runsOutAt == fullAt)
    }

    // H1: the week note never shrinks to its bold lead alone; every shorter form keeps the meaning and the time.
    @Test func everyShortFormKeepsItsMeaningAndTime() {
        func forms(_ g: Glance, asOf: Date? = nil) -> [Copy.WeekNote] {
            Copy.weekNoteForms(g.week, asOf: asOf, now: designNow, formatting: fmt)
        }
        let unused = forms(glance(week: 40)).map(\.text)
        #expect(unused == ["~35% would go unused · Fri 4 AM", "~35% would go unused", "~35% unused"])
        #expect(forms(glance(week: 63)).map(\.text).last == "runs out Fri")
        #expect(forms(glance(week: 63)).map(\.text).first!.hasPrefix("runs out Fri 12:2"))
        #expect(forms(glance(week: 100)).map(\.text) == ["out until Fri 4 AM", "out until Fri"])
        #expect(forms(glance(week: 94)).map(\.text) == ["nearly out · 6% left", "6% left"])
        #expect(forms(glance(week: 60)).map(\.text) == ["resets Fri 4 AM", "resets Fri"])
        #expect(forms(glance(week: 0, resets: nil)).map(\.text) == ["0% week not started", "week not started", "not started"])
        for week in [0.0, 40, 60, 63, 94, 100] {
            let all = forms(glance(week: week, resets: week == 0 ? nil : friday))
            #expect(all.map { $0.text.count } == all.map { $0.text.count }.sorted(by: >))
            for form in all { #expect(!form.rest.isEmpty && form.text != form.lead) }
        }
        // An old, urgent reading keeps its words and says so at every length.
        let read = local(2026, 10, 6, 10, 42)
        for form in forms(glance(week: 63), asOf: read) { #expect(form.text.hasPrefix("runs out ") && form.text.hasSuffix("as of 10:42 AM")) }
        // A day far away carries its date.
        let far = Copy.weekNoteForms(glance(week: 100, resets: local(2026, 10, 23, 4)).week, now: designNow.addingTimeInterval(-3 * 86400), formatting: fmt)
        #expect(far.map(\.text) == ["out until Fri 23 Oct, 4 AM", "out until Fri 23 Oct"])
    }

    // The shortest form of every note, on any weekday within five days, fits the least room an M slot gives it, so no M card
    // clips "~20% unu…" (the M threshold sits where the widest short form, "out until Wed", fits).
    @Test func theShortestNoteNeverClipsAtTheSmallestMSlot() {
        let room = GlanceLayout.noteWidth(size: .m, slot: WidgetSizing.slotM)
        let size = GlanceLayout.noteFontSize(.m)
        for day in 7...11 { for week in [0.0, 40, 60, 63, 94, 100] {
            let g = glance(week: week, resets: week == 0 ? nil : local(2026, 10, day, 4))
            let last = Copy.weekNoteForms(g.week, now: designNow, formatting: fmt).last!
            #expect(last.estimatedWidth(fontSize: size) <= room, "\(week) on \(day) Oct: \(last.text) in \(room)")
        } }
    }

    // H1: at every layout the default 280 pt widget lands on, the note that fits still says what and when.
    @Test func theNoteThatFitsAtTheDefaultWidthKeepsItsMeaning() {
        let moods: [CodeMood?] = [nil, .idle, .tool]
        var seen = Set<WidgetSize>()
        for orgs in 1...3 { for advice in [false, true] { for mood in moods {
            let layout = WidgetSizing.layout(width: 280, orgs: orgs, advice: advice, week: false, status: mood)
            seen.insert(layout.size)
            guard layout.size >= .m else { continue }
            let room = GlanceLayout.noteWidth(size: layout.size, slot: layout.slot)
            for (week, expect) in [(40.0, "unused"), (63, "runs out Fri"), (100, "out until Fri"), (94, "left"), (60, "resets Fri")] {
                let g = glance(week: week)
                let size = GlanceLayout.noteFontSize(layout.size)
                let picked = Copy.fitting(Copy.weekNoteForms(g.week, now: designNow, formatting: fmt), width: room, fontSize: size)
                #expect(picked.text.contains(expect), "\(layout.size) \(week): \(picked.text)")
                #expect(picked.text != picked.lead)
                // And the form picked really fits the room, so nothing is cut off mid-word.
                #expect(picked.estimatedWidth(fontSize: size) <= room, "\(layout.size) \(week): \(picked.text) in \(room)")
            }
        } } }
        #expect(seen.isSuperset(of: [.s, .m]))
    }
}

@Suite struct GlanceMessageTests {
    @Test func problemWords() {
        let cases: [(RefreshProblem, String, String, String)] = [
            (.offline, "Can’t reach claude.ai", "No connection · trying again every minute", "Offline"),
            (.refused, "claude.ai refused the request", "Access refused · trying again soon", "Error"),
            (.http(503), "claude.ai answered with an error (503)", "Trying again soon", "Error"),
            (.blocked, "Blocked by a bot check", "claude.ai’s bot check stopped Tidemark", "Blocked"),
            (.changedShape(details: ""), "claude.ai changed how it answers", "Tidemark can’t read its usage page yet", "Error"),
            (.noWeeklyLimit, "This account has no weekly limit", "claude.ai shows no weekly limit for this sign-in", "No limit"),
        ]
        for (problem, title, detail, narrow) in cases {
            let words = GlanceCopy.problem(problem)
            #expect(words.title == title)
            #expect(words.detail == detail)
            #expect(words.narrow == narrow)
        }
        #expect(GlanceCopy.problem(.offline).action == "Retry")
        #expect(GlanceCopy.problem(.offline).sentence == "Can’t reach claude.ai. No connection · trying again every minute")
    }

    @Test func theOtherMessages() {
        #expect(GlanceCopy.signedOut.title == "Sign in to claude.ai" && GlanceCopy.signedOut.action == "Sign in…")
        #expect(GlanceCopy.loading.title == "Loading usage…" && GlanceCopy.loading.narrow == "Loading…")
        #expect(GlanceCopy.noPlans.title == "No plans on this account")
        #expect(GlanceCopy.noPlans.detail == "claude.ai shows no usage for this sign-in")
        #expect(["Offline", "Signed out", "Blocked", "Error", "Loading…"].allSatisfy { $0.count <= 11 })
    }

    @Test func notchWordsAreTheSameShortWords() {
        #expect(GlanceCopy.notchWord(signedIn: false, problem: nil, loading: false) == "Sign in")
        #expect(GlanceCopy.notchWord(signedIn: true, problem: .offline, loading: false) == "Offline")
        #expect(GlanceCopy.notchWord(signedIn: true, problem: .blocked, loading: false) == "Blocked")
        #expect(GlanceCopy.notchWord(signedIn: true, problem: nil, loading: true) == "Loading…")
        #expect(GlanceCopy.notchWord(signedIn: true, problem: nil, loading: false) == nil)
        // M1, L3: no plans says so instead of loading for good; no weekly limit has its own word.
        #expect(GlanceCopy.notchWord(signedIn: true, problem: nil, loading: true, message: GlanceCopy.noPlans) == "No plans")
        #expect(GlanceCopy.notchWord(signedIn: true, problem: nil, loading: true, message: GlanceCopy.loading) == "Loading…")
        #expect(GlanceCopy.notchWord(signedIn: true, problem: .noWeeklyLimit, loading: false) == "No limit")
        #expect(GlanceCopy.notchWord(signedIn: true, problem: .refused, loading: false) == "Error")
    }

    @Test func readAgeAges() {
        let read = local(2026, 10, 6, 9, 14)
        func age(_ seconds: TimeInterval) -> String {
            GlanceCopy.readAge(seconds: seconds, at: read, now: read.addingTimeInterval(seconds), formatting: fmt)
        }
        #expect(age(5) == "Read just now")
        #expect(age(59) == "Read just now")
        #expect(age(120) == "Read 2 min ago")
        #expect(age(3600) == "Read 1 h ago")
        #expect(age(5 * 3600 + 59 * 60) == "Read 5 h ago")
        #expect(age(6 * 3600) == "Read at 9:14 AM")
        #expect(age(30 * 3600) == "Read at Tue 9:14 AM")
    }
}
