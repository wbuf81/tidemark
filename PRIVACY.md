# Privacy

Tidemark has no server, no account and no analytics. Your calendar stays on your Mac. Two
things leave it, and both are off until you switch them on:

1. Plan limits: Tidemark's own window reads your usage page on claude.ai (see below).
2. "Write it with Claude Code": the week's summary goes to Anthropic through your own Claude
   Code (see below).

Nothing else is sent anywhere.

## What Tidemark reads

You choose these in the first-run steps and can change them any time in Settings.

| Source | What it reads | Default |
|---|---|---|
| Claude Code sessions | When each ran, its title and project, from `~/.claude/projects`. | On |
| First messages | What you first asked in each session. | Off |
| Git commits in those projects | Only your own commits. | On |
| Cowork tasks (a folder you pick) | `tidemark-log.jsonl` in that folder, and the older per-task entry files named `<id>__<stamp>.json`. Nothing else in the folder is opened. | Off until you set it up |
| Claude Desktop's older Cowork sessions | `local_*.json` and `audit.jsonl` in `~/Library/Application Support/Claude/local-agent-mode-sessions`. | Off until you turn it on |
| Claude Code's status (hooks) | Eight Claude Code events, so the widget knows when Claude Code is thinking, working or waiting. | Off until you add the hooks |
| claude.ai plan limits | Your usage page, from Tidemark's own signed-in window. While this is on, `~/.claude.json` is also read (every 10 seconds, only to see which plan Claude Code is signed into: the organisation ID in it). | Off |
| Whether Claude Code is working | File changes (names and times only, never the contents) in `~/.claude/projects`, so the widget can show Claude Code's status. This is always on, whatever the switches above say. | Always on |
| Claude Code's settings file | `~/.claude/settings.json`, read about every 30 seconds to see whether Tidemark's hooks are in it and how long Claude Code keeps transcripts (`cleanupPeriodDays`). Tidemark changes the file only when you add or remove the hooks. This is always on. | Always on |

## What Tidemark stores, and where

- `~/Library/Application Support/Tidemark/`: your calendar (sessions, commits), names and tags,
  weekly reports, usage history, the hook status files, and, if you imported an old week
  calendar, a copy of it.
- `~/Library/Caches/io.github.wbuf81.tidemark`: caches.
- A login item, only if you chose Launch at login.
- Settings, in the app's preferences (`io.github.wbuf81.tidemark`).
- If you turned on plan limits: claude.ai's sign-in cookies, in Tidemark's own WebKit store
  (`~/Library/WebKit/io.github.wbuf81.tidemark` and `~/Library/HTTPStorages/io.github.wbuf81.tidemark`).
  Your password goes to claude.ai, never to Tidemark.
- If you add the hooks: entries marked `# tidemark` in `~/.claude/settings.json`. A copy of the
  file is kept first, and Remove hooks removes only Tidemark's entries.

## Plan limits (claude.ai) are optional

Reading claude.ai is off until you turn it on through a warning sheet. The warning says:

> Anthropic hasn't approved this. Tidemark reads the usage page claude.ai shows you, from its own
> signed-in window. Anthropic's terms don't allow apps to use your claude.ai sign-in this way, so
> they could block it or act on your account. It's off unless you turn it on, and you can turn it
> off any time.

When on, Tidemark reads your usage page every 3 minutes. It does not change your browser's
identity or work around bot checks. Turning it off, or Sign out, stops it.

## "Write it with Claude Code" is optional

The weekly report is written on this Mac unless you choose "Write it with Claude Code" (asked
once; change it in Settings → Week). Then Tidemark runs your own Claude Code with that week's
summary: titles, projects, hours and commit subjects. First messages go in only if you turned
them on. Claude Code sends that to Anthropic's service under your own plan and Anthropic's
terms; Tidemark has no copy of it on any server.

That run is a Claude Code session like any other, so Claude Code records it in its own history
under `~/.claude/projects`. Tidemark leaves those runs out of your calendar, but the record is
Claude Code's, kept as long as Claude Code keeps its transcripts.

## Nothing else leaves your Mac

No analytics, no crash reporting, no update pinging.

## Delete it

- Settings → Week → Delete all data removes your calendar, names, tags, reports and usage
  history, resets settings and signs out of claude.ai. It keeps the imported copy of an old
  calendar and the Claude Code hooks. Claude Code's own files and your git repositories are not
  touched. Weeks older than 30 days exist only in Tidemark, so export them first if you want them.
- Settings → Advanced → Uninstall… does all of that and also removes the hooks, the imported
  copy, the caches and the login item, then quits. The app itself stays in Applications: drag
  it to the Bin. The README lists the folders if you prefer to do it by hand.
