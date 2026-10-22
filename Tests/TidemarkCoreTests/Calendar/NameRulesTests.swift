import Foundation
import Testing
@testable import TidemarkCore

@Suite struct NameRulesTests {
    private func session(_ id: String = "sess-tide-0001", title: String? = nil, first: String? = nil, root: String = "/Users/you/tide-tables",
                         folders: [String] = [], origin: SessionOrigin = .claudeCode) -> CalendarSession {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return CalendarSession(id: id, origin: origin, title: title, firstMessage: first, root: root, folders: folders,
                               blocks: [Block(start: start, end: start.addingTimeInterval(600))], lastActivity: start)
    }

    private func book(sessions: [String: NameEntry] = [:], projects: [String: NameEntry] = [:], folders: [String: NameEntry] = [:],
                      projectFolders: [String: String] = [:]) -> NameBook {
        var b = NameBook()
        b.sessions = sessions
        b.projects = projects
        b.folders = folders
        b.projectFolders = projectFolders
        return b
    }

    @Test func exactNameBeatsARule() {
        let b = book(sessions: ["Email Brief*": NameEntry(name: "Daily brief"), "Email Brief v3": NameEntry(name: "Brief three")])
        #expect(b.shown(.sessions, "Email Brief v3") == "Brief three")
        #expect(b.shown(.sessions, "Email Brief v2") == "Daily brief")
        #expect(b.shown(.sessions, "Other work") == "Other work")
    }

    @Test func theLongestRuleWins() {
        let b = book(sessions: ["Email*": NameEntry(name: "Mail"), "Email Brief*": NameEntry(name: "Daily brief")])
        #expect(b.shown(.sessions, "Email Brief Daily") == "Daily brief")
        #expect(b.shown(.sessions, "Email triage") == "Mail")
    }

    @Test func ownFieldsSitOnTopOfTheRule() {
        let rule = NameEntry(name: "Daily brief", tags: ["mail"], project: "Harbor Labs")
        let b = book(sessions: ["Email Brief*": rule, "Email Brief v3": NameEntry(tags: ["work"])])
        let e = b.entry(.sessions, "Email Brief v3")
        #expect(e.name == "Daily brief")
        #expect(e.project == "Harbor Labs")
        #expect(e.tags == ["work"])
        #expect(b.entry(.sessions, "Email Brief*") == rule)
    }

    @Test func myTitleAndTags() {
        let b = book(sessions: ["Email Brief*": NameEntry(name: "Daily brief", tags: ["mail"])],
                     projects: ["tide-tables": NameEntry(tags: ["work", "mail"])])
        let s = session(title: "Email Brief v1")
        #expect(b.label(s) == "Email Brief v1")
        #expect(b.tags(s, project: "tide-tables") == ["mail", "work"])
        #expect(b.label(session(title: nil, first: nil)) == "Untitled session")
        #expect(b.label(session(title: nil, first: "  fix   the tide chart rounding in the harbor  ")) == "fix the tide chart rounding…")
    }

    @Test func projectNames() {
        let b = book(projectFolders: ["lighthouse-api": "Lighthouse API"])
        #expect(b.projectName(root: "/Users/you/lighthouse-api/") == "Lighthouse API")
        #expect(b.projectName(root: "/Users/you/tide-tables") == "tide-tables")
        #expect(b.projectName(root: "project:Harbor Labs") == "Harbor Labs")
        #expect(b.projectName(root: "Cowork") == "Cowork")
    }

    @Test func intoAProjectByEitherName() throws {
        var b = book(projectFolders: ["tide-tables": "Tides"])
        b.projects["Tides"] = NameEntry(name: "Tide Tables")
        b.sessions["Email Brief*"] = NameEntry(project: "Tides")
        let cowork = session("sess-cow-1", title: "Email Brief 1", root: "Cowork", origin: .cowork)
        let code = session("sess-tide-1", title: "Build", root: "/Users/you/tide-tables")
        var out = NameBook.assignProjects([code, cowork], names: b)
        #expect(out[1].root == "/Users/you/tide-tables")
        #expect(out[1].project == "Tides")
        #expect(out[1].session.root == "Cowork")
        b.sessions["Email Brief*"] = NameEntry(project: "Tide Tables")
        out = NameBook.assignProjects([code, cowork], names: b)
        #expect(out[1].root == "/Users/you/tide-tables")
    }

    @Test func intoANewProjectAndBack() {
        var b = book()
        b.sessions["Email Brief*"] = NameEntry(project: "Harbor Labs")
        let s = session(title: "Email Brief 1", root: "Cowork", origin: .cowork)
        var out = NameBook.assignProjects([s], names: b)
        #expect(out[0].root == "project:Harbor Labs")
        #expect(out[0].project == "Harbor Labs")
        b.sessions = [:]
        out = NameBook.assignProjects([s], names: b)
        #expect(out[0].root == "Cowork")
        #expect(out[0].project == "Cowork")
    }

    @Test func byFolderButNotTheSharedOne() {
        var b = book(folders: ["Field Notes": NameEntry(project: "Lighthouse Co"), "Claude": NameEntry(project: "Harbor Labs")])
        let a = session(root: "Cowork", folders: ["Claude", "Field Notes"], origin: .cowork)
        #expect(NameBook.assignProjects([a], names: b)[0].project == "Lighthouse Co")
        let onlyShared = session(root: "Cowork", folders: ["Claude"], origin: .cowork)
        #expect(NameBook.assignProjects([onlyShared], names: b)[0].project == "Cowork")
        b.folders["Claude"] = nil
        #expect(b.assignedProject(onlyShared) == nil)
    }

    @Test func aWholeProjectMoves() {
        let b = book(projects: ["tide-tables": NameEntry(project: "Other work")])
        let a = session("a", root: "/Users/you/tide-tables")
        let c = session("c", root: "/Users/you/field-notes")
        let out = NameBook.assignProjects([a, c], names: b)
        #expect(out[0].root == "project:Other work")
        #expect(out[0].project == "Other work")
        #expect(out[0].session.root == "/Users/you/tide-tables")
        #expect(out[1].root == "/Users/you/field-notes")
        #expect(out[1].project == "field-notes")
    }

    @Test func theTitleBeatsTheFolder() {
        let b = book(sessions: ["Email Brief*": NameEntry(project: "Harbor Labs")], folders: ["Field Notes": NameEntry(project: "Lighthouse Co")])
        let s = session(title: "Email Brief 2", root: "Cowork", folders: ["Field Notes"], origin: .cowork)
        #expect(b.assignedProject(s) == "Harbor Labs")
    }

    @Test func onlyTheFieldsSentChange() throws {
        var b = book(sessions: ["Email Brief 1": NameEntry(name: "Daily brief", tags: ["mail"], project: "Harbor Labs")])
        b = try b.apply(NameChange(kind: .sessions, key: "Email Brief 1", tags: ["Work", "work", "  mail  ", "", "WORK"]))
        let e = b.sessions["Email Brief 1"]
        #expect(e?.name == "Daily brief")
        #expect(e?.project == "Harbor Labs")
        #expect(e?.tags == ["Work", "mail"])
        b = try b.apply(NameChange(kind: .sessions, key: "Email Brief 1", name: .some("Email Brief 1")))
        #expect(b.sessions["Email Brief 1"]?.name == nil)
        b = try b.apply(NameChange(kind: .sessions, key: "Email Brief 1", tags: [], project: .some(nil)))
        #expect(b.sessions["Email Brief 1"] == nil)
        let long = try NameBook().apply(NameChange(kind: .sessions, key: "x", name: .some(String(repeating: "n", count: 300)),
                                                   tags: (0..<30).map { "t\($0)" } + [String(repeating: "g", count: 60)]))
        #expect(long.sessions["x"]?.name?.count == 200)
        #expect(long.sessions["x"]?.tags?.count == 20)
    }

    @Test func aProjectCanMoveAndHideTitles() throws {
        var b = try NameBook().apply(NameChange(kind: .projects, key: "tide-tables", name: .some("Tide Tables"), tags: ["work"],
                                                project: .some("Other work"), hideTitles: true))
        let e = b.projects["tide-tables"]
        #expect(e == NameEntry(name: "Tide Tables", tags: ["work"], project: "Other work", hideTitles: true))
        #expect(b.hidesTitles(project: "tide-tables"))
        b = try b.apply(NameChange(kind: .projects, key: "tide-tables", name: .some(nil), tags: [], project: .some(nil), hideTitles: false))
        #expect(b.projects.isEmpty)
        #expect(!b.hidesTitles(project: "tide-tables"))
    }

    @Test func foldersTakeOnlyAProject() throws {
        var b = try NameBook().apply(NameChange(kind: .folders, key: "Field Notes", name: .some("Notes"), tags: ["x"], project: .some("Harbor Labs"), hideTitles: true))
        #expect(b.folders["Field Notes"] == NameEntry(project: "Harbor Labs"))
        b = try b.apply(NameChange(kind: .sessions, key: "Email*", name: .some("Mail")))
        #expect(b.sessions["Email*"]?.name == "Mail")
    }

    @Test func aTitleIsKeptExactly() throws {
        let b = try NameBook().apply(NameChange(kind: .sessions, key: "  Fix  the  tide  ", name: .some("Tides")))
        #expect(b.sessions["Fix  the  tide"]?.name == "Tides")
    }

    @Test func badChangesThrow() {
        let book = NameBook()
        #expect(throws: NameBookError.badKey) { try book.apply(NameChange(kind: .sessions, key: "   ", name: .some("a"))) }
        #expect(throws: NameBookError.badKey) { try book.apply(NameChange(kind: .sessions, key: "*", name: .some("a"))) }
        #expect(throws: NameBookError.badKey) { try book.apply(NameChange(kind: .projects, key: String(repeating: "k", count: 501))) }
    }

    @Test func secretNameWholeWordOnly() {
        let b = book(projects: ["tide": NameEntry(project: "Other work"), "Other work": NameEntry(hideTitles: true)],
                     projectFolders: ["tide-web": "tide"])
        #expect(Set(b.secretNames()) == ["tide", "tide-web"])
        #expect(b.mentionsSecret("fix tide charts"))
        #expect(b.mentionsSecret("Fix TIDE"))
        #expect(b.mentionsSecret("in tide-web today"))
        #expect(!b.mentionsSecret("tidemark release"))
        #expect(!b.mentionsSecret("subtide"))
        #expect(!book().mentionsSecret("anything"))
    }

    @Test func secretFilterAppliesToCommitSubjects() {
        let b = book(projects: ["Harbor Labs": NameEntry(project: "Other work"), "Other work": NameEntry(hideTitles: true)])
        let subjects = ["Fix Harbor Labs login", "Tidy the readme", "harbor labs! cleanup"]
        #expect(subjects.filter { !b.mentionsSecret($0) } == ["Tidy the readme"])
        #expect(b.mentionsSecret("C++ (Harbor Labs)"))
    }
}
