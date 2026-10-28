// Glass Crate — SETUP
// Downloads the tools the app needs into its own private folder:
//   ~/Library/Application Support/Glass Crate/bin
// Also holds the one-time setup screen (SetupView, at the bottom).
// Checking for and installing newer versions of the tools is in Updates.swift.
//
//   yt-dlp   downloads video and audio
//   ffmpeg   converts and joins audio/video
//   ffprobe  reads audio/video info for ffmpeg
//   deno     lets yt-dlp read YouTube's pages

import Foundation
import AppKit
import SwiftUI

struct Tool {
    let name: String      // file name in the bin folder
    let label: String     // name shown to the user
    let url: URL          // where the newest version is downloaded from
    let zipped: Bool
}

enum ToolError: LocalizedError {
    case badResponse(String)
    case missingInZip(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let s): return "The download server didn't respond properly (\(s))"
        case .missingInZip(let s): return "\(s) wasn't found inside the download"
        case .commandFailed(let s): return s
        }
    }
}

/// Downloads one file with progress, and can be cancelled. Used by setup and by updates.
final class FileFetch: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var onProgress: ((Double) -> Void)?
    /// Optional: gets "12.4 MB of 31.2 MB · 2.3 MB/s" on the main thread, so people can see it hasn't stalled.
    var onDetail: ((String) -> Void)?
    private var lastSample: (time: Date, bytes: Int64)?
    private var speed: Double = 0   // bytes per second, smoothed
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    /// Downloads `url` to a temporary file and returns where it is. `progress` gets 0...1 on the main thread.
    func fetch(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        onProgress = progress
        lastSample = nil
        speed = 0
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let t = self.session.downloadTask(with: url)
            self.task = t
            t.resume()
        }
    }

    func cancel() { task?.cancel() }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ToolError.badResponse("error \(http.statusCode)")
            }
            // The temporary file disappears when this function returns, so move it somewhere safe first.
            let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: saved)
            continuation?.resume(returning: saved)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let f = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // Speed, measured about twice a second and smoothed so it doesn't jump around
        let now = Date()
        if let last = lastSample {
            let dt = now.timeIntervalSince(last.time)
            guard dt >= 0.5 else { DispatchQueue.main.async { self.onProgress?(f) }; return }
            let current = Double(totalBytesWritten - last.bytes) / dt
            speed = speed == 0 ? current : speed * 0.7 + current * 0.3
        }
        lastSample = (now, totalBytesWritten)
        var detail = "\(DownloadItem.size(Double(totalBytesWritten))) of \(DownloadItem.size(Double(totalBytesExpectedToWrite)))"
        if speed > 0 { detail += " · \(DownloadItem.size(speed))/s" }
        DispatchQueue.main.async {
            self.onProgress?(f)
            self.onDetail?(detail)
        }
    }
}

final class ToolManager: ObservableObject {
    static let shared = ToolManager()

    @Published var ready = false
    @Published var isInstalling = false
    @Published var progress: Double? = nil
    @Published var status = ""          // shown on the setup screen
    @Published var detail = ""          // size and speed of the current download, e.g. "12.4 MB of 31.2 MB · 2.3 MB/s"
    @Published var installError: String? = nil

    /// True during first-time setup, or for the second or two while updated tools are swapped in.
    var busy: Bool { isInstalling || UpdateManager.shared.isSwapping }

    /// Set by the download queue. When the last download finishes, a waiting update can be installed.
    var downloadsRunning = false {
        didSet { if oldValue && !downloadsRunning { UpdateManager.shared.installIfWaiting() } }
    }

    let binDir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Glass Crate/bin", isDirectory: true)
    }()

    // MARK: Where each tool comes from

    #if arch(arm64)
    static let ffArch = "arm64"
    static let denoArch = "aarch64-apple-darwin"
    #else
    static let ffArch = "amd64"
    static let denoArch = "x86_64-apple-darwin"
    #endif

    static let tools: [Tool] = [
        Tool(name: "yt-dlp", label: "yt-dlp",
             url: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!,
             zipped: false),
        Tool(name: "ffmpeg", label: "FFmpeg",
             url: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(ffArch)/release/ffmpeg.zip")!,
             zipped: true),
        Tool(name: "ffprobe", label: "FFprobe",
             url: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(ffArch)/release/ffprobe.zip")!,
             zipped: true),
        Tool(name: "deno", label: "Deno",
             url: URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-\(denoArch).zip")!,
             zipped: true),
    ]

    private init() {
        refresh()
    }

    // MARK: Status

    func path(_ tool: String) -> String { binDir.appendingPathComponent(tool).path }

    var missingTools: [Tool] {
        Self.tools.filter { !FileManager.default.isExecutableFile(atPath: path($0.name)) }
    }

    func refresh() {
        ready = missingTools.isEmpty
    }

    // MARK: First-time install

    private let fetcher = FileFetch()
    private var installCancelled = false

    func install() {
        guard !isInstalling else { return }
        let toInstall = missingTools
        isInstalling = true
        installCancelled = false
        installError = nil
        progress = 0
        detail = ""
        fetcher.onDetail = { [weak self] d in self?.detail = d }
        Task {
            do {
                try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
                for (i, tool) in toInstall.enumerated() {
                    if installCancelled { throw CancellationError() }
                    let start = Double(i) / Double(toInstall.count)
                    let span = 1 / Double(toInstall.count)
                    await MainActor.run {
                        self.status = "Downloading \(tool.label)… (\(i + 1) of \(toInstall.count))"
                    }
                    let file = try await fetcher.fetch(tool.url) { [weak self] f in
                        self?.progress = start + f * span
                    }
                    await MainActor.run { self.status = "Installing \(tool.label)…"; self.detail = "" }
                    try installFile(file, for: tool)
                }
                await MainActor.run {
                    self.isInstalling = false
                    self.progress = nil
                    self.status = ""
                    self.detail = ""
                    UpdateManager.shared.markChecked()   // tools are brand new, so the weekly check can wait
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.progress = nil
                    self.status = ""
                    self.detail = ""
                    self.refresh()
                    // Cancelled on purpose: just go back to the setup screen, no error message.
                    // Tools that finished are kept, so the next attempt picks up where this one stopped.
                    if !self.installCancelled {
                        self.installError = "Setup didn't finish: \(error.localizedDescription). Check your internet connection and try again."
                    }
                }
            }
        }
    }

    /// Called when the app closes. If setup never finished, deletes the app's folder
    /// (and any partly downloaded tools) so it's as if setup never started.
    func cleanUpIfSetupIncomplete() {
        refresh()
        guard !ready else { return }
        cancelInstall()
        try? FileManager.default.removeItem(at: binDir.deletingLastPathComponent())
    }

    /// "Cancel" while setup is running: stops the current download.
    func cancelInstall() {
        installCancelled = true
        fetcher.cancel()
    }

    // MARK: Installing a downloaded file (setup and updates)

    func installFile(_ file: URL, for tool: Tool) throws {
        let fm = FileManager.default
        let dest = binDir.appendingPathComponent(tool.name)
        var source = file
        var unzipDir: URL? = nil

        if tool.zipped {
            let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            unzipDir = dir
            let r = try Self.run("/usr/bin/ditto", ["-x", "-k", file.path, dir.path])
            guard r.status == 0 else { throw ToolError.commandFailed("Couldn't unzip \(tool.label)") }
            guard let found = findFile(named: tool.name, in: dir) else { throw ToolError.missingInZip(tool.label) }
            source = found
        }

        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: source, to: dest)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        _ = try? Self.run("/usr/bin/xattr", ["-c", dest.path])   // clear any download flags

        try? fm.removeItem(at: file)
        if let unzipDir { try? fm.removeItem(at: unzipDir) }
    }

    private func findFile(named name: String, in dir: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in e where url.lastPathComponent == name {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                return url
            }
        }
        return nil
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - The one-time setup screen

/// One row on the setup screen: what a tool does, with links to its official pages.
private struct ToolRow: View {
    let icon: String
    let name: String
    let what: String
    let links: [(title: String, url: String)]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.gcHeadline)
                Text(what)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(links.indices, id: \.self) { i in
                        if i > 0 { Text("·").foregroundStyle(.secondary) }
                        Link(links[i].title, destination: URL(string: links[i].url)!)
                    }
                }
                .font(.gcCaption)
            }
        }
    }
}

struct SetupView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var tools = ToolManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)   // the app's own icon (from icon.png)
                .resizable()
                .frame(width: 72, height: 72)
            Text("One-time setup").font(.gcTitle)
            // Two separate lines so each one centers on its own
            VStack(spacing: 2) {
                Text("Glass Crate relies on a few free, open-source tools to do its work.")
                Text("Here's what each one does, with links to learn more.")
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                ToolRow(icon: "arrow.down.circle",
                        name: "yt-dlp",
                        what: "Downloads the video and audio from YouTube.",
                        links: [("Official project on GitHub", "https://github.com/yt-dlp/yt-dlp")])
                ToolRow(icon: "waveform",
                        name: "FFmpeg + FFprobe (2 files)",
                        what: "FFmpeg joins video and audio, converts to MP3, WAV, or AIFF, and adds album art. FFprobe, its companion, checks each file before it's converted.",
                        links: [("ffmpeg.org", "https://ffmpeg.org"),
                                ("Mac version built by Martin Riedl", "https://ffmpeg.martin-riedl.de")])
                ToolRow(icon: "curlybraces",
                        name: "Deno",
                        what: "Helps yt-dlp read YouTube's pages so downloads keep working.",
                        links: [("deno.com", "https://deno.com")])
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            Text("This one-time setup downloads the latest version of these 4 files, about 200 MB in total, into the app's own folder. Nothing else is installed, no password is needed, and everything is removed if you uninstall the app.")
                .font(.gcCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)   // narrower than the grey box above it

            if tools.isInstalling {
                VStack(spacing: 6) {
                    ProgressView(value: tools.progress ?? 0)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tools.status)
                                .font(.gcCallout)
                                .foregroundStyle(.secondary)
                            // "12.4 MB of 31.2 MB · 2.3 MB/s": if the numbers keep moving, it hasn't stalled
                            if !tools.detail.isEmpty {
                                Text(tools.detail)
                                    .font(.gcCallout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Cancel") { tools.cancelInstall() }
                    }
                }
            } else {
                if let err = tools.installError {
                    Text(err)
                        .font(.gcCallout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button("Quit") { Uninstaller.quitSetup() }
                    Button(tools.installError == nil ? "Begin Setup" : "Try Again") { tools.install() }
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }

            Divider()

            HStack(spacing: 6) {
                Button("Open source on GitHub") { NSWorkspace.shared.open(Links.github) }
                    .buttonStyle(.link)
                Text("·")
                Button("About Glass Crate") { openWindow(id: "about") }
                    .buttonStyle(.link)
            }
            .font(.gcCaption)
            .foregroundStyle(.secondary)
        }
    }
}
