import Testing
@testable import TidemarkCore

@Suite struct CodeMoodCopyTests {
    @Test func wordsForEveryMood() {
        #expect(CodeMood.idle.word == "Idle")
        #expect(CodeMood.thinking.word == "Thinking")
        #expect(CodeMood.tool.word == "Working")
        #expect(CodeMood.permission.word == "Needs you")
        #expect(CodeMood.done.word == "Done")
    }
}
