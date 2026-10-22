import Testing
@testable import TidemarkCore

@Suite struct TideStyleSuite {
    @Test func labelsAreTheMockupsWords() {
        #expect(TideStyle.level.label == "Water level")
        #expect(TideStyle.week.label == "Over the week")
    }

    @Test func rawValuesAreTheSavedWords() {
        #expect(TideStyle.allCases.map(\.rawValue) == ["level", "week"])
        #expect(TideStyle(rawValue: "week") == .week)
        #expect(TideStyle(rawValue: "nonsense") == nil)
    }

    @Test func theWavesDriftOnlyWhenNothingSaysStop() {
        var gate = WaveGate()
        #expect(!gate.runs)   // no window yet
        gate.windowVisible = true
        #expect(gate.runs)
        let reasons: [(String, (inout WaveGate) -> Void)] = [
            ("window hidden or covered", { $0.windowVisible = false }),
            ("screens asleep", { $0.screensAwake = false }),
            ("session resigned", { $0.sessionActive = false }),
            ("Reduce Motion", { $0.reduceMotion = true }),
            ("a picture", { $0.stillPicture = true }),
            ("an old reading", { $0.isOld = true }),
        ]
        for (name, stop) in reasons {
            var stopped = gate
            stop(&stopped)
            #expect(!stopped.runs, "\(name) should stop the waves")
        }
        // And back: every reverse puts them going again.
        var back = gate
        back.screensAwake = false; back.sessionActive = false; back.windowVisible = false
        back.screensAwake = true; back.sessionActive = true; back.windowVisible = true
        #expect(back.runs)
    }
}
