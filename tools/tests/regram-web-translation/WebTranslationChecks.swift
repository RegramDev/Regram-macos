import AppKit
import WebKit
import Foundation

@main final class WebTranslationChecks: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private let webView = WKWebView()

    static func main() {
        let app = NSApplication.shared
        let delegate = WebTranslationChecks()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        webView.navigationDelegate = self
        webView.frame = CGRect(x: 0, y: 0, width: 500, height: 600)
        webView.loadHTMLString("""
        <h1>Hello world</h1><p><span>Text &amp; symbols</span><a href="https://example.com/path?x=1">A link</a></p>
        <input value="Private input"><textarea>Private textarea</textarea><pre>Code</pre><code>Inline code</code>
        <form><p>Private form</p></form><p contenteditable>Private editor</p><p hidden>Hidden text</p>
        <p style="display:none">Invisible text</p><p aria-hidden="true">Hidden accessibility text</p><p translate="no">Untouched</p>
        <iframe srcdoc="<p>Private frame</p>"></iframe>
        """, baseURL: URL(string: "https://example.com"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fatalError("WebKit fixture timed out") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluate(RegramWebTranslationScript.collect) { value in
            precondition(value as? [String] == ["Hello world", "Text & symbols", "A link"], String(describing: value))
            let translated = "Quote '\" \\ newline\n<script>window.injected=1</script> 中文"
            self.evaluate(RegramWebTranslationScript.apply(index: 0, translation: translated)!) { _ in
                self.webView.evaluateJavaScript("[document.querySelector('h1').textContent, document.querySelector('input').value, document.querySelector('a').getAttribute('href'), window.injected || null, document.querySelector('textarea').textContent]") { value, error in
                    precondition(error == nil)
                    let values = value as! [Any]
                    precondition(values[0] as? String == translated)
                    precondition(values[1] as? String == "Private input")
                    precondition(values[2] as? String == "https://example.com/path?x=1")
                    precondition(values[3] is NSNull)
                    precondition(values[4] as? String == "Private textarea")
                    self.evaluate(RegramWebTranslationScript.restore) { _ in
                        self.webView.evaluateJavaScript("document.querySelector('h1').textContent") { value, error in
                            precondition(error == nil && value as? String == "Hello world")
                            self.evaluate(RegramWebTranslationScript.collect) { _ in
                                self.evaluate(RegramWebTranslationScript.apply(index: 0, translation: "Translated")!) { _ in
                                    self.webView.evaluateJavaScript("document.querySelector('h1').textContent = 'Site update'; document.body.insertAdjacentHTML('beforeend', '<p>Dynamic text</p>')") { _, _ in
                                        self.evaluate(RegramWebTranslationScript.restore) { _ in
                                            self.webView.evaluateJavaScript("document.querySelector('h1').textContent") { value, _ in
                                                precondition(value as? String == "Site update")
                                                self.evaluate(RegramWebTranslationScript.collect) { value in
                                                    precondition((value as? [String])?.contains("Dynamic text") == true)
                                                    print("WebKit translation checks passed: readable text, private fields and frames excluded, escaped text, links preserved, reversible changes, dynamic content retained and collected")
                                                    NSApplication.shared.terminate(nil)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func evaluate(_ script: String, completion: @escaping (Any?) -> Void) {
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
            switch result {
            case let .success(value): completion(value)
            case let .failure(error): fatalError("\(error)")
            }
        }
    }
}
