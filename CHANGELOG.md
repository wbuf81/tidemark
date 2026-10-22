# Changelog

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
