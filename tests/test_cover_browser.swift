import AppKit
import SwiftUI
import WebKit

@main
struct CoverBrowserTest {
    @MainActor
    static func main() throws {
        guard let rootPath = ProcessInfo.processInfo.environment["OPENBOR_FRONTEND_SUPPORT_ROOT"], rootPath.hasPrefix("/tmp/") else { fatalError("Isolated test root required") }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 140, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let blue = NSColor(deviceRed: 0.1, green: 0.4, blue: 0.8, alpha: 1)
        for y in 0..<180 { for x in 0..<140 { image.setColor(blue, atX: x, y: y) } }
        let png = image.representation(using: .png, properties: [:])!
        let dataURL = "data:image/png;base64," + png.base64EncodedString()
        precondition(CoverImageLoader.selectionURL("file:///etc/passwd") == nil)
        precondition(CoverImageLoader.selectionURL("javascript:alert(1)") == nil)
        precondition(CoverImageLoader.selectionURL("https://user:password@example.com/image.png") == nil)
        do { _ = try CoverImageLoader.normalizedPNG(Data("not an image".utf8)); fatalError("Invalid image accepted") } catch {}
        do { _ = try CoverImageLoader.normalizedPNG(Data(count: CoverImageLoader.maximumBytes + 1)); fatalError("Oversized image accepted") } catch {}
        let search = CoverBrowserModel.searchURL(for: "Hyper Duel & other covers")
        precondition(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Hyper Duel & other covers")
        let browser = CoverBrowserModel(title: "Hyper Duel [v.3.0 Build 3366]")
        defer { browser.shutdown() }
        precondition(browser.query == "Hyper Duel OpenBOR cover")
        precondition(!browser.webView.configuration.websiteDataStore.isPersistent)
        let host = NSHostingView(rootView: BrowserFixture(browser: browser))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let html = "<html><body><a m='{\"murl\":\"\(dataURL)\"}' href='https://example.com'><img src='\(dataURL)' width='140' height='180'></a></body></html>"
        browser.webView.loadHTMLString(html, baseURL: nil)
        wait("web fixture") { !browser.webView.isLoading && browser.webView.url != nil }
        var scriptComplete = false
        browser.webView.evaluateJavaScript("document.querySelector('img').click()") { _, error in
            precondition(error == nil)
            scriptComplete = true
        }
        wait("image click and preview") { scriptComplete && browser.imageData != nil && !browser.isLoadingImage }
        precondition(browser.selectedURL?.absoluteString == dataURL)
        let model = AppModel()
        let game = GameEntry(id: "fixture-cover", title: "Fixture Cover", pakURL: URL(fileURLWithPath: rootPath + "/fixture.pak"), modifiedAt: .now)
        precondition(model.coverURL(for: game) == nil, "Preview must not import automatically")
        try model.storeCoverData(browser.imageData!, for: game)
        let destination = model.coverURL(for: game)!
        let saved = try Data(contentsOf: destination)
        let imageRefresh = model.coverRefreshToken(for: game)
        precondition(NSImage(data: saved) != nil && destination.pathExtension == "png")
        do { try model.storeCoverData(Data("invalid".utf8), for: game); fatalError("Invalid cover stored") } catch {}
        let afterFailure = try Data(contentsOf: destination)
        precondition(saved == afterFailure && model.coverRefreshToken(for: game) == imageRefresh, "Failed import damaged the existing cover")
        URLProtocol.registerClass(ScreenScraperRequestProbe.self)
        let credentials = (model.screenScraperDeveloperID, model.screenScraperDeveloperPassword)
        defer {
            model.screenScraperDeveloperID = credentials.0
            model.screenScraperDeveloperPassword = credentials.1
            URLProtocol.unregisterClass(ScreenScraperRequestProbe.self)
        }
        model.screenScraperDeveloperID = "isolated-test"
        model.screenScraperDeveloperPassword = "isolated-test"
        model.games = [game]
        model.refreshRemoteCovers()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        precondition(ScreenScraperRequestProbe.requestCount == 0, "ScreenScraper attempted to replace a manual cover")
        browser.selectImage(dataURL)
        browser.selectImage("data:image/png;base64," + Data("bad image".utf8).base64EncodedString())
        wait("latest selection error") { !browser.isLoadingImage && browser.errorText != nil }
        precondition(browser.imageData == nil, "Stale image import raced the latest selection")
        browser.selectImage("data:image/png;base64," + Data("bad image".utf8).base64EncodedString(), thumbnail: dataURL)
        wait("thumbnail fallback") { browser.imageData != nil && !browser.isLoadingImage }
        precondition(browser.usingThumbnail)
        if ProcessInfo.processInfo.environment["TEST_SEARCH_WEB"] == "1" {
            browser.query = "Hyper Duel OpenBOR cover"
            browser.search()
            wait("online search", timeout: 30) { !browser.webView.isLoading && browser.webView.url?.host?.contains("bing.com") == true }
            var imageCount: Int?
            browser.webView.evaluateJavaScript("document.querySelectorAll('img').length") { value, _ in imageCount = value as? Int }
            wait("online results") { imageCount != nil }
            precondition(imageCount! > 2, "Online search returned no image results")
            print("PASS: live Bing image search loaded \(imageCount!) images.")
            var clicked = false
            browser.webView.evaluateJavaScript("const image = document.querySelector('[m] img'); if (image) image.click(); !!image;") { value, _ in clicked = value as? Bool == true }
            wait("online image preview", timeout: 45) { clicked && browser.imageData != nil && !browser.isLoadingImage }
            print("PASS: clicked online image loaded a validated preview.")
            let browserHost = NSHostingView(rootView: CoverBrowserView(game: game) { data in try model.storeCoverData(data, for: game) })
            window.setContentSize(NSSize(width: 900, height: 600))
            window.contentView = browserHost
            RunLoop.main.run(until: Date().addingTimeInterval(6))
            browserHost.layoutSubtreeIfNeeded()
            let bitmap = browserHost.bitmapImageRepForCachingDisplay(in: browserHost.bounds)!
            browserHost.cacheDisplay(in: browserHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: rootPath + "/cover-browser.png"))
        }
        print("PASS: embedded browser image click, original image selection, preview-before-import, atomic cover import, size/type/URL validation and selection cancellation.")
    }

    @MainActor
    static func wait(_ label: String, timeout: TimeInterval = 10, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        fatalError("Timeout: \(label)")
    }
}

private struct BrowserFixture: NSViewRepresentable {
    let browser: CoverBrowserModel
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private final class ScreenScraperRequestProbe: URLProtocol {
    private static let lock = NSLock()
    private static var requests = 0
    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.screenscraper.fr" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
    }
    override func stopLoading() {}
}
