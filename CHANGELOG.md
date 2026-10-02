# Changelog

Notable changes are listed here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned with [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-02

First release.

### Added
- `Route` protocol and `@Observable` `Router` for driving `NavigationStack` — push, pop, pop-to, and full stack replacement.
- Nested sheets and full-screen covers, each with its own child router and stack.
- Serializable `NavigationState` covering the whole hierarchy, accessible via `state` and `apply(_:)`.
- `DeepLinkResolver` with `:param` and `*` wildcard patterns, support for both custom schemes and universal links, and host allow-listing.
- Route guards: allow, redirect, present, or deny — inherited through child routers.
- `TabRouter` for tabbed apps: per-tab stacks, pop-to-root on re-select, tab-targeted deep links, and state snapshots.
- `RouterStack` view and `navigationRestoration` modifier, backed by `SceneStorage`.
