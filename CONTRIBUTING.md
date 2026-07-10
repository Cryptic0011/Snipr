# Contributing to Snipr

Thanks for helping. Snipr is plain SwiftPM — no Xcode project required.

## Setup

```bash
git clone https://github.com/Cryptic0011/Snipr && cd Snipr
swift build                  # compile
swift test                   # run the test suite
./script/build_and_run.sh    # build the .app bundle and launch it
```

Screen capture, recording, and input-overlay features need macOS permissions
(Screen Recording, Accessibility, Input Monitoring) granted to the built app.

## Architecture

Read `HANDOFF.md` first — it maps the coordinator/presenter/engine layout.
Match the existing patterns rather than introducing new ones.

## Pull requests

- Keep PRs focused; one change per PR.
- `swift build -Xswiftc -warnings-as-errors && swift test` must pass — CI
  enforces both.
- Add or update tests for logic changes. UI-only changes should note how they
  were verified by hand (multi-monitor and Retina/non-Retina behavior matters).

## Releases

Maintainer-only; see `RELEASING.md`.
