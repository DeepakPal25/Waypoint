import Foundation
import Observation

/// What happens when code asks to navigate to a route.
public enum RouteDecision<R: Route> {
    case allow
    /// Navigate somewhere else instead, e.g. an upgrade screen.
    case redirect(R)
    /// Show a modal instead, e.g. login for a route that requires an account.
    case present(R, style: PresentationStyle)
    case deny
}

/// Owns the navigation state of one `NavigationStack` and the modal presented above it.
///
/// Views navigate by calling methods on the router from the environment,
/// never by owning `NavigationLink` destinations directly:
///
/// ```swift
/// struct ArticleRow: View {
///     @Environment(Router<AppRoute>.self) private var router
///     let article: Article
///
///     var body: some View {
///         Button(article.title) { router.push(.article(id: article.id)) }
///     }
/// }
/// ```
///
/// A presented modal gets its own child router, so each sheet has an
/// independent stack, and the whole tree can be captured as a
/// ``NavigationState`` and restored.
@MainActor
@Observable
public final class Router<R: Route> {
    /// A modal presented by this router.
    public struct Presentation: Identifiable {
        public let id = UUID()
        public let root: R
        public let style: PresentationStyle
        /// The router for the modal's own navigation stack.
        public let router: Router<R>
    }

    /// The navigation stack. Bound to `NavigationStack(path:)`.
    public var path: [R] = []
    /// The presented sheet. Set to `nil` by SwiftUI when the user swipes it away.
    public var sheet: Presentation?
    /// The presented full-screen cover.
    public var fullScreenCover: Presentation?

    /// Consulted before every push and present, e.g. to require sign-in.
    /// Inherited by child routers.
    @ObservationIgnored public var routeGuard: (@MainActor (R) -> RouteDecision<R>)?

    @ObservationIgnored public private(set) weak var parent: Router<R>?

    public init(path: [R] = [], routeGuard: (@MainActor (R) -> RouteDecision<R>)? = nil) {
        self.path = path
        self.routeGuard = routeGuard
    }

    // MARK: Stack

    /// Pushes a route, subject to ``routeGuard``.
    public func push(_ route: R) {
        switch decide(route) {
        case .allow:
            path.append(route)
        case .redirect(let other):
            path.append(other)
        case .present(let other, let style):
            show(other, style: style)
        case .deny:
            break
        }
    }

    /// Pushes several routes in one transaction, without consulting the guard for each.
    public func push(contentsOf routes: [R]) {
        path.append(contentsOf: routes)
    }

    public func pop(count: Int = 1) {
        path.removeLast(min(max(count, 0), path.count))
    }

    public func popToRoot() {
        path.removeAll()
    }

    /// Pops back to the most recent route matching `predicate`. Returns `false` if none matches.
    @discardableResult
    public func pop(to predicate: (R) -> Bool) -> Bool {
        guard let index = path.lastIndex(where: predicate) else { return false }
        path.removeSubrange(path.index(after: index)...)
        return true
    }

    /// Replaces the whole stack, e.g. after onboarding completes.
    public func setStack(_ routes: [R]) {
        path = routes
    }

    // MARK: Modals

    /// Presents a route modally with its own navigation stack, subject to ``routeGuard``.
    public func present(_ route: R, style: PresentationStyle = .sheet) {
        switch decide(route) {
        case .allow:
            show(route, style: style)
        case .redirect(let other):
            show(other, style: style)
        case .present(let other, let otherStyle):
            show(other, style: otherStyle)
        case .deny:
            break
        }
    }

    /// The modal this router is presenting, if any.
    public var presentation: Presentation? {
        sheet ?? fullScreenCover
    }

    /// The router at the top of the modal hierarchy, the one the user is looking at.
    public var topmost: Router<R> {
        presentation?.router.topmost ?? self
    }

    /// The router that owns the app's base navigation stack.
    public var root: Router<R> {
        parent?.root ?? self
    }

    /// Dismisses the modal *this router presented* (and everything above it).
    public func dismissPresented() {
        sheet = nil
        fullScreenCover = nil
    }

    /// Dismisses the modal *this router lives in*, like SwiftUI's `dismiss` action.
    public func dismiss() {
        parent?.dismissPresented()
    }

    /// Dismisses every modal in the app.
    public func dismissAll() {
        root.dismissPresented()
    }

    // MARK: State

    /// A serializable snapshot of this router and every modal above it.
    public var state: NavigationState<R> {
        NavigationState(
            path: path,
            presented: presentation.map {
                NavigationState.Presented(style: $0.style, root: $0.root, state: $0.router.state)
            }
        )
    }

    /// Replaces the whole hierarchy with `state`. Bypasses ``routeGuard``,
    /// since the state was already valid when it was captured.
    public func apply(_ state: NavigationState<R>) {
        path = state.path
        dismissPresented()
        if let presented = state.presented {
            let child = makeChild()
            child.apply(presented.state)
            setPresentation(Presentation(root: presented.root, style: presented.style, router: child))
        }
    }

    // MARK: Private

    private func decide(_ route: R) -> RouteDecision<R> {
        routeGuard?(route) ?? .allow
    }

    private func show(_ route: R, style: PresentationStyle) {
        dismissPresented()
        setPresentation(Presentation(root: route, style: style, router: makeChild()))
    }

    private func setPresentation(_ presentation: Presentation) {
        switch presentation.style {
        case .sheet: sheet = presentation
        case .fullScreenCover: fullScreenCover = presentation
        }
    }

    private func makeChild() -> Router<R> {
        let child = Router(routeGuard: routeGuard)
        child.parent = self
        return child
    }
}
