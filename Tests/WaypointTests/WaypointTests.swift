import Foundation
import Testing
@testable import Waypoint

enum AppRoute: Route {
    case profile(userID: String)
    case article(id: Int)
    case docs(path: String)
    case settings
    case notifications
    case login
    case upgrade
}

enum AppTab: String, Hashable, Codable, Sendable {
    case home, search, account
}

// MARK: - Stack

@Suite("Router stack")
@MainActor
struct StackTests {
    @Test("Push and pop")
    func pushPop() {
        let router = Router<AppRoute>()

        router.push(.settings)
        router.push(.notifications)
        #expect(router.path == [.settings, .notifications])

        router.pop()
        #expect(router.path == [.settings])

        router.pop(count: 10)
        #expect(router.path.isEmpty, "Popping more than the stack holds empties it without crashing")
    }

    @Test("Pop to a matching route")
    func popTo() {
        let router = Router<AppRoute>(path: [.article(id: 1), .profile(userID: "a"), .article(id: 2), .settings])

        #expect(router.pop { if case .profile = $0 { true } else { false } })
        #expect(router.path == [.article(id: 1), .profile(userID: "a")])

        #expect(!router.pop { $0 == .login })
        #expect(router.path.count == 2)
    }

    @Test("Replacing the stack and popping to root")
    func replace() {
        let router = Router<AppRoute>()
        router.setStack([.settings, .notifications])
        #expect(router.path.count == 2)
        router.popToRoot()
        #expect(router.path.isEmpty)
    }
}

// MARK: - Modals

@Suite("Router modals")
@MainActor
struct ModalTests {
    @Test("Presenting creates a child router with its own stack")
    func present() throws {
        let router = Router<AppRoute>()
        router.present(.settings)

        let sheet = try #require(router.sheet)
        #expect(sheet.root == .settings)
        #expect(sheet.router.parent === router)

        sheet.router.push(.notifications)
        #expect(sheet.router.path == [.notifications])
        #expect(router.path.isEmpty)
    }

    @Test("Full-screen covers and sheets are exclusive")
    func exclusivity() {
        let router = Router<AppRoute>()
        router.present(.settings)
        router.present(.login, style: .fullScreenCover)

        #expect(router.sheet == nil)
        #expect(router.fullScreenCover?.root == .login)
    }

    @Test("dismiss, dismissPresented and dismissAll")
    func dismissal() throws {
        let root = Router<AppRoute>()
        root.present(.settings)
        let first = try #require(root.sheet?.router)
        first.present(.login)
        let second = try #require(first.sheet?.router)

        #expect(root.topmost === second)
        #expect(second.root === root)

        second.dismiss()
        #expect(first.sheet == nil)
        #expect(root.sheet != nil)

        first.present(.login)
        let again = try #require(first.sheet?.router)
        again.dismissAll()
        #expect(root.presentation == nil)
    }
}

// MARK: - Guards

@Suite("Route guards")
@MainActor
struct GuardTests {
    @Test("A guard can redirect, present or deny")
    func decisions() {
        var isSignedIn = false
        var isPro = false
        let router = Router<AppRoute> { route in
            switch route {
            case .settings where !isSignedIn: .present(.login, style: .sheet)
            case .docs where !isPro: .redirect(.upgrade)
            case .notifications: .deny
            default: .allow
            }
        }

        router.push(.settings)
        #expect(router.path.isEmpty)
        #expect(router.sheet?.root == .login)

        router.dismissPresented()
        router.push(.docs(path: "intro"))
        #expect(router.path == [.upgrade])

        router.push(.notifications)
        #expect(router.path == [.upgrade])

        isSignedIn = true
        isPro = true
        router.push(.settings)
        router.push(.docs(path: "intro"))
        #expect(router.path == [.upgrade, .settings, .docs(path: "intro")])
    }

    @Test("Child routers inherit the guard")
    func inheritance() throws {
        let router = Router<AppRoute> { $0 == .notifications ? .deny : .allow }
        router.present(.settings)
        let child = try #require(router.sheet?.router)

        child.push(.notifications)
        #expect(child.path.isEmpty)
    }
}

// MARK: - State

@Suite("Navigation state")
@MainActor
struct StateTests {
    let nested = NavigationState<AppRoute>(
        path: [.article(id: 7)],
        presented: .init(
            style: .sheet,
            root: .settings,
            state: NavigationState(
                path: [.notifications],
                presented: .init(style: .fullScreenCover, root: .login)
            )
        )
    )

    @Test("Captures and re-applies a nested hierarchy")
    func roundTrip() throws {
        let router = Router<AppRoute>()
        router.apply(nested)

        #expect(router.path == [.article(id: 7)])
        let sheet = try #require(router.sheet)
        #expect(sheet.router.path == [.notifications])
        #expect(sheet.router.fullScreenCover?.root == .login)
        #expect(router.state == nested)
        #expect(router.state.modalDepth == 2)
    }

    @Test("Survives JSON encoding, as used for SceneStorage")
    func codable() throws {
        let data = try JSONEncoder().encode(nested)
        let decoded = try JSONDecoder().decode(NavigationState<AppRoute>.self, from: data)
        #expect(decoded == nested)

        let restored = Router<AppRoute>()
        restored.apply(decoded)
        #expect(restored.state == nested)
    }

    @Test("Applying state bypasses guards")
    func applyBypassesGuard() {
        let router = Router<AppRoute> { _ in .deny }
        router.apply(NavigationState(path: [.settings]))
        #expect(router.path == [.settings])
    }
}

// MARK: - Deep links

@Suite("Deep links")
@MainActor
struct DeepLinkTests {
    var resolver: DeepLinkResolver<NavigationState<AppRoute>> {
        var links = DeepLinkResolver<NavigationState<AppRoute>>(schemes: ["myapp"], hosts: ["example.com"])
        links.register("users/:id") { match in
            match["id"].map { NavigationState(path: [.profile(userID: $0)]) }
        }
        links.register("articles/:id") { match in
            match.int("id").map { NavigationState(path: [.article(id: $0)]) }
        }
        links.register("articles/:slug") { _ in
            NavigationState(path: [.upgrade])
        }
        links.register("docs/*") { match in
            NavigationState(path: [.docs(path: match["*"] ?? "")])
        }
        links.register("settings/notifications") { _ in
            NavigationState(path: [.settings, .notifications])
        }
        links.register("login") { _ in
            NavigationState(presented: .init(root: .login))
        }
        return links
    }

    @Test("Custom schemes treat the host as the first segment")
    func customScheme() {
        #expect(resolver.resolve(URL(string: "myapp://users/42")!) == NavigationState(path: [.profile(userID: "42")]))
        #expect(resolver.resolve(URL(string: "MYAPP://Settings/Notifications/")!)?.path == [.settings, .notifications])
    }

    @Test("Universal links are accepted only for known hosts")
    func universalLinks() {
        #expect(resolver.resolve(URL(string: "https://example.com/users/42")!)?.path == [.profile(userID: "42")])
        #expect(resolver.resolve(URL(string: "https://evil.example.org/users/42")!) == nil)
        #expect(resolver.resolve(URL(string: "otherapp://users/42")!) == nil)
    }

    @Test("A handler returning nil falls through to the next pattern")
    func fallthrough() {
        #expect(resolver.resolve(URL(string: "myapp://articles/12")!)?.path == [.article(id: 12)])
        #expect(resolver.resolve(URL(string: "myapp://articles/swift-6")!)?.path == [.upgrade])
    }

    @Test("Wildcards capture the rest of the path, percent-decoded")
    func wildcard() {
        let state = resolver.resolve(URL(string: "myapp://docs/guides/getting%20started")!)
        #expect(state?.path == [.docs(path: "guides/getting started")])
        #expect(resolver.resolve(URL(string: "myapp://docs")!)?.path == [.docs(path: "")])
    }

    @Test("Unknown paths and extra segments don't match")
    func noMatch() {
        #expect(resolver.resolve(URL(string: "myapp://users")!) == nil)
        #expect(resolver.resolve(URL(string: "myapp://users/42/extra")!) == nil)
        #expect(resolver.resolve(URL(string: "myapp://nope")!) == nil)
    }

    @Test("Query items are available to handlers")
    func query() {
        var links = DeepLinkResolver<String>(schemes: ["myapp"])
        links.register("search") { $0["q"] }
        #expect(links.resolve(URL(string: "myapp://search?q=swift%20macros&q=ignored")!) == "swift macros")
    }

    @Test("Handling a link dismisses modals and replaces the stack")
    func handling() throws {
        let router = Router<AppRoute>(path: [.settings])
        router.present(.login)
        let child = try #require(router.sheet?.router)

        #expect(child.handle(URL(string: "myapp://users/7")!, with: resolver))

        #expect(router.presentation == nil)
        #expect(router.path == [.profile(userID: "7")])
        #expect(!router.handle(URL(string: "myapp://unknown")!, with: resolver))
        #expect(router.path == [.profile(userID: "7")], "Unhandled links leave navigation untouched")
    }
}

// MARK: - Tabs

@Suite("TabRouter")
@MainActor
struct TabTests {
    @Test("Each tab keeps its own stack")
    func independentStacks() {
        let tabs = TabRouter<AppTab, AppRoute>(initial: .home)
        tabs.router(for: .home).push(.article(id: 1))
        tabs.select(.account)
        tabs.router(for: .account).push(.settings)

        #expect(tabs.router(for: .home).path == [.article(id: 1)])
        #expect(tabs.selectedRouter.path == [.settings])
    }

    @Test("Re-selecting the current tab pops it to root")
    func reselect() {
        let tabs = TabRouter<AppTab, AppRoute>(initial: .home)
        tabs.router(for: .home).push(.article(id: 1))
        tabs.router(for: .home).present(.login)

        tabs.select(.home)

        #expect(tabs.router(for: .home).path.isEmpty)
        #expect(tabs.router(for: .home).presentation == nil)
    }

    @Test("Deep links can target a tab")
    func tabDeepLink() {
        var links = DeepLinkResolver<(tab: AppTab, state: NavigationState<AppRoute>)>(schemes: ["myapp"])
        links.register("account/settings") { _ in (tab: .account, state: NavigationState(path: [.settings])) }

        let tabs = TabRouter<AppTab, AppRoute>(initial: .home)
        #expect(tabs.handle(URL(string: "myapp://account/settings")!, with: links))

        #expect(tabs.selection == .account)
        #expect(tabs.selectedRouter.path == [.settings])
    }

    @Test("Snapshots restore the selection and every tab")
    func snapshot() throws {
        let tabs = TabRouter<AppTab, AppRoute>(initial: .home)
        tabs.router(for: .home).push(.article(id: 3))
        tabs.select(.search)
        tabs.router(for: .search).present(.login)

        let data = try JSONEncoder().encode(tabs.state)
        let restored = TabRouter<AppTab, AppRoute>(initial: .home)
        restored.apply(try JSONDecoder().decode(TabRouter<AppTab, AppRoute>.Snapshot.self, from: data))

        #expect(restored.selection == .search)
        #expect(restored.router(for: .home).path == [.article(id: 3)])
        #expect(restored.router(for: .search).sheet?.root == .login)
    }
}
