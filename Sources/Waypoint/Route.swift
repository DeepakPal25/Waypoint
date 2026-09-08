/// A destination in your app.
///
/// Routes are plain values, usually an enum, so navigation is type-checked,
/// testable without UI, and serializable for state restoration and deep links:
///
/// ```swift
/// enum AppRoute: Route {
///     case profile(userID: String)
///     case article(id: Int)
///     case settings
///     case login
/// }
/// ```
///
/// Associated values should be identifiers, not models: a route must survive
/// being written to disk and restored on the next launch.
public protocol Route: Hashable, Codable, Sendable {}

/// How a modal destination is shown.
public enum PresentationStyle: String, Hashable, Codable, Sendable {
    case sheet
    /// Falls back to a sheet on macOS, which has no full-screen cover.
    case fullScreenCover
}

/// A complete, serializable snapshot of a navigation hierarchy: the stack,
/// plus whatever modal is presented on top of it, recursively.
///
/// It is the single format used for state restoration, deep links and tests.
///
/// ```swift
/// // Settings › Notifications, with a login sheet on top
/// NavigationState(
///     path: [.settings, .notifications],
///     presented: .init(style: .sheet, root: .login)
/// )
/// ```
public struct NavigationState<R: Route>: Hashable, Codable, Sendable {
    public var path: [R]

    /// The modal presented on top of `path`, if any.
    public var presented: Presented? {
        get { presentedStorage.first }
        set { presentedStorage = newValue.map { [$0] } ?? [] }
    }

    // A struct can't directly contain an optional of itself, so the
    // recursion goes through an array of zero or one elements.
    private var presentedStorage: [Presented]

    public init(path: [R] = [], presented: Presented? = nil) {
        self.path = path
        self.presentedStorage = presented.map { [$0] } ?? []
    }

    public struct Presented: Hashable, Codable, Sendable {
        public var style: PresentationStyle
        /// The root view of the modal's own navigation stack.
        public var root: R
        /// Navigation inside the modal.
        public var state: NavigationState

        public init(style: PresentationStyle = .sheet, root: R, state: NavigationState = NavigationState()) {
            self.style = style
            self.root = root
            self.state = state
        }
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case presentedStorage = "presented"
    }

    /// The number of modals stacked on top of each other.
    public var modalDepth: Int {
        presented.map { 1 + $0.state.modalDepth } ?? 0
    }
}
