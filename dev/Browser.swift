// Glass Crate — BROWSE MEDIA ADD-ON (new in 1.2.0)
// A phone-sized browser on the LEFT side of the main window, under the same title bar
// (the Download Queue still slides out on the right). It's always shown, and follows the theme.
// It starts on a black "Browse Media" screen listing the sites below. Pick one to browse its mobile site,
// then click Add to Crate at the bottom to add the video or track you're on to the Download Queue,
// using the formats checked in the main window.
//
// Adding a site: add one line to `BrowseSite.all`.
// Browsing data (history, cookies, sign-ins) is kept in Glass Crate's own web storage,
// separate from Safari and Chrome, and Uninstall removes it (see Uninstaller.swift).

import SwiftUI
import AppKit
import WebKit

// MARK: - The sites

struct BrowseSite: Identifiable {
    let name: String
    let icon: String        // a generic SF Symbol, not the site's logo
    let address: URL        // the mobile site
    var id: String { name }

    /// The list on the Browse Media screen, in order. Add a line to add a site.
    static let all: [BrowseSite] = [
        BrowseSite(name: "YouTube", icon: "play.rectangle", address: URL(string: "https://m.youtube.com")!),
        BrowseSite(name: "SoundCloud", icon: "waveform", address: URL(string: "https://m.soundcloud.com")!),
    ]
}

extension Notification.Name {
    /// Sent by the browser's Download button. The link is the notification's object (a String).
    static let glassCrateDownloadLink = Notification.Name("glassCrateDownloadLink")
}

// MARK: - The browser itself (kept alive while the app runs, so closing the panel doesn't lose your place)

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = BrowserModel()

    @Published var showingHome = true          // the black Browse Media screen
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // Glass Crate's own storage, separate from Safari
        config.mediaTypesRequiringUserActionForPlayback = .all   // nothing plays until you press play
        webView = WKWebView(frame: .zero, configuration: config)
        // Ask sites for their phone layout, which fits the narrow panel
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        webView.allowsBackForwardNavigationGestures = true
        // (No fixed look: the browser follows the app's theme, so sites show their light look in light themes)
        super.init()
        webView.navigationDelegate = self
        // YouTube and SoundCloud change pages without fully reloading, so watch the address directly
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.url = w.url } },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoBack = w.canGoBack } },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoForward = w.canGoForward } },
            webView.observe(\.isLoading, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.isLoading = w.isLoading } },
        ]
    }

    func open(_ site: BrowseSite) {
        showingHome = false
        webView.load(URLRequest(url: site.address))
    }

    func back() {
        if webView.canGoBack { webView.goBack() } else { goHome() }
    }
    func forward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    /// Back to the Browse Media screen. Any video or song playing is paused.
    func goHome() {
        pauseMedia()
        showingHome = true
    }

    /// Pauses anything playing (used when the panel closes or goes back to Browse Media).
    func pauseMedia() {
        // Apple's own "pause everything" for the browser. It also catches players that aren't on the page
        // itself, like SoundCloud's, which the old way missed.
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(function(m){m.pause()})")
    }

    // MARK: What can be downloaded

    /// The link to download for the page you're on, or nil if it isn't a single video or track.
    var downloadLink: String? {
        guard !showingHome, let url, let host = url.host?.lowercased() else { return nil }
        // YouTube: a video (watch?v=…, shorts/…). The link is cleaned to just the video.
        if host.contains("youtu") {
            guard DownloadItem.youTubeID(from: url.absoluteString) != nil else { return nil }
            return DownloadItem.cleanLink(url.absoluteString)
        }
        // SoundCloud: a track looks like soundcloud.com/artist/track
        if host.hasSuffix("soundcloud.com") {
            let parts = url.pathComponents.filter { $0 != "/" }
            let notArtists: Set<String> = ["discover", "search", "you", "stream", "feed", "charts", "upload",
                                           "pages", "settings", "messages", "notifications", "people", "tags",
                                           "signin", "login", "mobile", "terms-of-use"]
            guard parts.count == 2, !notArtists.contains(parts[0].lowercased()),
                  !["sets", "likes", "tracks", "albums", "reposts", "followers", "following", "popular-tracks"]
                    .contains(parts[1].lowercased()) else { return nil }
            return "https://soundcloud.com/\(parts[0])/\(parts[1])"
        }
        return nil
    }

    // Links that try to open a new window (target="_blank") open right here instead
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url {
            webView.load(URLRequest(url: u))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Uninstall: deletes everything the browser stored (history, cookies, sign-ins, cached pages).
    static func removeAllBrowsingData(then done: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            // WebKit's own folders for this app, in case anything is left
            let fm = FileManager.default
            let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            if let id = Bundle.main.bundleIdentifier {
                for sub in ["WebKit/\(id)", "Caches/\(id)", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies"] {
                    try? fm.removeItem(at: lib.appendingPathComponent(sub))
                }
            }
            DispatchQueue.main.async { done() }
        }
    }
}

/// Puts the browser on screen.
private struct WebViewHost: NSViewRepresentable {
    let model: BrowserModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Rounded corners for the page, matching its outline
        nsView.wantsLayer = true
        nsView.layer?.cornerRadius = UIScale.s(10)
        nsView.layer?.masksToBounds = true
    }
}

// MARK: - The panel

struct BrowserPanel: View {
    @AppStorage(Appearance.key) private var themeMode = Appearance.defaultMode   // redraw when the theme changes
    @AppStorage(UIScale.key) private var uiScale = 1.0
    /// About the size of a phone screen; the window is this tall. Both follow Interface Size,
    /// and the height is limited on small screens so the window always fits.
    static var width: CGFloat { UIScale.s(400) }
    static var height: CGFloat { min(UIScale.s(740), (NSScreen.main?.visibleFrame.height ?? 900) - 60) }

    @ObservedObject private var model = BrowserModel.shared
    @AppStorage("wantVideo") private var wantVideo = true
    @AppStorage("wantMP3") private var wantMP3 = true
    @AppStorage("wantWAV") private var wantWAV = false
    @AppStorage("wantAIFF") private var wantAIFF = false

    private var anythingChecked: Bool { wantVideo || wantMP3 || wantWAV || wantAIFF }

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    /// The frame around the website: near-black in dark themes, light grey in light themes
    private var chrome: Color { dark ? Color(white: 0.06) : Color(white: 0.93) }
    /// The Sites list background: black in dark themes, a soft light grey in light themes
    private var homeBackground: Color { dark ? .black : Color(white: 0.97) }

    var body: some View {
        Group {
            if model.showingHome {
                home
            } else {
                // The page itself lives in BrowserModel, so going to Sites and back keeps your place.
                // The web page sits inside a rounded, outlined "screen", so it's clear where the
                // website ends and Glass Crate begins.
                VStack(spacing: 0) {
                    toolbar
                    WebViewHost(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: UIScale.s(10)))
                        .overlay(RoundedRectangle(cornerRadius: UIScale.s(10))
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1))
                        .padding(.horizontal, UIScale.s(10))
                    downloadBar
                }
                .background { chrome }
            }
        }
        .font(.gcBody)
        .overlay(alignment: .trailing) {
            // A clear edge between the browser and the rest of the window
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
        }
    }

    /// The start screen: "Browse Media" and the list of sites (black in dark themes, light in light themes).
    private var home: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Browse Media")
                .font(.gcTitle)
                .foregroundStyle(.primary)
                .padding(.bottom, UIScale.s(6))
            Text("Find a video or track, then click Add to Crate.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .padding(.bottom, UIScale.s(20))
            ForEach(BrowseSite.all) { site in
                Button { model.open(site) } label: {
                    HStack(spacing: UIScale.s(14)) {
                        Image(systemName: site.icon)
                            .font(.system(size: UIScale.s(20)))
                            .frame(width: UIScale.s(28))
                        Text(site.name).font(.gcHeadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.gcCallout)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                    .padding(UIScale.s(14))
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, UIScale.s(8))
            }
            Spacer()
        }
        .padding(UIScale.s(24))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { homeBackground }   // (this form stays below the title bar, which keeps its own color)
    }

    /// Back, Forward, Reload, and Sites (the list of sites), with the site's address in the middle.
    private var toolbar: some View {
        HStack(spacing: UIScale.s(14)) {
            Button { model.back() } label: { Image(systemName: "chevron.left") }
                .help("Back").accessibilityLabel("Back")
            Button { model.forward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)
                .help("Forward").accessibilityLabel("Forward")
            Spacer(minLength: 4)
            Text(model.url?.host?.replacingOccurrences(of: "www.", with: "") ?? "")
                .font(.gcCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { model.isLoading ? model.stop() : model.reload() } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(model.isLoading ? "Stop" : "Reload").accessibilityLabel(model.isLoading ? "Stop" : "Reload")
            // Back to the list of sites. Labeled, since an icon alone wasn't clear.
            Button { model.goHome() } label: {
                Label("Sites", systemImage: "square.grid.2x2")
                    .labelStyle(.titleAndIcon)
                    .font(.gcCaption.weight(.semibold))
            }
            .help("Back to the list of sites").accessibilityLabel("Back to the list of sites")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(0.85))
        .font(.system(size: UIScale.s(15), weight: .medium))
        .padding(.horizontal, UIScale.s(14))
        .padding(.vertical, UIScale.s(10))
    }

    /// Add to Crate: adds the video or track you're on to the Download Queue.
    private var downloadBar: some View {
        let link = model.downloadLink
        // SoundCloud always works: it saves audio only (an MP3 if no audio format is checked)
        let ready = link != nil && (anythingChecked || DownloadItem.isAudioOnly(link ?? ""))
        return VStack(spacing: UIScale.s(4)) {
            AddToCrateButton(enabled: ready, font: .gcHeadline) {
                if let link { NotificationCenter.default.post(name: .glassCrateDownloadLink, object: link) }
            }
            Text(link == nil ? "Open a video or track to add it."
                 : DownloadItem.isAudioOnly(link ?? "") ? "Audio only: uses the audio formats checked on the right."
                 : !anythingChecked ? "Check a format on the right first."
                 : "Uses the formats checked on the right.")
                .font(.gcCaption)
                .foregroundStyle(.secondary)
        }
        .padding(UIScale.s(12))
    }
}

/// The "Add to Crate" button, the same everywhere (the browser and the main window), so it's
/// always clear it's Glass Crate's button and not part of a website or an ad.
struct AddToCrateButton: View {
    let enabled: Bool
    var font: Font = .gcHeadline
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add to Crate", systemImage: "arrow.down.circle.fill")
                .font(font)
                .frame(maxWidth: .infinity)
                .padding(.vertical, UIScale.s(8))
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: UIScale.s(8))
                    .fill(enabled ? Color.gcAccent : Color.secondary.opacity(0.35)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
