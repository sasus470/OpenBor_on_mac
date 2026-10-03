import SwiftUI
import WebKit
import ImageIO

enum CoverImageLoader {
    static let maximumBytes = 12 * 1024 * 1024

    enum Failure: LocalizedError {
        case invalidImage, tooLarge, downloadFailed, invalidURL
        var errorDescription: String? {
            UIStrings.text(self == .tooLarge ? "Cover too large" : self == .downloadFailed ? "Cover download failed" : "Invalid cover image")
        }
    }

    static func selectionURL(_ value: String) -> URL? {
        guard value.count <= maximumBytes * 2, let url = URL(string: value),
              ["https", "http", "data"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        if url.scheme != "data", url.host == nil || url.user != nil || url.password != nil { return nil }
        return url
    }

    static func normalizedPNG(_ data: Data) throws -> Data {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_000_000 / height else { throw Failure.invalidImage }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 1600,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure.invalidImage }
        return png
    }

    static func fetch(_ url: URL) async throws -> Data {
        guard selectionURL(url.absoluteString) != nil else { throw Failure.invalidURL }
        if url.scheme == "data" {
            let parts = url.absoluteString.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].lowercased().hasPrefix("data:image/"),
                  parts[0].lowercased().hasSuffix(";base64"),
                  let data = Data(base64Encoded: String(parts[1])) else { throw Failure.invalidImage }
            return try normalizedPNG(data)
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw Failure.downloadFailed }
        guard response.expectedContentLength <= maximumBytes else { throw Failure.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw Failure.tooLarge }
            data.append(byte)
        }
        return try normalizedPNG(data)
    }
}

@MainActor
final class CoverBrowserModel: ObservableObject {
    @Published var query: String
    @Published var imageData: Data?
    @Published var selectedURL: URL?
    @Published var isLoadingPage = false
    @Published var isLoadingImage = false
    @Published var usingThumbnail = false
    @Published var errorText: String?
    @Published var canGoBack = false
    @Published var canGoForward = false
    let webView: WKWebView
    private let bridge = CoverBrowserBridge()
    private var selectionTask: Task<Void, Never>?
    private var selectionRevision = UUID()

    // Select actual images only; prefer the search result's original source URL.
    static let selectionScript = #"""
    document.addEventListener('click', function(event) {
        const img = event.target.closest && event.target.closest('img');
        if (!img || Math.max(img.width, img.naturalWidth) < 80 || Math.max(img.height, img.naturalHeight) < 80) return;
        let source = img.currentSrc || img.src;
        const result = img.closest('[m]');
        if (result) {
            try { source = JSON.parse(result.getAttribute('m')).murl || source; } catch (_) {}
        }
        if (!source || !/^(https?:|data:image\/)/i.test(source)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        window.webkit.messageHandlers.coverSelection.postMessage({source: source, thumbnail: img.currentSrc || img.src});
    }, true);
    """#

    init(title: String) {
        let cleanTitle = title.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        query = "\(cleanTitle.isEmpty ? title : cleanTitle) OpenBOR cover"
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(WKUserScript(source: Self.selectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        webView = WKWebView(frame: .zero, configuration: configuration)
        bridge.model = self
        configuration.userContentController.add(bridge, contentWorld: .defaultClient, name: "coverSelection")
        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
    }

    static func searchURL(for query: String) -> URL {
        var components = URLComponents(string: "https://www.bing.com/images/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }

    func search() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        selectionTask?.cancel()
        selectionRevision = UUID()
        imageData = nil
        selectedURL = nil
        isLoadingImage = false
        usingThumbnail = false
        errorText = nil
        webView.load(URLRequest(url: Self.searchURL(for: query)))
    }

    func selectImage(_ source: String, thumbnail: String? = nil) {
        guard let url = CoverImageLoader.selectionURL(source) else { return }
        selectionTask?.cancel()
        let revision = UUID()
        selectionRevision = revision
        selectedURL = url
        imageData = nil
        errorText = nil
        isLoadingImage = true
        usingThumbnail = false
        let fallbackURL = thumbnail.flatMap(CoverImageLoader.selectionURL)
        selectionTask = Task { [weak self] in
            do {
                let data: Data
                var usedFallback = false
                do { data = try await CoverImageLoader.fetch(url) }
                catch {
                    try Task.checkCancellation()
                    guard let fallbackURL, fallbackURL != url else { throw error }
                    data = try await CoverImageLoader.fetch(fallbackURL)
                    usedFallback = true
                }
                guard let self, !Task.isCancelled, self.selectionRevision == revision else { return }
                self.imageData = data
                self.isLoadingImage = false
                self.usingThumbnail = usedFallback
            } catch {
                guard let self, !Task.isCancelled, self.selectionRevision == revision else { return }
                self.errorText = UIStrings.text("Cover download failed")
                self.isLoadingImage = false
            }
        }
    }

    func shutdown() {
        selectionTask?.cancel()
        selectionRevision = UUID()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "coverSelection", contentWorld: .defaultClient)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}

@MainActor
private final class CoverBrowserBridge: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var model: CoverBrowserModel?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let selection = message.body as? [String: String], let source = selection["source"] else { return }
        model?.selectImage(source, thumbnail: selection["thumbnail"])
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        model?.isLoadingPage = true
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.isLoadingPage = false
        model?.canGoBack = webView.canGoBack
        model?.canGoForward = webView.canGoForward
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        model?.isLoadingPage = false
        model?.errorText = UIStrings.text("Cover search unavailable")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        decisionHandler(["http", "https", "about"].contains(scheme ?? "") ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") { webView.load(navigationAction.request) }
        return nil
    }
}

private struct CoverWebView: NSViewRepresentable {
    let browser: CoverBrowserModel
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct CoverBrowserView: View {
    @StateObject private var browser: CoverBrowserModel
    @ObservedObject private var language = InterfaceLanguagePreferences.shared
    @Environment(\.dismiss) private var dismiss
    let game: GameEntry
    let onImport: (Data) throws -> Void

    init(game: GameEntry, onImport: @escaping (Data) throws -> Void) {
        self.game = game
        self.onImport = onImport
        _browser = StateObject(wrappedValue: CoverBrowserModel(title: game.title))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UIStrings.text("Search covers online").uppercased()).font(.custom("Menlo-Bold", size: 18)).foregroundStyle(ArcadePalette.amber)
                    Text(game.title).lineLimit(1)
                }
                Spacer()
                Button(UIStrings.text("Cancel")) { dismiss() }
            }
            HStack {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canGoBack)
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!browser.canGoForward)
                TextField(UIStrings.text("Cover search query"), text: $browser.query).textFieldStyle(.roundedBorder).onSubmit { browser.search() }
                Button(UIStrings.text("Search")) { browser.search() }
                if browser.isLoadingPage { ProgressView().controlSize(.small) }
            }
            Text(UIStrings.text("Cover browser help")).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                CoverWebView(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    Text(UIStrings.text("Cover preview").uppercased()).font(.custom("Menlo-Bold", size: 11)).foregroundStyle(ArcadePalette.amber)
                    ZStack {
                        ArcadePalette.ink
                        if let data = browser.imageData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFit()
                        } else if browser.isLoadingImage {
                            ProgressView()
                        } else {
                            Image(systemName: "photo").font(.system(size: 32)).foregroundStyle(.secondary)
                        }
                    }.frame(height: 260)
                    if let url = browser.selectedURL {
                        Text(url.host ?? UIStrings.text("Embedded image")).font(.custom("Menlo", size: 10)).lineLimit(2).foregroundStyle(.secondary)
                    }
                    Button(UIStrings.text("Use this cover")) {
                        guard let data = browser.imageData else { return }
                        do { try onImport(data); dismiss() }
                        catch { browser.errorText = UIStrings.text("Cover import failed") }
                    }.buttonStyle(ArcadeButtonStyle(prominent: true)).disabled(browser.imageData == nil || browser.isLoadingImage)
                    if let error = browser.errorText { Text(error).foregroundStyle(ArcadePalette.amber).font(.custom("Menlo", size: 10)) }
                    if browser.usingThumbnail { Text(UIStrings.text("Using search thumbnail")).foregroundStyle(ArcadePalette.amber).font(.custom("Menlo", size: 10)) }
                    Spacer(minLength: 0)
                    Text(UIStrings.text("Cover rights help")).foregroundStyle(.secondary).font(.custom("Menlo", size: 10))
                }.frame(width: 210)
            }
        }
        .padding(20).frame(width: 900, height: 600)
        .background(ArcadePalette.ink).foregroundStyle(ArcadePalette.cream)
        .font(.custom("Menlo", size: 12)).buttonStyle(ArcadeButtonStyle())
        .environment(\.colorScheme, .dark)
        .task { browser.search() }
        .onDisappear { browser.shutdown() }
        .onExitCommand { dismiss() }
    }
}
