# Contributing to Waypoint

Glad you're here — contributions are welcome.

## Getting started

```bash
git clone https://github.com/DeepakPal25/Waypoint.git
cd Waypoint
swift test
```

You'll need Xcode 16 or later (Swift 6).

## A few ground rules

- **Open an issue first** for anything bigger than a small bug fix. It's worth agreeing on the approach before you put the time in.
- **No dependencies.** Keep the library dependency-free and compiling cleanly under Swift 6 strict concurrency. Navigation logic belongs in `Router` so it stays testable without a view.
- **Write tests** for new behaviour using Swift Testing. Test routers directly — no need to render views.
- **Document public API** with DocC comments.
- **Update CHANGELOG.md** under *Unreleased*.

## Submitting a pull request

1. Fork the repo and cut a branch from `main`.
2. Make your change and add tests.
3. Run `swift test` and make sure everything passes.
4. Open a PR explaining what changed and why.

Contributions are MIT-licensed, same as the rest of the project.
