// Glass Crate — UPDATES
// Mac-style updates for the tools, shown in Settings → Updates. Never pushy, never in the way:
//   • Checking only asks each tool's source for its newest version (a few tiny requests).
//   • Each tool updates on its own: Download (with progress and Cancel), then Install when you're ready.
//     FFmpeg and FFprobe are one item, since they have to match.
//   • Skip hides a version until an even newer one comes out.
//   • Options: check weekly (on), download automatically (off), install automatically (off).
//   • Installing waits until no downloads are running, so a tool never changes mid-download.
//   • Downloaded updates are kept in "Glass Crate/pending" until installed, even if the app is quit.
// The main window shows a small red ! next to the "Updates" link when something needs a look.

import Foundation
import SwiftUI

/// A tool, or tools that update together.
struct UpdateGroup: Identifiable {
    let id: String          // "yt-dlp", "ffmpeg", "deno"
    let label: String       // shown in Settings
    let toolNames: [String]
    var tools: [Tool] { toolNames.compactMap { n in ToolManager.tools.first { $0.name == n } } }

    static let all: [UpdateGroup] = [
        UpdateGroup(id: "yt-dlp", label: "yt-dlp", toolNames: ["yt-dlp"]),
        UpdateGroup(id: "ffmpeg", label: "FFmpeg + FFprobe", toolNames: ["ffmpeg", "ffprobe"]),
        UpdateGroup(id: "deno", label: "Deno", toolNames: ["deno"]),
    ]
}

enum UpdateStatus: Equatable {
    case notChecked
    case checking
    case upToDate
    case available
    case skipped
    case downloading
    case downloaded          // ready to install
    case waitingToInstall    // will install when the download queue is empty
    case installing
    case failed(String)
}

struct UpdateState {
    var status: UpdateStatus = .notChecked
    var installed = ""                       // installed version, e.g. "9.0.2"
    var latest = ""                          // newest version, e.g. "9.0.3"
    var links: [(tool: Tool, url: URL)] = [] // where to download the newest version
    var size: Int64? = nil                   // total download size in bytes, if known
    var progress: Double = 0
    var note = ""                            // e.g. "Updated to 9.0.3."
}

final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var states: [String: UpdateState] = [:]
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date? = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date

    // MARK: Options (Settings → Updates)

    static let autoCheckKey = "updatesAutoCheck"        // default on
    static let autoDownloadKey = "updatesAutoDownload"  // default off
    static let autoInstallKey = "updatesAutoInstall"    // default off
    private func option(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
    private var autoCheck: Bool { option(Self.autoCheckKey, default: true) }
    private var autoDownload: Bool { option(Self.autoDownloadKey, default: false) }
    private var autoInstall: Bool { autoDownload && option(Self.autoInstallKey, default: false) }

    // MARK: Summary for the rest of the app

    /// Something to look at: an update available (not skipped), or downloaded and ready.
    var needsAttention: Bool {
        states.values.contains { [.available, .downloaded, .waitingToInstall].contains($0.status) }
    }
    /// New tool files are being swapped in; new downloads wait for this (a second or two).
    var isSwapping: Bool { states.values.contains { $0.status == .installing } }
    /// Anything in progress (Uninstall waits for this).
    var isWorking: Bool {
        isChecking || states.values.contains { [.downloading, .waitingToInstall, .installing].contains($0.status) }
    }

    func state(_ id: String) -> UpdateState { states[id] ?? UpdateState() }

    private var fetchers: [String: FileFetch] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {
        restorePending()
    }

    // MARK: Checking

    static let autoCheckInterval: TimeInterval = 7 * 24 * 60 * 60   // one week

    func markChecked() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
        DispatchQueue.main.async { self.lastChecked = now }
    }

    /// When the app opens: checks if it's been a week (and weekly checks are on). Quiet unless something's found.
    func checkIfDue() {
        guard autoCheck else { return }
        let last = lastChecked ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.autoCheckInterval { check() }
    }

    /// "Check Now": asks each tool's source for its newest version. Downloads nothing (unless
    /// "Download updates automatically" is on).
    func check() {
        guard ToolManager.shared.ready, !isChecking else { return }
        isChecking = true
        Task {
            var anyProblem = false
            for group in UpdateGroup.all {
                if await !self.checkGroup(group) { anyProblem = true }
            }
            if !anyProblem { self.markChecked() }
            await MainActor.run { self.isChecking = false }
        }
    }

    /// "Retry" on one tool whose check failed: checks just that one.
    func checkOne(_ id: String) {
        guard ToolManager.shared.ready, let group = UpdateGroup.all.first(where: { $0.id == id }) else { return }
        Task { _ = await self.checkGroup(group) }
    }

    /// Checks one tool. Returns false if the check couldn't reach its source.
    private func checkGroup(_ group: UpdateGroup) async -> Bool {
        // Leave alone anything that's mid-download or downloaded and waiting
        let current = await MainActor.run { self.state(group.id).status }
        if [.downloading, .downloaded, .waitingToInstall, .installing, .checking].contains(current) { return true }
        await MainActor.run { self.states[group.id, default: UpdateState()].status = .checking }
        do {
            let result = try await self.compare(group)
            await MainActor.run { self.apply(result, to: group) }
            return true
        } catch {
            await MainActor.run {
                self.states[group.id, default: UpdateState()].status =
                    .failed("Couldn't check. Check your internet connection, then click Retry.")
            }
            return false
        }
    }

    private struct CheckResult {
        let installed: String
        let installedLine: String
        let latest: String
        let links: [(tool: Tool, url: URL)]
        let size: Int64?
    }

    private func compare(_ group: UpdateGroup) async throws -> CheckResult {
        var links: [(tool: Tool, url: URL)] = []
        var total: Int64 = 0
        var sizeKnown = true
        var latest = ""
        for tool in group.tools {
            let info: (version: String, url: URL, size: Int64?)
            switch tool.name {
            case "yt-dlp": info = try await gitHubLatest(repo: "yt-dlp/yt-dlp", asset: "yt-dlp_macos")
            case "deno":   info = try await gitHubLatest(repo: "denoland/deno", asset: "deno-\(ToolManager.denoArch).zip")
            default:       info = try await martinRiedlLatest(tool.url)
            }
            if latest.isEmpty { latest = info.version }
            links.append((tool, info.url))
            if let s = info.size { total += s } else { sizeKnown = false }
        }
        let line = Self.versionLine(of: group.tools[0])
        return CheckResult(installed: Self.versionNumber(from: line), installedLine: line, latest: latest,
                           links: links, size: sizeKnown ? total : nil)
    }

    private func apply(_ r: CheckResult, to group: UpdateGroup) {
        var s = state(group.id)
        s.installed = r.installed
        s.latest = r.latest
        s.links = r.links
        s.size = r.size
        s.note = ""
        if Self.matches(r.installedLine, r.latest) {
            s.status = .upToDate
            clearPending(group)
        } else if pendingVersion(group) == r.latest {
            s.status = .downloaded
        } else if UserDefaults.standard.string(forKey: "updatesSkip.\(group.id)") == r.latest {
            s.status = .skipped
        } else {
            s.status = .available
        }
        states[group.id] = s
        if s.status == .available && autoDownload { download(group.id) }
        else if s.status == .downloaded && autoInstall { install(group.id) }
    }

    /// yt-dlp and Deno: GitHub says the newest release's version, file, and size.
    private func gitHubLatest(repo: String, asset: String) async throws -> (version: String, url: URL, size: Int64?) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.timeoutInterval = 20
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let file = assets.first(where: { $0["name"] as? String == asset }),
              let link = file["browser_download_url"] as? String,
              let url = URL(string: link) else {
            throw ToolError.badResponse("GitHub")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return (version, url, (file["size"] as? NSNumber)?.int64Value)
    }

    /// FFmpeg and FFprobe: the "latest" link forwards to a folder named like "1789931890_9.0.2".
    /// First asks for just the headers (no download). If the site won't answer that kind of request,
    /// asks for the first single byte instead. Either way it learns where the link forwards, and the size.
    private func martinRiedlLatest(_ latestLink: URL) async throws -> (version: String, url: URL, size: Int64?) {
        var head = URLRequest(url: latestLink)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 20
        if let (_, response) = try? await URLSession.shared.data(for: head),
           let http = response as? HTTPURLResponse, http.statusCode == 200, let final = http.url,
           let version = Self.riedlVersion(from: final) {
            return (version, final, http.expectedContentLength > 0 ? http.expectedContentLength : nil)
        }

        var oneByte = URLRequest(url: latestLink)
        oneByte.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        oneByte.timeoutInterval = 20
        let (_, response) = try await URLSession.shared.data(for: oneByte)
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode),
              let final = http.url, let version = Self.riedlVersion(from: final) else {
            throw ToolError.badResponse("ffmpeg.martin-riedl.de")
        }
        // "Content-Range: bytes 0-0/45678901" → the full size is after the slash
        var size: Int64? = nil
        if let range = http.value(forHTTPHeaderField: "Content-Range"), let total = range.split(separator: "/").last {
            size = Int64(total)
        }
        return (version, final, size)
    }

    /// "…/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip" → "9.0.2"
    static func riedlVersion(from url: URL) -> String? {
        let folder = url.deletingLastPathComponent().lastPathComponent
        guard let underscore = folder.firstIndex(of: "_") else { return nil }
        let version = String(folder[folder.index(after: underscore)...])
        return version.isEmpty ? nil : version
    }

    /// The first line the installed tool prints about its version, e.g. "ffmpeg version 9.0.2 Copyright…".
    static func versionLine(of tool: Tool) -> String {
        let flag = tool.name == "ffmpeg" || tool.name == "ffprobe" ? "-version" : "--version"
        let out = (try? ToolManager.run(ToolManager.shared.path(tool.name), [flag]))?.output ?? ""
        return out.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Just the number from a version line: "deno 2.5.1 (…)" → "2.5.1", "ffmpeg version 9.0.2 …" → "9.0.2".
    static func versionNumber(from line: String) -> String {
        let words = line.split(separator: " ").map(String.init)
        if let i = words.firstIndex(of: "version"), i + 1 < words.count { return words[i + 1] }
        if words.first == "deno", words.count > 1 { return words[1] }
        return words.first ?? ""
    }

    /// True if the version line includes the newest version as one of its words.
    static func matches(_ line: String, _ version: String) -> Bool {
        line.split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ")" })
            .contains { $0 == version || $0.hasPrefix(version + "-") }
    }

    // MARK: Download → Install

    private var pendingDir: URL {
        ToolManager.shared.binDir.deletingLastPathComponent().appendingPathComponent("pending", isDirectory: true)
    }
    private func pendingFile(_ tool: Tool) -> URL { pendingDir.appendingPathComponent(tool.name) }
    private func pendingVersion(_ group: UpdateGroup) -> String? {
        guard let v = UserDefaults.standard.string(forKey: "updatesPending.\(group.id)"),
              group.tools.allSatisfy({ FileManager.default.fileExists(atPath: pendingFile($0).path) }) else { return nil }
        return v
    }
    private func clearPending(_ group: UpdateGroup) {
        for t in group.tools { try? FileManager.default.removeItem(at: pendingFile(t)) }
        UserDefaults.standard.removeObject(forKey: "updatesPending.\(group.id)")
    }

    /// Downloaded-but-not-installed updates survive quitting the app.
    private func restorePending() {
        for group in UpdateGroup.all {
            if let v = pendingVersion(group) {
                var s = UpdateState()
                s.status = .downloaded
                s.latest = v
                states[group.id] = s
            }
        }
    }

    /// "Download": gets the newest version of this tool and keeps it ready to install.
    func download(_ id: String) {
        guard let group = UpdateGroup.all.first(where: { $0.id == id }),
              state(id).status == .available || state(id).status == .skipped else { return }
        let links = state(id).links
        guard !links.isEmpty else { return }
        let fetcher = FileFetch()
        fetchers[id] = fetcher
        states[id]?.status = .downloading
        states[id]?.progress = 0
        tasks[id] = Task {
            do {
                try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
                for (i, link) in links.enumerated() {
                    let start = Double(i) / Double(links.count)
                    let span = 1 / Double(links.count)
                    let file = try await fetcher.fetch(link.url) { [weak self] f in
                        self?.states[id]?.progress = start + f * span
                    }
                    let dest = pendingFile(link.tool)
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: file, to: dest)
                }
                let latest = await MainActor.run { self.state(id).latest }
                UserDefaults.standard.set(latest, forKey: "updatesPending.\(id)")
                await MainActor.run {
                    guard self.state(id).status == .downloading else { return }
                    self.states[id]?.status = .downloaded
                    if self.autoInstall { self.install(id) }
                }
            } catch {
                await MainActor.run {
                    self.clearPending(group)
                    if self.state(id).status == .downloading {   // not cancelled on purpose
                        self.states[id]?.status = .failed("The download didn't finish. Your current version is unchanged.")
                    }
                }
            }
        }
    }

    /// "Install": swaps in the downloaded version. Waits if downloads are running.
    func install(_ id: String) {
        guard [.downloaded, .waitingToInstall].contains(state(id).status) else { return }
        if ToolManager.shared.downloadsRunning {
            states[id]?.status = .waitingToInstall
            return
        }
        guard let group = UpdateGroup.all.first(where: { $0.id == id }) else { return }
        states[id]?.status = .installing
        let latest = state(id).latest
        Task.detached {
            var problem = false
            for tool in group.tools {
                do {
                    try ToolManager.shared.installFile(self.pendingFile(tool), for: tool)
                } catch {
                    problem = true
                }
            }
            await MainActor.run {
                self.clearPending(group)
                ToolManager.shared.refresh()
                if problem {
                    self.states[id]?.status = .failed("Couldn't install the update. Check Now to try again.")
                } else {
                    self.states[id]?.status = .upToDate
                    self.states[id]?.installed = latest
                    self.states[id]?.note = "Updated to \(latest)."
                }
                // Let any downloads that were waiting on the swap start now
                NotificationCenter.default.post(name: .glassCrateToolsChanged, object: nil)
            }
        }
    }

    /// Called when the last download in the queue finishes.
    func installIfWaiting() {
        for (id, s) in states where s.status == .waitingToInstall {
            states[id]?.status = .downloaded
            install(id)
        }
    }

    /// "Cancel" while downloading: stops and keeps the current version.
    /// "Don't Install Yet" while waiting: keeps the download ready for later.
    func cancel(_ id: String) {
        switch state(id).status {
        case .downloading:
            states[id]?.status = .available   // set first, so the download's error isn't shown as a failure
            fetchers[id]?.cancel()
            tasks[id]?.cancel()
        case .waitingToInstall:
            states[id]?.status = .downloaded
        default:
            break
        }
    }

    /// "Skip": hides this version until a newer one comes out.
    func skip(_ id: String) {
        UserDefaults.standard.set(state(id).latest, forKey: "updatesSkip.\(id)")
        if state(id).status == .available { states[id]?.status = .skipped }
    }

    func unskip(_ id: String) {
        UserDefaults.standard.removeObject(forKey: "updatesSkip.\(id)")
        if state(id).status == .skipped { states[id]?.status = .available }
    }

    /// Total size like "45 MB".
    static func sizeText(_ bytes: Int64?) -> String? {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }
}

extension Notification.Name {
    static let glassCrateToolsChanged = Notification.Name("glassCrateToolsChanged")
}

// MARK: - Settings → Updates tab

struct UpdatesSettings: View {
    @ObservedObject private var updater = UpdateManager.shared
    @AppStorage(UpdateManager.autoCheckKey) private var autoCheck = true
    @AppStorage(UpdateManager.autoDownloadKey) private var autoDownload = false
    @AppStorage(UpdateManager.autoInstallKey) private var autoInstall = false

    private var lastCheckedText: String {
        guard let d = updater.lastChecked else { return "Never checked" }
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Last checked: " + f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tool Updates").font(.gcHeadline)
                Spacer()
                if updater.isChecking { ProgressView().controlSize(.small) }
                Text(lastCheckedText)
                    .font(.gcCallout)
                    .foregroundStyle(.secondary)
                Button("Check Now") { updater.check() }
                    .disabled(updater.isChecking)
            }
            Text("Glass Crate uses yt-dlp, FFmpeg, and Deno to do its work. YouTube changes often, so these get updates now and then. Nothing downloads or installs unless you choose, and you can keep using the app the whole time.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Check for updates once a week", isOn: $autoCheck)
                Toggle("Download updates automatically", isOn: $autoDownload)
                Text("Downloaded updates wait until you choose to install them.")
                    .font(.gcCaption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                Toggle("Install updates automatically", isOn: $autoInstall)
                    .disabled(!autoDownload)
                    .padding(.leading, 20)
            }
            .toggleStyle(.checkbox)

            VStack(spacing: 0) {
                ForEach(UpdateGroup.all) { group in
                    UpdateRow(group: group)
                    if group.id != UpdateGroup.all.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            Text("Updates install between downloads, never in the middle of one.")
                .font(.gcCaption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One tool in Settings → Updates: versions, status, and its own buttons.
private struct UpdateRow: View {
    let group: UpdateGroup
    @ObservedObject private var updater = UpdateManager.shared

    var body: some View {
        let s = updater.state(group.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.label).font(.gcHeadline)
                    Text(versionText(s))
                        .font(.gcCallout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                buttons(s)
            }
            if s.status == .downloading {
                ProgressView(value: s.progress)
            }
        }
        .padding(.vertical, 12)
    }

    private func versionText(_ s: UpdateState) -> String {
        let size = UpdateManager.sizeText(s.size).map { " (\($0))" } ?? ""
        switch s.status {
        case .notChecked: return s.installed.isEmpty ? "Not checked yet" : s.installed
        case .checking: return "Checking…"
        case .upToDate: return s.note.isEmpty ? "\(s.installed) · Up to date" : s.note
        case .available, .downloading: return "\(s.installed) → \(s.latest)\(size)"
        case .skipped: return "\(s.installed) · Skipped \(s.latest)"
        case .downloaded: return "\(s.latest) downloaded, ready to install"
        case .waitingToInstall: return "\(s.latest) will install when your downloads finish"
        case .installing: return "Installing \(s.latest)…"
        case .failed(let msg): return msg
        }
    }

    @ViewBuilder private func buttons(_ s: UpdateState) -> some View {
        HStack(spacing: 6) {
            switch s.status {
            case .available:
                Button("Skip") { updater.skip(group.id) }
                Button("Download") { updater.download(group.id) }
            case .skipped:
                Button("Undo Skip") { updater.unskip(group.id) }
            case .downloading:
                Button("Cancel") { updater.cancel(group.id) }
            case .downloaded:
                Button("Install") { updater.install(group.id) }
            case .waitingToInstall:
                Button("Don't Install Yet") { updater.cancel(group.id) }
            case .checking, .installing:
                ProgressView().controlSize(.small)
            case .upToDate:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Retry") { updater.checkOne(group.id) }
            case .notChecked:
                EmptyView()
            }
        }
        .controlSize(.small)
    }
}
