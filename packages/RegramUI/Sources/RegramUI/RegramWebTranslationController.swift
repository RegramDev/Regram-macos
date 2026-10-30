import Cocoa
import WebKit
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import Localization
import InputDataUI
import AlertsUI
import RegramCore
import RegramServices

private final class RegramWebpageTranslation {
    private weak var webView: WKWebView?
    private let context: any AccountContextProtocol
    private let request = MetaDisposable()
    private var generation = UUID()
    private var observer: NSObjectProtocol?
    private(set) var running = false
    private(set) var translated = false
    var changed: () -> Void = {}
    var failed: (String) -> Void = { _ in }

    init(webView: WKWebView, context: any AccountContextProtocol) {
        self.webView = webView
        self.context = context
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.restore() }
    }

    deinit {
        request.dispose()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func navigationChanged() {
        generation = UUID()
        request.set(nil)
        running = false
        translated = false
        changed()
    }

    func restore() {
        navigationChanged()
        evaluate(RegramWebTranslationScript.restore) { _, _ in }
    }

    private func evaluate(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        guard let webView else { completion(nil, nil); return }
        if #available(macOS 11.0, *) {
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                switch result {
                case let .success(value): completion(value, nil)
                case let .failure(error): completion(nil, error)
                }
            }
        } else {
            webView.evaluateJavaScript(script, completionHandler: completion)
        }
    }

    func start() {
        guard !running, let url = webView?.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        navigationChanged()
        let token = UUID()
        generation = token
        running = true
        changed()
        let accountId = context.peerId.toInt64()
        let settings = RegramPreferences.shared.settings(accountId: accountId)
        let language = appCurrentLanguage.primaryLanguage.languageCode
        evaluate(RegramWebTranslationScript.collect) { [weak self] value, error in
            guard let self, self.generation == token else { return }
            guard error == nil, let texts = value as? [String], !texts.isEmpty else { self.fail("webTranslation.noText", token: token); return }
            guard texts.count <= 2000, texts.reduce(0, { $0 + $1.utf8.count }) <= 500_000 else { self.fail("webTranslation.tooLarge", token: token); return }
            self.translate(texts, index: 0, language: language, settings: settings, token: token)
        }
    }

    private func fail(_ key: String, token: UUID) {
        guard generation == token else { return }
        running = false
        request.set(nil)
        changed()
        failed(regramString(key))
    }

    private func translate(_ texts: [String], index: Int, language: String, settings: RegramAccountSettings, token: UUID) {
        guard generation == token else { return }
        let accountId = context.peerId.toInt64()
        guard RegramPreferences.shared.settings(accountId: accountId).translationIdentity == settings.translationIdentity else { fail("webTranslation.outdated", token: token); return }
        guard texts.indices.contains(index) else { running = false; translated = true; changed(); return }
        let batch = Array(texts[index..<min(texts.count, index + 8)])
        let signal: Signal<[String], TranslateFetchError>
        if settings["translationBackend"].string == "default" {
            signal = context.engine.messages.translate(texts: batch.map { ($0, []) }, toLang: language) |> mapError { _ in TranslateFetchError.network } |> map { $0.map { $0.0 } }
        } else {
            signal = combineLatest(batch.map { regramProtectedTranslation(text: $0, to: language, accountId: accountId, settings: settings, ranges: [], protectedIds: []) |> map(\.text) })
        }
        request.set((signal |> timeout(120, queue: .mainQueue(), alternate: .fail(.network)) |> deliverOnMainQueue).start(next: { [weak self] values in
            guard let self, self.generation == token else { return }
            guard RegramPreferences.shared.settings(accountId: accountId).translationIdentity == settings.translationIdentity else { self.fail("webTranslation.outdated", token: token); return }
            let scripts = values.enumerated().compactMap { RegramWebTranslationScript.apply(index: index + $0.offset, translation: $0.element) }
            guard values.count == batch.count, scripts.count == batch.count else { self.fail("webTranslation.failed", token: token); return }
            self.evaluate(scripts.joined(separator: ";\n")) { [weak self] _, error in
                guard let self, self.generation == token else { return }
                guard error == nil else { self.fail("webTranslation.failed", token: token); return }
                self.translated = true
                self.changed()
                DispatchQueue.main.async { [weak self] in self?.translate(texts, index: index + batch.count, language: language, settings: settings, token: token) }
            }
        }, error: { [weak self] _ in self?.fail("webTranslation.failed", token: token) }))
    }
}

private final class RegramWebTranslationBrowserController: GenericViewController<RegramWebTranslationView>, WKNavigationDelegate, WKUIDelegate {
    private let context: any AccountContextProtocol
    private let url: URL
    private var translation: RegramWebpageTranslation?

    init(context: any AccountContextProtocol, url: URL) {
        self.context = context
        self.url = url
        super.init(frame: NSMakeRect(0, 0, 720, 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let webView = genericView.webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let translation = RegramWebpageTranslation(webView: webView, context: context)
        self.translation = translation
        translation.changed = { [weak self] in self?.updateControls() }
        translation.failed = { [weak self] text in if let self { alert(for: self.context.window, info: text) } }
        genericView.translate.target = self
        genericView.translate.action = #selector(translatePage)
        genericView.restore.target = self
        genericView.restore.action = #selector(restorePage)
        updateControls()
        webView.load(URLRequest(url: url))
        readyOnce()
    }

    override var defaultBarTitle: String { regramString("webTranslation.action") }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        if isLoaded() { genericView.updateTheme(); updateControls() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        translation?.restore()
        genericView.webView.stopLoading()
    }

    @objc private func translatePage() {
        if translation?.running == true { translation?.restore() } else { translation?.start() }
    }

    @objc private func restorePage() { translation?.restore() }

    private func updateControls() {
        genericView.translate.title = regramString(translation?.running == true ? "cancel" : "webTranslation.translate")
        genericView.translate.isEnabled = genericView.webView.url != nil && !genericView.webView.isLoading
        genericView.restore.isEnabled = translation?.translated == true || translation?.running == true
        genericView.status.stringValue = genericView.webView.url?.host ?? url.host ?? ""
        genericView.needsLayout = true
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { translation?.navigationChanged(); updateControls() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { updateControls() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { translation?.navigationChanged(); updateControls() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { translation?.navigationChanged(); updateControls() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil { webView.load(URLRequest(url: url)) }
        return nil
    }
}

public func RegramWebTranslationController(context: any AccountContextProtocol, url: URL) -> ViewController? {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return nil }
    return RegramWebTranslationBrowserController(context: context, url: url)
}

public func RegramWebTranslationURLController(context: any AccountContextProtocol) -> InputDataController {
    let identifier = InputDataIdentifier("web_translation_url")
    let rows: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .input(sectionId: 1, index: 0, value: .string(""), error: nil, identifier: identifier, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: "https://", filter: { $0 }, limit: 4096),
        .desc(sectionId: 1, index: 1, text: .plain(regramString("webTranslation.notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem))
    ]
    return RegramFormController(dataSignal: .single(InputDataSignalValue(entries: rows)), title: regramString("webTranslation.action"), validateData: { data in
        guard let text = data[identifier]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: text), let controller = RegramWebTranslationController(context: context, url: url) else { return .fail(.fields([identifier: .shake])) }
        context.bindings.rootNavigation().push(controller)
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: true, identifier: "regram.webTranslation", doneString: { regramString("webTranslation.open") })
}
