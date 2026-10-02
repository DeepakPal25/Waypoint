# ``Waypoint``

Type-safe navigation for SwiftUI — routers for `NavigationStack`, nested modals, deep links, route guards and state restoration.

## Overview

Declare your destinations as a ``Route`` enum, host a ``RouterStack``, and navigate through the ``Router`` in the environment:

```swift
RouterStack(router: router) { HomeView() } destination: { $0.view }
    .navigationRestoration(router)
    .onOpenURL { router.handle($0, with: .app) }
```

## Topics

### Routing

- ``Route``
- ``Router``
- ``RouterStack``
- ``PresentationStyle``
- ``RouteDecision``

### State

- ``NavigationState``

### Deep links

- ``DeepLinkResolver``
- ``DeepLinkMatch``

### Tabs

- ``TabRouter``
