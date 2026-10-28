// Glass Crate — BASE PROGRAM
// The app itself: startup, menu, and the main window.
//
// This is GlassCrate.swift, the base program.
// Add-on files (all built in automatically by build.sh):
//   Downloader.swift   one download: runs yt-dlp and reports progress
//   Queue.swift        the download queue and the Download Queue panel that slides out on the right
//   Browser.swift      Browse Media: a phone-sized browser on the left side of the main window (1.2.0)
//   Tagging.swift      artist/album tags, album art, hidden signature
//   Setup.swift        downloads yt-dlp, ffmpeg, ffprobe, and Deno the first time (no Homebrew)
//   Updates.swift      Settings → Updates: check, download, and install tool updates, each on its own
//   Uninstaller.swift  Uninstall (Settings → Uninstall, and the menu item)
//   Appearance.swift   Light / Dark / Match System
//   Settings.swift     the Settings window: General, Downloads, Updates, and Uninstall tabs
//   About.swift        the "About this app" window
//   About.md           the text shown in the About window (plain text, edit freely)
//   CHANGELOG.md       the text shown in the What's New window (add each version at the top)

import SwiftUI
import AppKit

// MARK: - App

/// Glass Crate's home on GitHub: the code, the downloads (Releases), and where to report problems.
enum Links {
    static let github = URL(string: "https://github.com/nine00p/glasscrate")!
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting (⌘Q, or the main window's close button) while downloads are running or waiting:
    /// ask first. The queue is saved either way, and comes back paused next time.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let queue = DownloadQueue.shared
        let running = queue.runningCount
        let waiting = queue.waitingCount
        guard running + waiting > 0, !queue.isQuitting else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Downloads are still running"
        alert.informativeText = "Are you sure you want to quit? Your Download Queue is saved. When you open Glass Crate again, you can resume each download, or all of them at once, and they'll continue where they left off."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Downloading")   // first: Return keeps the app open, the safe choice
        let quit = alert.addButton(withTitle: "Quit")
        quit.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        queue.stopAll()
        return .terminateNow
    }

    /// Closing the app before setup is finished (Quit, ⌘Q, or the close button)
    /// removes anything setup downloaded, so nothing is left behind.
    func applicationWillTerminate(_ notification: Notification) {
        ToolManager.shared.cleanUpIfSetupIncomplete()
    }
}

@main
struct GlassCrateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Glass Crate") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands { AppMenu() }

        Window("About Glass Crate", id: "about") {
            AboutView()
                .glassCrateWindow()
        }
        .windowResizability(.contentSize)

        Window("What's New in Glass Crate", id: "whatsnew") {
            AboutView(resource: "CHANGELOG", showVersion: false)
                .glassCrateWindow()
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView()
                .glassCrateWindow()
        }
        .windowResizability(.contentSize)
    }
}

/// Items in the app's menu (top left, next to the Apple menu).
struct AppMenu: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Glass Crate") { openWindow(id: "about") }
            Button("What's New") { openWindow(id: "whatsnew") }
            Button("Check for Updates…") {
                UserDefaults.standard.set("updates", forKey: "settingsTab")
                openWindow(id: "settings")
                UpdateManager.shared.check()
            }
            Divider()
            Button("Uninstall Glass Crate…") { Uninstaller.run() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                UserDefaults.standard.set("general", forKey: "settingsTab")
                openWindow(id: "settings")
            }
                .keyboardShortcut(",")
        }
    }
}

// MARK: - Main window

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var queue = DownloadQueue.shared
    @State private var showQueue = false          // the Downloads drawer on the right
    @AppStorage(UIScale.key) private var uiScale = 1.0              // Settings → General → Interface Size
    @ObservedObject private var tools = ToolManager.shared
    @ObservedObject private var updater = UpdateManager.shared
    @ObservedObject private var settingsWindow = SettingsWindow.shared   // so the gear lights up while Settings is open
    @ObservedObject private var browser = BrowserModel.shared            // to know when it's showing an audio-only site
    @State private var link = ""
    // Both boxes start checked; after that the app remembers how they were left last time
    @AppStorage("wantVideo") private var wantVideo = true
    @AppStorage("wantMP3") private var wantMP3 = true
    @AppStorage("wantWAV") private var wantWAV = false
    @AppStorage("wantAIFF") private var wantAIFF = false
    @AppStorage(SaveFolders.qualityKey) private var quality = "Best available"   // Settings → Downloads
    @AppStorage(SaveFolders.videoKey) private var videoPath = ""
    @AppStorage(SaveFolders.mp3Key) private var mp3Path = ""
    @AppStorage(SaveFolders.losslessKey) private var losslessPath = ""
    @AppStorage(SaveFolders.askKey) private var askEachTime = false
    @AppStorage(SaveFolders.lastAskedKey) private var lastAskedPath = ""
    @AppStorage(Appearance.key) private var appearance = Appearance.defaultMode   // Dark unless changed
    @AppStorage("keepOnTop") private var keepOnTop = false   // the pin button

    private var videoFolder: URL    { SaveFolders.url(SaveFolders.videoKey, path: videoPath) }
    private var mp3Folder: URL      { SaveFolders.url(SaveFolders.mp3Key, path: mp3Path) }
    private var losslessFolder: URL { SaveFolders.losslessURL(losslessPath: losslessPath, audioPath: mp3Path) }
    private var anythingChecked: Bool { wantVideo || wantMP3 || wantWAV || wantAIFF }
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The browser is showing an audio-only site (SoundCloud): only the Audio checkboxes show. Your MP4 setting doesn't change.
    private var browsingAudioOnly: Bool {
        !browser.showingHome && DownloadItem.isAudioOnly(browser.url?.absoluteString ?? "")
    }
    private var canDownload: Bool { !trimmedLink.isEmpty && anythingChecked && !tools.busy }

    var body: some View {
        Group {
            if tools.ready {
                // Browse Media on the left and the main controls on the right, in one window
                // under one title bar. The window is as tall as the browser. Everything follows Interface Size.
                HStack(spacing: 0) {
                    BrowserPanel()
                        .frame(width: BrowserPanel.width)
                    mainView
                        .font(.gcMainBody)   // the main window's text size (see Appearance.swift)
                        .padding(UIScale.s(24))
                        .frame(width: UIScale.s(640))
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(height: BrowserPanel.height)
                .id("\(appearance)-\(uiScale)")   // redraw everything when the theme or Interface Size changes
                    // The Download Queue panel is a separate drawer window attached to this one (see Queue.swift)
                    .background(WindowAccessor { window in
                        window.useGlassCrateBackground()          // matches the drawer and Settings
                        QueueDrawer.shared.parent = window
                        QueueDrawer.shared.setOnTop(keepOnTop)   // remembered from last time
                        QuitOnClose.attach(to: window)           // the red X quits the whole app
                        // Saved downloads: open the queue once the window has finished appearing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !queue.items.isEmpty { showQueue = true }
                        }
                    })
                    .onChange(of: keepOnTop) { QueueDrawer.shared.setOnTop($0) }
                    // The browser's Download button
                    .onReceive(NotificationCenter.default.publisher(for: .glassCrateDownloadLink)) { note in
                        if let l = note.object as? String { startDownload(from: l) }
                    }
                    .onChange(of: showQueue) { open in
                        if open {
                            QueueDrawer.shared.show(QueuePanel(queue: queue))
                        } else {
                            QueueDrawer.shared.hide()
                        }
                    }
            } else {
                SetupView()   // SetupView is in Setup.swift
                    .padding(UIScale.s(24))
                    .frame(width: UIScale.s(640))
            }
        }
        .font(.gcBody)        // default text size for everything in the window (see Appearance.swift)
        .controlSize(UIScale.controlSize)
        .glassCrateChrome()   // solid title bar and the theme's background
        .tint(Color.gcAccent)  // checkboxes use the theme's color
        .onAppear {
            Appearance.apply(appearance)
            tools.refresh()
            UpdateManager.shared.checkIfDue()   // automatic check, at most once a week; asks before updating
        }
        .onChange(of: appearance) { Appearance.apply($0) }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)   // the app's icon (from icon.png)
                    .resizable()
                    .frame(width: UIScale.s(36), height: UIScale.s(36))
                Text("Glass Crate").font(.gcMainTitle)
                Spacer()
                // Pin: keep Glass Crate on top of other windows (handy while browsing YouTube)
                Button { keepOnTop.toggle() } label: {
                    Image(systemName: keepOnTop ? "pin.fill" : "pin")
                        .font(.gcIcon)
                        .foregroundStyle(keepOnTop ? Color.gcAccent : Color.secondary)
                }
                .buttonStyle(.borderless)
                .hoverTip(keepOnTop ? "Stop keeping app on top" : "Keep app on top")
                // Download Queue: lights up when the queue is open; a small number shows how many are in it
                Button { showQueue.toggle() } label: {
                    Image(systemName: "sidebar.right")
                        .font(.gcIcon)
                        .foregroundStyle(showQueue ? Color.gcAccent : Color.secondary)
                        .overlay(alignment: .topTrailing) {
                            if !queue.items.isEmpty {
                                Text("\(queue.items.count)")
                                    .font(.system(size: UIScale.s(9), weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .background(Capsule().fill(showQueue ? Color.gcAccent : Color.gray))
                                    .offset(x: 8, y: -6)
                            }
                        }
                }
                .buttonStyle(.borderless)
                .hoverTip(showQueue ? "Close Download Queue" : "Open Download Queue")
                // Settings: lights up while the Settings window is open; click again to close it
                Button {
                    if settingsWindow.isOpen {
                        settingsWindow.close()
                    } else {
                        UserDefaults.standard.set("general", forKey: "settingsTab")
                        openWindow(id: "settings")
                    }
                } label: {
                    Image(systemName: settingsWindow.isOpen ? "gearshape.fill" : "gearshape")
                        .font(.gcIcon)
                        .foregroundStyle(settingsWindow.isOpen ? Color.gcAccent : Color.secondary)
                }
                .buttonStyle(.borderless)
                .hoverTip(settingsWindow.isOpen ? "Close Settings" : "Settings")
            }
            .zIndex(1)   // so the hover labels draw on top of the text below the header

            VStack(alignment: .leading, spacing: 4) {
                Text("Download video and audio")
                    .font(.gcMainHeadline)
                Text("Copy the link to any video, paste it in the box below, choose your options, and download.")
                    .font(.gcMainCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Links from some other sites may also work, but YouTube is the only officially supported site.")
                    .font(.gcMainCaption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Paste a link", text: $link)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canDownload { startDownload() } }

            // Video: [x] MP4   ...   Audio: [x] MP3 [x] WAV [x] AIFF
            // Video on the left edge and Audio on the right edge, lining up with the full-width Add to Crate.
            // Check any combination; each checked format is saved as its own file.
            // (Video quality is in Settings → Downloads.)
            HStack(spacing: 10) {
                // On an audio-only site (SoundCloud), the Video part disappears and only Audio shows.
                // The MP4 setting is kept, and comes back as it was for YouTube.
                if !browsingAudioOnly {
                    Text("Video:").font(.gcMainHeadline)
                    Toggle("MP4", isOn: $wantVideo)
                        .help("Quality: \(quality). Change it in Settings → Downloads.")
                }

                Spacer(minLength: UIScale.s(16))

                Text("Audio:").font(.gcMainHeadline)
                Toggle("MP3", isOn: $wantMP3)
                Toggle("WAV", isOn: $wantWAV)
                Toggle("AIFF", isOn: $wantAIFF)
            }
            .toggleStyle(.checkbox)

            // The same Add to Crate button as the browser's, so it's clearly Glass Crate's (not part of a website)
            AddToCrateButton(enabled: canDownload, font: .gcMainHeadline, action: startDownload)

            Spacer(minLength: 0)   // with the browser showing, the footer sits at the bottom of the window

            Divider()

            // Footer: "Glass Crate v1.3.0 · Open source on GitHub", all in plain grey.
            // The version opens What's New. "Update available" shows up only when there's something to do.
            HStack(spacing: 6) {
                Button("Glass Crate v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")) {
                    openWindow(id: "whatsnew")
                }
                .buttonStyle(.plain)
                .help("What's New · " + AboutView.versionText)
                Text("·")
                Button("Open source on GitHub") { NSWorkspace.shared.open(Links.github) }
                    .buttonStyle(.plain)
                    .help("See the code, get new versions, or report a problem")
                if updater.needsAttention {
                    Text("·")
                    // A small pill in the Mac's accent color: an update is available or downloaded and ready
                    Button {
                        UserDefaults.standard.set("updates", forKey: "settingsTab")
                        openWindow(id: "settings")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Update available")
                        }
                        .foregroundStyle(Color.gcAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gcAccent.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.gcMainCaption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    /// Add to Crate: adds the link to the queue with the options checked right now,
    /// clears the box for the next link, and slides out the Download Queue panel.
    /// Uses the folders set in Settings → Downloads, or asks first if "Ask each time" is on.
    private func startDownload() { startDownload(from: nil) }

    /// `from`: a link from the browser's Download button. Without it, the link in the box is used (and cleared).
    private func startDownload(from browserLink: String?) {
        guard anythingChecked || DownloadItem.isAudioOnly(browserLink ?? trimmedLink) else { NSSound.beep(); return }
        var v = videoFolder, m = mp3Folder, l = losslessFolder
        if askEachTime {
            let start = lastAskedPath.isEmpty
                ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                : URL(fileURLWithPath: lastAskedPath)
            guard let picked = SaveFolders.choose(startingAt: start,
                                                  message: "Choose where to save this download",
                                                  prompt: "Save Here") else { return }
            lastAskedPath = picked.path
            v = picked; m = picked; l = picked
        }
        let finalLink = DownloadItem.cleanLink(browserLink ?? trimmedLink)
        // Audio-only sites (SoundCloud): MP4 is left out of this download only. Your checkboxes stay
        // as they are, so YouTube downloads still get video. If no audio format is checked, it saves an MP3.
        var video = wantVideo, mp3 = wantMP3
        if DownloadItem.isAudioOnly(finalLink) {
            video = false
            if !(wantMP3 || wantWAV || wantAIFF) { mp3 = true }
        }
        queue.add(DownloadRequest(link: finalLink, video: video, mp3: mp3, wav: wantWAV, aiff: wantAIFF,
                                  quality: quality, videoFolder: v, mp3Folder: m, losslessFolder: l,
                                  binDir: tools.binDir.path))
        if browserLink == nil { link = "" }
        showQueue = true
    }
}
