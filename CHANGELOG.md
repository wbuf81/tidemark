# Changelog

## 1.0.2

- The battery of the plan Claude Code is using shows bubbles rising while it works, and a blue dot when it needs you.
- Right-click the widget: the Tide check mark follows your choice, and "Show the week" hides or shows the week at
  the end (also in Settings → Widget).
- The README shows everything Tidemark does, with a picture of each part.

## 1.0.1

- The programs Tidemark runs (git for your commits, Claude Code for the weekly report) no longer stall
  when several run at once on a Mac with few cores.
- Builds with Xcode 16's Swift again.

## 1.0.0

First public release.

- One app, Tidemark: a widget beside the Dock (or a notch) and one window with Usage, Week,
  Month, Trends and Names & tags.
- The week calendar of Claude Code sessions and Cowork tasks, with commits, built on your Mac.
- Weekly report, plain or written by Claude Code.
- Plan limits and run-out forecast from claude.ai, off by default and behind a warning.
- Each plan is a tide in the widget: the water rises as its week fills, hatched where you'd be locked
  out. Right-click for "Water level" or "Over the week". Claude Code's status sits on the plan it's on.
- Click a plan, in the widget or the menu bar, for its details: what's left, when it runs out, your pace,
  the week as a line and your busiest hours.
- A battery per plan in the menu bar, showing what's left of its week.
- Usage on a moonlit tide: the answer as a headline, a card per plan, the week's chart and last week.
- Claude Code's status through hooks, off until you add them.
- Public domain (the Unlicense). Not signed by Apple: open it once with Open Anyway.
- Replaces Claude Dock and the Python week calendar; Tidemark offers to import your old weeks.
- Builds are versioned from one `VERSION` file and carry the app icon and the license;
  `release.sh` makes a universal zip with a checksum.
