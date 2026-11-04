import SwiftUI
import WebKit

/// Официальный SoundCloud-виджет для треков, у которых нет локального аудио.
/// Это легальный способ играть библиотеку SoundCloud без перехвата потоков;
/// нативный эквалайзер и оффлайн для таких треков недоступны.
struct SoundCloudEmbedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
