import SwiftUI

extension View {
    /// Saves the router's full navigation state (stack and modals) in
    /// `SceneStorage` and restores it when the scene is recreated.
    ///
    /// ```swift
    /// RouterStack(router: router) { HomeView() } destination: { $0.view }
    ///     .navigationRestoration(router)
    /// ```
    ///
    /// If the saved data can't be decoded (for example after a route's shape
    /// changed in an app update), the app simply starts at the root.
    public func navigationRestoration<R: Route>(_ router: Router<R>, key: String = "waypoint.navigation") -> some View {
        modifier(NavigationRestorationModifier(router: router, key: key))
    }

    /// Saves and restores a ``TabRouter``, including the selected tab and every tab's stack.
    public func navigationRestoration<Tab, R: Route>(
        _ tabs: TabRouter<Tab, R>,
        key: String = "waypoint.tabs"
    ) -> some View {
        modifier(TabRestorationModifier(tabs: tabs, key: key))
    }
}

struct NavigationRestorationModifier<R: Route>: ViewModifier {
    let router: Router<R>
    @SceneStorage private var storedState: Data?
    @State private var hasRestored = false

    init(router: Router<R>, key: String) {
        self.router = router
        _storedState = SceneStorage(key)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasRestored else { return }
                hasRestored = true
                if let storedState, let state = try? JSONDecoder().decode(NavigationState<R>.self, from: storedState) {
                    router.apply(state)
                }
            }
            .onChange(of: router.state) { _, newState in
                storedState = try? JSONEncoder().encode(newState)
            }
    }
}

struct TabRestorationModifier<Tab: Hashable & Codable & Sendable, R: Route>: ViewModifier {
    let tabs: TabRouter<Tab, R>
    @SceneStorage private var storedState: Data?
    @State private var hasRestored = false

    init(tabs: TabRouter<Tab, R>, key: String) {
        self.tabs = tabs
        _storedState = SceneStorage(key)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasRestored else { return }
                hasRestored = true
                if let storedState, let state = try? JSONDecoder().decode(TabRouter<Tab, R>.Snapshot.self, from: storedState) {
                    tabs.apply(state)
                }
            }
            .onChange(of: tabs.state) { _, newState in
                storedState = try? JSONEncoder().encode(newState)
            }
    }
}

extension TabRouter {
    /// A binding for `TabView(selection:)` that routes taps through ``select(_:)``,
    /// so tapping the current tab pops it to root.
    public var selectionBinding: Binding<Tab> {
        Binding(
            get: { self.selection },
            set: { self.select($0) }
        )
    }
}
