// Glass Crate — SETTINGS ADD-ON
// The Settings window, in four tabs:
//   General:   Theme (Glass Crate: Light, Crimson, Dark, Blackout · System: Match System, Light, Dark) and Interface Size.
//   Downloads: save folders (Video and Audio, plus an optional separate folder for WAV/AIFF),
//              video quality, and "ask where to save each time".
//   Updates:   tool updates (the tab itself is in Updates.swift).
//   Uninstall: what's removed and what stays, and the Uninstall button.
// More settings can be added to this file later.

import SwiftUI
import AppKit

enum SaveFolders {
    // Where each choice is remembered
    static let videoKey     = "videoFolder"
    static let mp3Key       = "mp3Folder"
    static let losslessKey  = "losslessFolder"    // WAV and AIFF
    static let askKey       = "askEachTime"
    static let lastAskedKey = "lastAskedFolder"
    static let qualityKey   = "videoQuality"      // "Best available", "1080p", …
    static let qualities    = ["Best available", "1080p", "720p", "480p", "360p"]

    /// Default folders: a "Glass Crate" folder inside Movies for videos, and inside Music for all audio.
    /// The folders are created by the first download that uses them (yt-dlp makes missing folders).
    /// (If an older version had a single save folder set, that's used instead.)
    static func defaultURL(for key: String) -> URL {
        if let old = UserDefaults.standard.string(forKey: "saveFolder"), !old.isEmpty {
            return URL(fileURLWithPath: old)
        }
        let fm = FileManager.default
        switch key {
        case videoKey: return fm.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Glass Crate", isDirectory: true)
        case mp3Key:   return fm.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("Glass Crate", isDirectory: true)
        default:       return fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
    }

    /// The saved folder for Video or Audio, or its default.
    static func url(_ key: String, path: String) -> URL {
        path.isEmpty ? defaultURL(for: key) : URL(fileURLWithPath: path)
    }

    /// WAV/AIFF folder: same as the Audio folder unless the user picked a separate one.
    static func losslessURL(losslessPath: String, audioPath: String) -> URL {
        losslessPath.isEmpty ? url(mp3Key, path: audioPath) : URL(fileURLWithPath: losslessPath)
    }

    /// Shows a folder picker. Returns nil if the user cancels.
    static func choose(startingAt start: URL, message: String, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func shortPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - The Settings window (gear button, ⌘, or the Updates link)

/// One folder line in Settings: icon, name, current folder, and a Change… button.
private struct FolderRow: View {
    let icon: String
    let title: String
    let key: String
    @Binding var path: String
    /// The folder to show, if it isn't simply this setting's own folder (WAV/AIFF uses the Audio folder until changed)
    var shownURL: URL? = nil

    var body: some View {
        let url = shownURL ?? SaveFolders.url(key, path: path)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.gcHeadline)
                Text(SaveFolders.shortPath(url))
                    .font(.gcCallout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Change…") {
                if let picked = SaveFolders.choose(startingAt: url, message: "Choose where to save \(title) files") {
                    path = picked.path
                }
            }
        }
    }
}

/// Keeps track of the Settings window, so the gear can light up while it's open
/// and close it when clicked again (handy with two screens).
final class SettingsWindow: ObservableObject {
    static let shared = SettingsWindow()
    @Published private(set) var isOpen = false
    private weak var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    fileprivate func attach(_ w: NSWindow) {
        window = w
        isOpen = true
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak self] _ in self?.isOpen = false }
    }

    func close() { window?.close() }
}

/// The tabs, in order: id, name, and icon.
private let settingsTabs: [(id: String, title: String, icon: String)] = [
    ("general", "General", "gearshape"),
    ("downloads", "Downloads", "folder"),
    ("updates", "Updates", "arrow.down.circle"),
    ("uninstall", "Uninstall", "trash"),
]

struct SettingsView: View {
    @AppStorage(UIScale.key) private var uiScale = 1.0
    @AppStorage(Appearance.key) private var themeMode = Appearance.defaultMode   // redraw when the theme changes
    /// Which tab is showing: "general", "downloads", "updates", or "uninstall".
    /// The gear opens General; the Updates link in the footer opens Updates.
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        VStack(spacing: 0) {
            // Glass Crate's own tab bar: the selected tab is filled with the Mac's accent color
            // (System Settings → Appearance → Accent color), so it's blue, red, purple… to match.
            HStack(spacing: 4) {
                ForEach(settingsTabs, id: \.id) { t in
                    let selected = tab == t.id
                    Button { tab = t.id } label: {
                        Label(t.title, systemImage: t.icon)
                            .font(.gcBody)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selected ? Color.gcAccent : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            .padding(.top, 14)

            Group {
                switch tab {
                case "downloads": DownloadSettings()
                case "updates":   UpdatesSettings()          // in Updates.swift
                case "uninstall": UninstallSettings()
                default:          GeneralSettings()
                }
            }
            .padding(UIScale.s(24))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // every tab starts at the top
        }
        .font(.gcBody)
        .controlSize(UIScale.controlSize)
        // (No overall tint: it turned the dropdown menus a bright color. The tabs and checkboxes
        // use the theme color on their own.)
        .frame(width: UIScale.s(600))
        .id("\(themeMode)-\(uiScale)")   // redraw when the theme or Interface Size changes
        .background(WindowAccessor { SettingsWindow.shared.attach($0) })
    }
}

/// Settings → General: theme and Interface Size.
struct GeneralSettings: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.defaultMode
    @AppStorage(UIScale.key) private var uiScale = 1.0

    /// Both rows share one setting; the row that doesn't have the current theme shows nothing selected.
    private func row(_ title: String, _ choices: [(tag: String, title: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.gcCallout.weight(.semibold)).foregroundStyle(.secondary)
            Picker(title, selection: Binding(get: { Appearance.mode }, set: { appearance = $0 })) {
                ForEach(choices, id: \.tag) { Text($0.title).tag($0.tag) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: UIScale.s(440))   // both rows the same length
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIScale.s(12)) {
            Text("Theme").font(.gcHeadline)
            row("Glass Crate", Appearance.glassCrateChoices)
            row("System", Appearance.systemChoices)
            Text("Glass Crate themes use Glass Crate's own colors. System themes use your Mac's look and accent color, and Match System switches when your Mac does.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)

            Text("Interface Size").font(.gcHeadline)
            Picker("Interface Size", selection: $uiScale) {
                ForEach(UIScale.choices, id: \.value) { Text($0.title).tag($0.value) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Text("Makes everything smaller or larger: text, icons, the browser, and the windows. Smaller sizes fit better on laptop screens.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: appearance) { Appearance.apply($0) }
    }
}

/// Settings → Downloads: where files are saved.
struct DownloadSettings: View {
    @AppStorage(SaveFolders.videoKey) private var videoPath = ""
    @AppStorage(SaveFolders.mp3Key) private var mp3Path = ""
    @AppStorage(SaveFolders.losslessKey) private var losslessPath = ""
    @AppStorage(SaveFolders.askKey) private var askEachTime = false
    @AppStorage(SaveFolders.qualityKey) private var quality = "Best available"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Download Locations").font(.gcHeadline)
            Text("Pick where you'd like your files to be downloaded, or keep the default folders.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                FolderRow(icon: "film", title: "Video", key: SaveFolders.videoKey, path: $videoPath)
                FolderRow(icon: "music.note", title: "Audio", key: SaveFolders.mp3Key, path: $mp3Path)
                FolderRow(icon: "waveform", title: "WAV / AIFF", key: SaveFolders.losslessKey, path: $losslessPath,
                          shownURL: SaveFolders.losslessURL(losslessPath: losslessPath, audioPath: mp3Path))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            .disabled(askEachTime)
            .opacity(askEachTime ? 0.5 : 1)

            HStack(spacing: 10) {
                Text("Video quality").font(.gcHeadline)
                Picker("Video quality", selection: $quality) {
                    ForEach(SaveFolders.qualities, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.top, 4)
            Text("Best available is recommended. If a video doesn't have the quality you pick, you get the closest one below it.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Ask where to save each time", isOn: $askEachTime)
                .toggleStyle(.checkbox)
            Text("When this is on, Glass Crate asks for a folder every time you click Download, and the folders above are skipped.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings → Uninstall: what gets removed, what stays, and the Uninstall button.
struct UninstallSettings: View {
    @ObservedObject private var queue = DownloadQueue.shared
    @ObservedObject private var tools = ToolManager.shared
    @ObservedObject private var updater = UpdateManager.shared

    private var busy: Bool { queue.anyRunning || tools.busy || updater.isWorking }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uninstall Glass Crate").font(.gcHeadline)
            Text("Uninstalling removes Glass Crate and everything it added to your Mac, so nothing is left behind.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Removed", systemImage: "trash").font(.gcHeadline)
                    bullet("The Glass Crate app (moved to the Trash)")
                    bullet("The tools it downloaded: yt-dlp, FFmpeg, FFprobe, and Deno (about 200 MB)")
                    bullet("Your settings and your saved Download Queue")
                    bullet("Browse Media's browsing data: history, cookies, and any sign-ins")
                    bullet("Tool updates that were downloaded but not installed")
                    bullet("Unfinished downloads still in the queue, including their partial files")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Kept", systemImage: "checkmark.circle").font(.gcHeadline)
                    bullet("Everything you've downloaded: your videos and music stay right where they are, in their folders")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            HStack {
                Button("Uninstall Glass Crate…") { Uninstaller.run() }
                    .disabled(busy)
                if busy {
                    Text("Wait for downloads and updates to finish, or cancel them, before uninstalling.")
                        .font(.gcCallout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("You'll be asked to confirm first.")
                .font(.gcCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.gcCallout)
    }
}
