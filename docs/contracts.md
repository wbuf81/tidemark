# Tidemark v1 contracts

The types and calls that different parts of Tidemark code against. **Frozen:** change them only
with the coordinator's OK, and update this file in the same commit.

## Identity (`Sources/TidemarkCore/AppIdentity.swift`)

Permanent values that end up on users' Macs. Pinned by `AppIdentityTests`.

| | Value |
|---|---|
| Name | `Tidemark` |
| Bundle ID | `io.github.wbuf81.tidemark` |
| Support folder | `~/Library/Application Support/Tidemark/` (`calendar/`, `sessions/` inside) |
| Hooks marker | `# tidemark` (also recognised: `# claude-dock`) |
| WebKit store ID (claude.ai) | `8AD323F0-8465-42C6-98BD-6E670027E1DC` |
| Cowork log folder name | `Tidemark Log` (also read: `Claude Calendar Log`) |
| Week summary format | `week-summary/1` |
| Environment variables | `TIDEMARK_*` |

## The calendar (`Sources/TidemarkCore/Calendar/`)

- `CalendarModel.swift`: the data. Sessions (`CalendarSession`, `Block`, `Commit`, `SessionOrigin`),
  sources (`SourceSwitches`, `WeekStart`), names (`NameBook`, `NameEntry`, `NameKind`, `NameChange`,
  `NameBookError`), what the window shows (`WeekModel`, `WeekItem`, `ProjectTotal`, `TagTotal`,
  `MonthModel`, `MonthDay`, `MonthItem`, `TrendModel`, `TrendRow`, `TrendGrouping`, `NameRow`),
  reports (`WeekReport`, `ReportAuthor`, `ReportFailure`), and results (`RefreshSummary`,
  `LegacyFound`, `ImportResult`, `CalendarProblem`).
- `CalendarStoring.swift`: the protocol every part uses. Thread-safe; queries never wait for a refresh.
- `CalendarStores.swift`: `live(home:environment:)` and `reportWriter(home:environment:)`, the only
  way the app gets the real store and the Claude Code report writer.
- `SwitchableCalendar.swift`: forwards to a target the app can swap (demo data on and off).
- `DemoCalendar.swift`: the sample weeks every render and screenshot uses (the week of 19 Oct 2026).
- `HoursText.swift`: "9h 05m", minutes rounded half to even.
- `CoworkInstruction.swift`: the text a user pastes into Cowork (`text(folderName:)`, the name defaulting to
  `AppIdentity.coworkLogFolderName`).

### The engine's public API (Batch 1)

- `CalendarStore(folder:home:environment:runner:calendar:)`: the real `CalendarStoring`; `calendar: Calendar? = nil`
  follows the system time zone. Every write goes through one writer lock; queries never wait.
- `ProcessRunning`, `SystemProcessRunner(environment:)`: child processes get only `HOME`, `PATH` and, when set,
  `CLAUDE_CONFIG_DIR`.
- `ClaudeCodeReport(runner:home:environment:candidates:timeout:calendar:)`, `systemCandidates(home:)`,
  `summary(_:calendar:)`, `write(_:now:)`.
- `CalendarFiles`, `CalendarFilesError`, `LegacyImportError`, `AssignedSession` and the `NameBook` rules
  (`entry`, `shown`, `label`, `tags`, `assignedProject`, `assignProjects`, `hidesTitles`, `secretNames`,
  `mentionsSecret`, `apply`). Keys and file names always use the Gregorian calendar.

### Files on disk

```
<support>/calendar/format.json                {"format":"tidemark-calendar","version":1,"lastRefresh":"<ISO 8601>","lastSources":SourceSwitches}  (both optional)
<support>/calendar/sessions/<yyyy-MM>.json    {"version":1,"sessions":[CalendarSession]}   by the local month of the first block
<support>/calendar/names.json                 {"version":1,"names":NameBook}
<support>/calendar/reports.json               {"version":1,"reports":[WeekReport]}
<support>/calendar/backups/<base>.<yyyyMMdd-HHmmss>-<nnn>.json   the last 10 per file (month files use base sessions-<yyyy-MM>)
<support>/calendar/legacy/                    verbatim copies from an import; never rewritten
<support>/calendar/import-source/             an old calendar copied in for import; kept until Uninstall
```

Dates are ISO 8601 with their offset. A file with a newer `version` is read-only; a file that won't
decode is never written over.

## Plan state (`Sources/TidemarkCore/PlanState.swift`)

`PlanState` is `.fine`, `.runsOutEarly` or `.out`; `PlanStates.state(reading, forecast, thresholds)`
decides it. Out = week left under the red threshold, or the 5-hour window at the red threshold.
Runs out early = the forecast runs out before the reset, or the 5-hour window at the yellow
threshold. Fine otherwise. Each state has a shape (circle, triangle, square); an old reading draws it
hollow.

## Claude Code's files (`Sources/TidemarkCore/ClaudePaths.swift`)

`configDir`, `projectsDir`, `settingsFile`, `accountFile`, all honouring `CLAUDE_CONFIG_DIR`.

## Usage problems (`RefreshProblem`)

`offline`, `blocked`, `refused`, `http(Int)`, `noWeeklyLimit`, `changedShape(details: String)`.
Their words live in `UsageCopy`.

## Notifications

`AppModel` raises `onOut`, `onSessionNearlyFull` and `onAdvice` with a ready-made `Notice`
(title, body, plan), plus `onSignedOut`. The shell only posts them, gated by the Notifications
settings.

## The app (`Sources/Tidemark/`)

- `MainSection`: usage, week, month, trends, names.
- `MainWindowController`: `init(model:calendar:actions:)`, `show(_:plan:)`, `previousWeek()`,
  `nextWeek()`, `today()`, `copySummary()`, `toggleSidebar()`, `reload()` (re-reads the calendar into the open
  window; the app calls it after every calendar refresh, demo-mode toggle, week-start change and Delete all),
  `isVisible`, `onVisibilityChange`.
- `UsagePane`: `init(model:actions:selectedPlan:)`.
- `SettingsTab`: general, widget, plans, week, notifications, advanced. `SettingsWindowController`:
  `show(_:)`, `isVisible`, `onVisibilityChange`.
- `AppActions`: every action a view can ask for, each with a do-nothing default; `AppActions.none`.
- `AppModel`: `state(for:)`, `isOld(_:)` (the reading is over 10 minutes old: hollow shape, dimmed numbers, "as of"),
  `orgsToRead` (the shown plans plus the hidden one Claude Code is on; the poller reads these, only `orgs` are
  drawn), `noticeLog` (saved in the settings), `codeMood`, `limitsOff`, `readAge(now:)`, the notice callbacks.
- Shared views: `StateShape`, `StatusGlyph`, `WeekRing`.
- Render mode: each area has a `ShotProvider` in `Render/`; `Renderer.catalog` lists them.

## The shell's shared parts (`Sources/TidemarkCore/Shell/ShellContracts.swift`)

`HookState` (notConnected, connected, outdated), `ClaudeCodeHookFile.state()` and `.update()`,
`DataItem` and `Removal` (deleteAll, uninstall), `DataInventory.items(home:environment:)` (the environment
moves the Claude Code paths with `CLAUDE_CONFIG_DIR`), `ShellTime.hideEnds(started:duration:)` and
`ShellTime.hideIsOver(started:duration:now:)` (the wall clock, so sleep can't stretch "Hide for an hour").

## Shell logic in Core (`Sources/TidemarkCore/Shell/`, Batch 4)

- `CalendarSchedule.mayRefresh(sourcesChosen:paused:)`: the calendar reads nothing until the user has chosen what
  Tidemark reads (first run's step 2 or any change in Settings → Week; the saved `sourcesChosen`) and not while
  Delete all or Uninstall runs. `CalendarSchedule.sourcesChosen(leavingStep:)`: true for step 2.
- `UsageGate`: `mayRequest(planLimits:demoMode:)`, `run(_:at:planLimits:demoMode:_:)` and
  `mayWrite(_:in:planLimits:demoMode:)`, the "off means off" rule for claude.ai; `RefreshGeneration`
  (`begin()`, `cancel()`, `isCurrent(_:)`) makes a refresh in flight stale.
- `SettingsReset`: `keptKeys` (`sources`, `sourcesChosen`, `planLimits`, `firstRunDone`, `settingsVersion`: the
  user's privacy choices survive Delete all) and `keysToRemove(existing:)`.
- `CoworkLogFolder.prepare(chosen:)`: the folder to store for Cowork's log: the chosen one when it already is a
  log folder, else a `Tidemark Log` folder made inside it.
- `HooksText` (internal): edits the settings text itself, so everything that isn't Tidemark's hook groups stays
  byte for byte; used by `ClaudeCodeHookFile.connect()` and `disconnect()`.
- `NetworkRetry`: `failed()`, `succeeded()`, `wake()`, `networkReturned()` and `next(after:)`. Waits are 30, 60,
  120, 300, 600 s; offline stops at 60 s ("trying again every minute"); blocked and refused never go below
  `pollInterval` (180 s); `GlanceCopy.problem` says "trying again soon" for the errors that back off.

## Usage and glance logic in Core (Batch 3)

- `GlanceCopy`: the widget's, strip's and notch's own words: `problem(_:)`, `notchWord(...)`, `readAge(...)`,
  `stripNote(_:asOf:now:formatting:)`, `menuLine(_:glance:now:formatting:)` (`UsageCopy.menuLine` forwards to it),
  and the fixed messages (`signedOut`, `loading`, `noPlans`). `GlanceMessage` carries title, detail, narrow
  word and action.
- `Notices`: `weekAlert`, `sessionNearlyFull`, `toRead(shown:known:claudeCodeOrg:)` and
  `due(claudeCodeOrg:orgs:latest:history:now:formatting:thresholds:log:)`, which returns a `Notices.Due`
  (`week`, `sessionFull`) for the plan Claude Code is on, shown or not, each once per window.
  `NoticeLog` (Codable) remembers what was posted; the app keeps it in the settings under `noticeLog`.
- `UsageSummary.make(UsageInput)`: everything the Usage pane shows (tiles, plans, headline, switch advice) as
  plain values.
- `WidgetSizing`: M starts at a 130 pt slot, so the shortest week note never clips.

## Settings keys added in v1

`sourcesChosen` (Bool, default false; set true by first run's step 2, by any change to the sources, and by the
settings migration for an install that already had `firstRunDone`; kept by Delete all) and `noticeLog`
(Codable data; the notices already posted, so a relaunch doesn't post them again; reset by Delete all).

## Window panes (`Sources/Tidemark/Window/`)

`MonthPane(store:settings:now:onOpenWeek:)`, `TrendsPane(store:settings:now:onOpenWeek:)` and
`NamesPane(store:settings:now:)`, where `store` is `CalendarStoring`, `now` is `() -> Date` and
`onOpenWeek` is `(Date) -> Void`.
