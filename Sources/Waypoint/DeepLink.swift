import Foundation

/// The parts of a URL that matched a deep-link pattern.
public struct DeepLinkMatch: Sendable, Hashable {
    /// Values for `:name` placeholders, and `"*"` for a trailing wildcard.
    public let parameters: [String: String]
    /// Query items. When a name repeats, the first value wins.
    public let query: [String: String]
    public let url: URL

    public subscript(_ name: String) -> String? {
        parameters[name] ?? query[name]
    }

    /// A parameter parsed as an integer, or `nil` if it's missing or not a number.
    public func int(_ name: String) -> Int? {
        self[name].flatMap(Int.init)
    }
}

/// Maps URLs to navigation targets with path patterns.
///
/// ```swift
/// var links = DeepLinkResolver<NavigationState<AppRoute>>(
///     schemes: ["myapp"],
///     hosts: ["example.com", "www.example.com"]
/// )
/// links.register("users/:id") { match in
///     match["id"].map { NavigationState(path: [.profile(userID: $0)]) }
/// }
/// links.register("articles/:id") { match in
///     match.int("id").map { NavigationState(path: [.article(id: $0)]) }
/// }
/// links.register("login") { _ in
///     NavigationState(presented: .init(root: .login))
/// }
/// ```
///
/// Both `myapp://users/42` and `https://example.com/users/42` resolve to the
/// same pattern: for a custom scheme the URL's host is treated as the first
/// path segment.
///
/// Patterns are tried in registration order and the first handler that
/// returns a value wins, so register specific patterns before general ones.
/// A handler returns `nil` to reject a match (e.g. a non-numeric ID) and let
/// later patterns try.
///
/// `Output` is generic, so a resolver can return a `NavigationState`, a
/// `(tab, state)` pair for ``TabRouter``, or anything else.
public struct DeepLinkResolver<Output>: Sendable {
    private struct Entry: Sendable {
        let pattern: Pattern
        let handler: @Sendable (DeepLinkMatch) -> Output?
    }

    /// Custom URL schemes handled, e.g. `["myapp"]`. Compared case-insensitively.
    public let schemes: Set<String>
    /// Hosts accepted for `http`/`https` universal links. Links to any other host are ignored.
    public let hosts: Set<String>
    private var entries: [Entry] = []

    public init(schemes: Set<String> = [], hosts: Set<String> = []) {
        self.schemes = Set(schemes.map { $0.lowercased() })
        self.hosts = Set(hosts.map { $0.lowercased() })
    }

    /// Registers a pattern such as `"users/:id"`, `"settings/notifications"` or `"docs/*"`.
    ///
    /// - `:name` matches one segment and captures it.
    /// - `*` as the last segment matches the rest of the path (including nothing).
    /// - Other segments match literally, ignoring case.
    public mutating func register(_ pattern: String, _ handler: @escaping @Sendable (DeepLinkMatch) -> Output?) {
        entries.append(Entry(pattern: Pattern(pattern), handler: handler))
    }

    /// The output for `url`, or `nil` if the URL isn't handled.
    public func resolve(_ url: URL) -> Output? {
        guard let segments = segments(of: url) else { return nil }
        let query = Self.queryItems(of: url)

        for entry in entries {
            guard let parameters = entry.pattern.match(segments) else { continue }
            let match = DeepLinkMatch(parameters: parameters, query: query, url: url)
            if let output = entry.handler(match) {
                return output
            }
        }
        return nil
    }

    private func segments(of url: URL) -> [String]? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let pathSegments = url.pathComponents.filter { $0 != "/" }

        if schemes.contains(scheme) {
            // myapp://users/42 → host "users", path "/42"
            let host = url.host(percentEncoded: false).map { [$0] } ?? []
            return (host + pathSegments).filter { !$0.isEmpty }
        }
        if scheme == "https" || scheme == "http",
           let host = url.host(percentEncoded: false)?.lowercased(),
           hosts.contains(host) {
            return pathSegments
        }
        return nil
    }

    private static func queryItems(of url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var query: [String: String] = [:]
        for item in items where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        return query
    }
}

struct Pattern: Sendable {
    enum Segment: Sendable, Equatable {
        case literal(String)
        case parameter(String)
        case wildcard
    }

    let segments: [Segment]

    init(_ pattern: String) {
        segments = pattern
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { part in
                if part == "*" { return .wildcard }
                if part.hasPrefix(":") { return .parameter(String(part.dropFirst())) }
                return .literal(part.lowercased())
            }
    }

    func match(_ path: [String]) -> [String: String]? {
        var parameters: [String: String] = [:]
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .wildcard:
                guard index <= path.count else { return nil }
                parameters["*"] = path[index...].joined(separator: "/")
                return parameters
            case .literal(let expected):
                guard index < path.count, path[index].lowercased() == expected else { return nil }
            case .parameter(let name):
                guard index < path.count else { return nil }
                parameters[name] = path[index]
            }
        }
        return path.count == segments.count ? parameters : nil
    }
}

extension Router {
    /// Resolves `url` and, if handled, dismisses every modal and applies the
    /// result to the root router. Returns whether the URL was handled.
    ///
    /// ```swift
    /// .onOpenURL { router.handle($0, with: deepLinks) }
    /// ```
    @discardableResult
    public func handle(_ url: URL, with resolver: DeepLinkResolver<NavigationState<R>>) -> Bool {
        guard let state = resolver.resolve(url) else { return false }
        root.apply(state)
        return true
    }
}

extension TabRouter {
    /// Resolves `url` to a tab and state and opens it. Returns whether the URL was handled.
    @discardableResult
    public func handle(_ url: URL, with resolver: DeepLinkResolver<(tab: Tab, state: NavigationState<R>)>) -> Bool {
        guard let target = resolver.resolve(url) else { return false }
        open(target.tab, state: target.state)
        return true
    }
}
