import Foundation
import Observation

/// Coordinates a `TabView` where every tab has its own navigation stack.
///
/// ```swift
/// enum Tab: String, Codable, CaseIterable { case home, search, profile }
///
/// @State private var tabs = TabRouter<Tab, AppRoute>(initial: .home)
///
/// TabView(selection: tabs.selectionBinding) {
///     RouterStack(router: tabs.router(for: .home)) { HomeView() } destination: { $0.view }
///         .tag(Tab.home)
///     …
/// }
/// ```
///
/// Selecting the tab that's already selected pops it to its root, matching
/// the standard iOS behaviour.
@MainActor
@Observable
public final class TabRouter<Tab: Hashable & Codable & Sendable, R: Route> {
    public private(set) var selection: Tab
    // Not observed: each router is observable itself, and creating one lazily
    // during a view update must not invalidate that view.
    @ObservationIgnored private var routers: [Tab: Router<R>] = [:]
    @ObservationIgnored private let routeGuard: (@MainActor (R) -> RouteDecision<R>)?

    public init(initial: Tab, routeGuard: (@MainActor (R) -> RouteDecision<R>)? = nil) {
        self.selection = initial
        self.routeGuard = routeGuard
    }

    /// The router for `tab`, created on first use.
    public func router(for tab: Tab) -> Router<R> {
        if let existing = routers[tab] { return existing }
        let router = Router<R>(routeGuard: routeGuard)
        routers[tab] = router
        return router
    }

    public var selectedRouter: Router<R> {
        router(for: selection)
    }

    /// Selects a tab. Re-selecting the current tab dismisses its modals and pops it to root.
    public func select(_ tab: Tab) {
        if tab == selection {
            let router = router(for: tab)
            router.dismissPresented()
            router.popToRoot()
        } else {
            selection = tab
        }
    }

    /// Switches to `tab` and applies `state` to it, e.g. for a deep link.
    public func open(_ tab: Tab, state: NavigationState<R>) {
        selection = tab
        router(for: tab).apply(state)
    }

    // MARK: State

    public struct Snapshot: Hashable, Codable, Sendable {
        public var selection: Tab
        public var tabs: [Tab: NavigationState<R>]

        public init(selection: Tab, tabs: [Tab: NavigationState<R>] = [:]) {
            self.selection = selection
            self.tabs = tabs
        }
    }

    public var state: Snapshot {
        Snapshot(selection: selection, tabs: routers.mapValues { $0.state })
    }

    public func apply(_ state: Snapshot) {
        selection = state.selection
        for (tab, tabState) in state.tabs {
            router(for: tab).apply(tabState)
        }
    }
}
