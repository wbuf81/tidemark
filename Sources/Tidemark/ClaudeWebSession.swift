import AppKit
import WebKit
import TidemarkCore

/// Whether a deadline race has already been settled, and how to end it early (`shutDown`).
private final class DeadlineBox {
    var done = false
    var abort: (() -> Void)?
}

/// The app's own claude.ai session, kept in the app's website data store (separate from
/// Safari, Chrome and the Claude desktop app). Requests run as fetch() inside a hidden
/// claude.ai page (same-origin), so the browser sends the session cookie. Only GET requests are ever made.
///
/// The hidden page is a tiny claude.ai document rather than the claude.ai web app, so no
/// site scripts run all day. There is no workaround for the site's bot check: a request it blocks
/// is reported as blocked ("Blocked by a bot check"), and nothing pretends to be another browser.
///
/// Nothing here exists until the owner turns plan limits on: no web view is made, no request is
/// sent and the website data store isn't opened. Every page load and request ends within 20
/// seconds, and `shutDown()` (plan limits off, Delete all, Uninstall) closes the sign-in window,
/// ends the watch for a sign-in, cancels what is in flight and lets the web views go.
@MainActor
final class ClaudeWebSession: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var onSignedIn: (() -> Void)?
    /// Whether the sign-in window is on screen, so the app can keep its Dock icon while it is.
    var onWindowVisibility: ((Bool) -> Void)?
    /// Whether asking claude.ai is allowed right now (plan limits on, no demo data): `UsageGate`.
    /// Checked by every request and every pass of the sign-in watch.
    var mayRequest: () -> Bool = { true }

    private static let home = URL(string: "https://claude.ai/robots.txt")!
    private static let login = URL(string: "https://claude.ai/login")!
    /// How long a page load or a request may take before it counts as offline.
    static let timeLimit: TimeInterval = 20

    /// Tidemark's own store, by its fixed ID: separate from Safari, Chrome and the Claude app.
    private var openedStore: WKWebsiteDataStore?
    private var dataStore: WKWebsiteDataStore {
        if let openedStore { return openedStore }
        let store = WKWebsiteDataStore(forIdentifier: AppIdentity.webStoreID)
        openedStore = store
        return store
    }
    private var hiddenView: WKWebView?
    private var fetcher: WKWebView {
        if let hiddenView { return hiddenView }
        let view = makeWebView()
        hiddenView = view
        return view
    }
    private var page = PageLoadState()
    private var watch: Task<Void, Never>?
    private var deadlines: [ObjectIdentifier: DeadlineBox] = [:]
    private var loadNumber = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var signInWindow: NSWindow?
    private var signInView: WKWebView?
    /// Windows the sign-in page opened (Google and single sign-on use pop-ups).
    private var popups: [NSWindow] = []

    /// GETs a claude.ai API path and returns the response body. Gives up after 20 seconds, the page
    /// load and the request together.
    func getJSON(_ path: String) async throws -> Data {
        guard mayRequest() else { throw CancellationError() }
        let (status, body) = try await withDeadline(Self.timeLimit) { [self] in try await fetch(path) }
        switch SessionResponse.classify(status: status, body: body) {
        case .ok:
            return Data(body.utf8)
        case .signedOut:
            throw WebSessionError.signedOut
        case .forbidden:
            throw WebSessionError.forbidden
        case .blocked:
            page.invalidate()
            throw WebSessionError.blocked
        case .failed(let code):
            throw WebSessionError.http(code)
        }
    }

    /// One request inside the hidden page. The page's own `fetch` is cut off at the time limit too.
    private func fetch(_ path: String) async throws -> (Int, String) {
        try await loadFetcher()
        let script = """
        const r = await fetch(path, { credentials: 'include', headers: { accept: 'application/json' },
                                      signal: AbortSignal.timeout(limit * 1000) });
        return { status: r.status, body: await r.text() };
        """
        let value: Any?
        do {
            value = try await fetcher.callAsyncJavaScript(script, arguments: ["path": path, "limit": Self.timeLimit],
                                                          in: nil, contentWorld: .page)
        } catch {
            page.invalidate()  // the page broke; load it again next time
            throw error
        }
        guard let result = value as? [String: Any],
              let status = (result["status"] as? NSNumber)?.intValue,
              let body = result["body"] as? String else { throw WebSessionError.badResult }
        return (status, body)
    }

    /// Runs `work`, but stops waiting for it after `seconds` (a wedged page never answers) or when
    /// `shutDown()` ends it.
    private func withDeadline<T>(_ seconds: TimeInterval, _ work: @escaping () async throws -> T) async throws -> T {
        let box = DeadlineBox()
        let id = ObjectIdentifier(box)
        deadlines[id] = box
        defer { deadlines[id] = nil }
        return try await withCheckedThrowingContinuation { continuation in
            box.abort = { continuation.resume(throwing: CancellationError()) }
            Task { @MainActor in
                do {
                    let value = try await work()
                    if !box.done { box.done = true; continuation.resume(returning: value) }
                } catch {
                    if !box.done { box.done = true; continuation.resume(throwing: error) }
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if !box.done {
                    box.done = true
                    self?.page.invalidate()
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        }
    }

    func showSignIn() {
        guard mayRequest() else { return }
        if let window = signInWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = makeWebView()
        view.uiDelegate = self
        let window = SignInWindow.make(page: view, target: self, openLink: #selector(openCopiedLink))
        window.delegate = self
        view.load(URLRequest(url: Self.login))
        window.center()
        signInWindow = window
        signInView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onWindowVisibility?(true)
        watchForSignIn()
    }

    /// Plan limits off, Delete all or Uninstall: closes the sign-in window and its pop-ups, ends the watch
    /// for a sign-in, cancels every request in flight and releases the web views, so nothing of claude.ai
    /// is left running or loaded.
    func shutDown() {
        watch?.cancel()
        watch = nil
        let pending = Array(deadlines.values)
        deadlines.removeAll()
        for box in pending where !box.done {
            box.done = true
            box.abort?()
        }
        closePopups()
        if let window = signInWindow {
            signInWindow = nil
            window.delegate = nil
            window.close()
            onWindowVisibility?(false)
        }
        signInView?.stopLoading()
        signInView = nil
        hiddenView?.stopLoading()
        hiddenView = nil
        loadNumber += 1
        page = PageLoadState()
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    /// Deletes every cookie and stored item in this app's web store: claude.ai's, and those
    /// of any Google or single sign-on page used to sign in.
    func signOut() async {
        // A store that was never opened holds nothing; opening it just to empty it would make it.
        guard openedStore != nil || Self.storeFolderExists else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records)
        page.invalidate()
    }

    /// Whether this app's WebKit folder exists, which it does only once the store has been used.
    private static var storeFolderExists: Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/WebKit/\(AppIdentity.bundleID)").path)
    }

    /// Loads a claude.ai link from the clipboard (a sign-in link from an email) in the
    /// sign-in window. Anything else is refused.
    @objc private func openCopiedLink() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: text), url.scheme == "https",
              let host = url.host?.lowercased(), host == "claude.ai" || host.hasSuffix(".claude.ai") else {
            NSSound.beep()
            return
        }
        signInView?.load(URLRequest(url: url))
    }

    // MARK: Pop-ups

    /// Google and single sign-on open their sign-in in a pop-up that talks back to the page
    /// that opened it, so it gets a real window sharing this session.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let size = NSSize(width: windowFeatures.width?.doubleValue ?? 500, height: windowFeatures.height?.doubleValue ?? 640)
        let popup = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        popup.uiDelegate = self
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        popups.append(window)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.filter { $0.contentView === webView }.forEach { $0.close() }
    }

    /// A pop-up closed by its page or its close button: stop it and let it go.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === signInWindow {
            watch?.cancel()
            watch = nil
            signInWindow = nil
            signInView?.stopLoading()
            signInView = nil
            closePopups()
            onWindowVisibility?(false)
            return
        }
        guard popups.contains(where: { $0 === window }) else { return }
        (window.contentView as? WKWebView)?.stopLoading()
        popups.removeAll { $0 === window }
    }

    private func closePopups() {
        popups.forEach { $0.close() }
    }

    // MARK: Private

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 640), configuration: config)
        view.navigationDelegate = self
        return view
    }

    /// Loads the hidden page if needed. Callers that arrive while a load is running wait for
    /// it instead of starting another, and everyone fails fast if the load fails.
    private func loadFetcher() async throws {
        if page.isReady { return }
        if page.claimLoad() {
            loadNumber += 1
            let number = loadNumber
            fetcher.load(URLRequest(url: Self.home))
            // A page that never finishes loading counts as offline after the time limit.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.timeLimit))
                guard let self, self.loadNumber == number, !self.page.isReady else { return }
                guard let view = self.hiddenView else { return }
                view.stopLoading()
                self.finished(view, ok: false)
            }
        }
        await withCheckedContinuation { waiters.append($0) }
        guard page.isReady else { throw WebSessionError.notReady }
    }

    /// The sign-in page is a web app that may not fire navigation events when it finishes,
    /// so poll for a working session every 2 seconds while the window is open (and while asking
    /// claude.ai is still allowed).
    private func watchForSignIn() {
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                guard self.mayRequest() else { self.shutDown(); return }
                guard let window = self.signInWindow, window.isVisible else { return }
                if (try? await self.getJSON("/api/organizations")) != nil, !Task.isCancelled {
                    self.signInWindow = nil
                    self.signInView = nil
                    window.delegate = nil
                    window.close()
                    self.closePopups()
                    self.onWindowVisibility?(false)
                    self.onSignedIn?()
                    return
                }
            }
        }
    }

    private func finished(_ webView: WKWebView, ok: Bool) {
        guard let hiddenView, webView === hiddenView else { return }
        page.finished(ok: ok)
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished(webView, ok: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finished(webView, ok: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finished(webView, ok: false)
    }

    /// macOS can end a hidden page's web process under memory pressure; reload it next time.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finished(webView, ok: false)
    }
}
