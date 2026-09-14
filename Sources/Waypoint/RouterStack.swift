import SwiftUI

/// A `NavigationStack` driven by a ``Router``, with sheets and full-screen
/// covers that get their own nested stacks.
///
/// ```swift
/// RouterStack(router: router) {
///     HomeView()
/// } destination: { route in
///     switch route {
///     case .profile(let id): ProfileView(userID: id)
///     case .article(let id): ArticleView(id: id)
///     case .settings: SettingsView()
///     case .login: LoginView()
///     }
/// }
/// ```
///
/// The router is placed in the environment, so any view inside can read it
/// with `@Environment(Router<AppRoute>.self)`. Views inside a modal get the
/// modal's own router.
public struct RouterStack<R: Route, Root: View, Destination: View>: View {
    @Bindable private var router: Router<R>
    private let root: Root
    private let destination: (R) -> Destination

    public init(
        router: Router<R>,
        @ViewBuilder root: () -> Root,
        @ViewBuilder destination: @escaping (R) -> Destination
    ) {
        self.router = router
        self.root = root()
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            root.navigationDestination(for: R.self) { route in
                destination(route)
            }
        }
        .environment(router)
        .sheet(item: $router.sheet) { presentation in
            modalStack(for: presentation)
        }
        #if os(macOS)
        .sheet(item: $router.fullScreenCover) { presentation in
            modalStack(for: presentation)
        }
        #else
        .fullScreenCover(item: $router.fullScreenCover) { presentation in
            modalStack(for: presentation)
        }
        #endif
    }

    private func modalStack(for presentation: Router<R>.Presentation) -> RouterStack<R, Destination, Destination> {
        RouterStack<R, Destination, Destination>(router: presentation.router) {
            destination(presentation.root)
        } destination: { route in
            destination(route)
        }
    }
}
