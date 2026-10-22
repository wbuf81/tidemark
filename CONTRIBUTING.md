# Contributing

Thank you for helping. Tidemark is in the public domain, so what you contribute is too.

## Build and test

You need macOS 14 or later and Xcode 16 (or its Command Line Tools).

```sh
git clone https://github.com/wbuf81/tidemark
cd tidemark
swift build
./test.sh              # all tests; ./test.sh --filter <Suite> for one suite
./build.sh             # builds build/Tidemark.app
```

Tests use Swift Testing. They run against temp folders, a fake HOME and fake `git` and `claude`
programs. A test never reads real files, touches the Keychain or opens a real account.

## The render mode

Pictures of the app come from an offscreen render with demo data:

```sh
swift run Tidemark --render "$(mktemp -d)"
```

It writes PNGs and exits. Use it to check a layout change in light, dark and on the notch.

## Rules for what goes in the repo

- Sample data only: plans `Personal`, `Harbor Labs`, `Lighthouse Co`; projects `tide-tables`,
  `lighthouse-api`, `field-notes`, `harbor-site`. Fixture emails use `@example.com`, paths use
  `/Users/you/`, and ids look like `sess-tide-0001`, never a real UUID.
- No names, emails, employers, home paths or account ids of real people.
- Words users read: "plan", sentence case, "Tidemark".
- Colours come from `Palette`; check text contrast 4.5:1 and marks 3:1 in light and dark.
- Every action must work from the keyboard and with VoiceOver.

## The guard hooks

`.githooks/` holds pre-commit, commit-msg and pre-push hooks that block secrets, real
paths, emails and real ids. Turn them on once:

```sh
git config core.hooksPath .githooks
```

Run `.githooks/scan-sensitive.sh --all` to scan every tracked file.

## Pull requests

Keep one change per pull request, add or update tests, and run `./test.sh`. Changes that touch
what a user sees need a render check; changes to behaviour that tests can't reach go in
`docs/manual-checks.md`. Be kind: see the Code of Conduct.
