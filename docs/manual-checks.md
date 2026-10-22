# Manual checks

The unit tests cover the logic and the offscreen render covers layouts with demo data. These need
a real Mac, a real account, or a person. Tick what you checked, and on which macOS.

## Install and first run

- [ ] On a clean user account on macOS 15: download the zip, drag Tidemark to Applications, open
      it. macOS says it can't check Tidemark; Done. System Settings → Privacy & Security → Open
      Anyway, Open Anyway again, password. It then opens.
- [ ] Check on a macOS 14 Mac (clean account): the README states only Control-click → Open → Open
      for macOS 14. Write down what the first alert's buttons are (we think Move to Trash and
      Cancel, no Done), what Open Anyway asks next (we think the button says Open), and how long
      the Open Anyway button stays in Privacy & Security after the first try (we think about an
      hour). If they differ, fix README steps 2 and 3 and the pictures' captions.
- [ ] macOS 14: Control-click Tidemark in Applications → Open → Open starts it.
- [ ] The README's steps and pictures match what you saw on each macOS.
- [ ] First run shows four steps, calendar first. "What Tidemark reads" has a switch per source,
      first messages off. Plan limits step has neither button pre-selected.
- [ ] Launch at login is not switched on unless you chose it.
- [ ] Two copies: opening a second copy brings the first to the front and doesn't start another.
- [ ] `./build.sh` while the app is running from `build/` compiles first, then quits it and reopens the new one. With a compile error (add one on purpose), the running app stays running.
- [ ] Close first run with Escape on step 1: Week says "Choose what Tidemark reads." with Choose sources, which opens "What Tidemark reads" on its own (no step count, no Back); Continue closes it and the week fills in. Settings → Week shows "Tidemark isn’t reading anything yet" with Choose what it reads… until then.
- [ ] With an old calendar waiting in `calendar/import-source`: nothing reads during first run, the import sheet appears when first run closes, Import then reads (names and weeks first), Not now reads without them.
- [ ] A settings file left with plan limits on from an older install: no claude.ai request and no sign-in window until first run is done.
- [ ] The notification permission prompt appears only with the first notification, after the
      "Get notified?" sheet.

## Widget and menu bar

- [ ] Frosted glass over a light and a dark desktop: text stays readable, in the widget and the notch.
- [ ] Widget beside the Dock (bottom, left, right, auto-hidden) never sits under it. Repeat with
      minimized windows, a second display plugged in and out, and a changed resolution.
- [ ] Every Settings → Widget position spot, then drag back.
- [ ] Resize through all sizes, light and dark; the width is remembered after relaunch.
- [ ] The menu bar item and its menu: Refresh now, Hide for 1 hour, Settings…, Quit.
- [ ] Notch: hover opens it and leaving closes it with no flicker; click opens the window; right-click
      shows the same menu; the glow and rim follow the states.

## The window

- [ ] Usage, Week, Month, Trends, Names & tags each open; sizes and place are remembered.
- [ ] Minimize the window with ⌘M (Settings closed): the Dock icon, ⌘Tab entry and menu bar stay, and clicking the Dock tile brings the window back.
- [ ] Rename, tag and move a session between projects in Names & tags; the Week updates at once.
- [ ] The weekly report: plain, and "Write it with Claude Code" (uses a little of your plan).
- [ ] A week with Daylight Saving change (25 Oct 2026 in Europe, 1 Nov 2026 in the US) and a
      Sunday week start look right.
- [ ] Change the Mac's time zone: times update within a minute, without relaunching.
- [ ] A 24-hour region shows "16:00"; a 12-hour one "4 PM".

## Plan limits (claude.ai)

- [ ] Off by default; the warning sheet shows before sign-in; neither button is the default.
- [ ] Email link, Google and single sign-on sign in; the pop-up opens in its own window.
- [ ] Sign out, then sign in again with Google: it asks for the account again.
- [ ] Ending the session on claude.ai brings a "signed out" notification; clicking it opens sign-in.
- [ ] One paid plan, a free plan only, and a plan that is turned off: each reads sensibly.
- [ ] Wi-Fi off: the window says it can't reach claude.ai within a refresh, the widget shows
      "old reading" and "as of"; Wi-Fi back on and Refresh now recovers.
- [ ] Offline for 10+ minutes: rows dim and say when the last reading was.
- [ ] Turning plan limits off stops the readings.

## Claude Code hooks

- [ ] Settings → Connect: the confirmation; `~/.claude/settings.json` gains entries marked
      `# tidemark`; other hooks unchanged. Remove hooks right after: the file is byte-identical
      (`shasum` before and after).
- [ ] A Claude Code prompt: thinking, then working while a command runs, then done, then idle,
      each within about a second.
- [ ] A permission prompt shows the waiting mark within a second; Esc mid-turn rests within about a minute.
- [ ] Two sessions, one waiting: the waiting mark shows. `kill -9` a session: it goes within 30 s.

## Cowork

- [ ] Choose a folder, paste the instruction into Cowork; after a task a line appears and Tidemark shows it.

## Accessibility

- [ ] VoiceOver pass: each plan reads as one sentence; every button, switch and sheet is reachable
      and named; the window, widget and notch are all operable.
- [ ] Keyboard pass: every action works without the pointer; focus is visible; Tab order is sensible.
- [ ] Increase Contrast, Reduce Transparency and Reduce Motion: everything stays readable and still.
- [ ] Windows zoom; very long and non-Latin names truncate without overlapping.

## Power

- [ ] Sleep and wake: readings resume without a relaunch and without a burst of requests.
- [ ] Activity Monitor: Tidemark near 0% CPU at rest and while the status animates.

## Data

- [ ] Import your week calendar: the sheet offers it once; the originals are unchanged.
- [ ] Settings → Week → Delete all data: confirmation, Export first works; everything is gone
      afterwards and claude.ai is signed out. Claude Code's files and git repositories are untouched.

## Uninstall

- [ ] Settings → Advanced → Uninstall… removes the hooks, login item, data and settings, then
      quits; the app stays in Applications until you drag it to the Bin.
- [ ] Delete all data keeps the imported old-calendar copy and the hooks; Uninstall removes them.
- [ ] The README's manual list leaves nothing behind:
      `ls ~/Library/*/io.github.wbuf81.tidemark* ~/Library/Application\ Support/Tidemark`.
