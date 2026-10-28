// Glass Crate — DOWNLOADER
// One item in the download queue: a link plus the formats and folders chosen when it was added.
// First asks YouTube about the video once and saves the answer ("info"), then runs yt-dlp for each
// checked format (one after another) using that saved answer, so YouTube is only asked once per video.
// Reports progress. If YouTube says to slow down, the item goes back in line and the queue waits.
// If a file already exists, asks whether to replace it or skip it.
// The queue that decides when items start is in Queue.swift.

import Foundation
import AppKit

final class LineSplitter {
    private var buffer = Data()
    private let onLine: (String) -> Void
    init(_ onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        buffer.append(data)
        while let r = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<r]
            if let line = String(data: lineData, encoding: .utf8) { onLine(line) }
            buffer = Data(buffer[buffer.index(after: r)...])
        }
    }
}

/// Everything chosen when the item was added to the queue.
struct DownloadRequest: Codable {
    let link: String
    let video: Bool
    let mp3: Bool
    let wav: Bool
    let aiff: Bool
    let quality: String
    let videoFolder: URL
    let mp3Folder: URL
    let losslessFolder: URL
    let binDir: String

    /// Short summary shown in the queue, e.g. "MP4 1080p · MP3 · WAV"
    var summary: String {
        var parts: [String] = []
        if video { parts.append(quality == "Best available" ? "MP4 (best)" : "MP4 \(quality)") }
        if mp3 { parts.append("MP3") }
        if wav { parts.append("WAV") }
        if aiff { parts.append("AIFF") }
        return parts.joined(separator: " · ")
    }
}

final class DownloadItem: ObservableObject, Identifiable {
    let id = UUID()
    let request: DownloadRequest

    @Published var isWaiting = true         // in the queue, not started yet
    @Published var isPaused = false         // restored after quitting; waits for Resume
    @Published var isRunning = false
    @Published var progress: Double? = nil
    @Published var status = "Waiting…"
    @Published var succeeded = false
    @Published var failed = false           // ended in an error (shows "Try Again")
    @Published var wasCancelled = false
    @Published var title: String? = nil     // the video's title, once yt-dlp reports it
    @Published var thumbnail: URL? = nil    // the video's thumbnail picture, shown in the Downloads panel
    // Where this download saved files, with a name for each ("Video", "Audio", "WAV/AIFF").
    // Used for the Open … Folder / Show in Finder buttons.
    @Published var usedFolders: [UsedFolder] = []

    /// Formats that already finished ("Video", "MP3", "WAV", "AIFF"), so Resume and Try Again skip them.
    var doneJobs: Set<String> = []

    /// Files yt-dlp started writing for the format that hasn't finished yet (from its "Destination:" lines).
    /// Used to delete Glass Crate's own leftover partial files when a download is removed, cleared,
    /// dropped at quit, or uninstalled. Cleared each time a format finishes, so finished files are never touched.
    var partialFiles: [String] = []

    /// Called whenever this item starts waiting again or finishes, so the queue can start the next one.
    var onChange: (() -> Void)?

    struct UsedFolder: Identifiable {
        let name: String
        let url: URL
        var id: String { url.path }
    }

    var isFinished: Bool { succeeded || failed || wasCancelled }

    /// The site this link is from, so the queue can limit how many run at once per site.
    var site: String {
        let host = URL(string: request.link)?.host?.lowercased() ?? "other"
        if host.contains("youtu") { return "youtube" }   // youtube.com, youtu.be, music.youtube.com
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// The site's name for the thumbnail placeholder, e.g. "YouTube" or "soundcloud.com".
    var siteName: String {
        switch site {
        case "youtube": return "YouTube"
        case "soundcloud.com", "m.soundcloud.com": return "SoundCloud"
        default: return site
        }
    }

    init(_ request: DownloadRequest) {
        self.request = request
        // YouTube thumbnails and titles can be found from the link right away, before the download starts
        if let id = Self.youTubeID(from: request.link) {
            thumbnail = URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
            fetchYouTubeTitle(videoID: id)
        } else if let host = URL(string: request.link)?.host?.lowercased(), host.hasSuffix("soundcloud.com") {
            // SoundCloud: the track's title and artwork, the same way
            fetchSoundCloudInfo()
        }
    }

    /// Asks SoundCloud's public "oEmbed" service (the same thing websites use to show a track preview)
    /// for the track's title and artwork, so they show up right away, before the download starts.
    private func fetchSoundCloudInfo() {
        var parts = URLComponents(string: "https://soundcloud.com/oembed")!
        parts.queryItems = [URLQueryItem(name: "url", value: request.link),
                            URLQueryItem(name: "format", value: "json")]
        guard let url = parts.url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            // SoundCloud's title reads "Track Name by Artist"; keep just the track name
            var title = json["title"] as? String
            if let t = title, let artist = json["author_name"] as? String, t.hasSuffix(" by \(artist)") {
                title = String(t.dropLast(" by \(artist)".count))
            }
            let art = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                guard let self else { return }
                if self.title == nil, let title { self.title = title }
                if self.thumbnail == nil, let art { self.thumbnail = art }
            }
        }.resume()
    }

    /// Asks YouTube's public "oEmbed" service for the video's title (the same thing websites use to
    /// show a video preview). It's quick and separate from the download, so the title shows up
    /// even while the item is waiting, or if the download itself fails.
    private func fetchYouTubeTitle(videoID: String) {
        var parts = URLComponents(string: "https://www.youtube.com/oembed")!
        parts.queryItems = [URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
                            URLQueryItem(name: "format", value: "json")]
        guard let url = parts.url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = json["title"] as? String else { return }
            DispatchQueue.main.async {
                if self?.title == nil { self?.title = title }
            }
        }.resume()
    }

    /// Trims a YouTube link down to just the video: "watch?v=Jg-lmuxQlyo&list=…&start_radio=1&si=…"
    /// becomes "https://www.youtube.com/watch?v=Jg-lmuxQlyo". Links from other sites are left as they are.
    static func cleanLink(_ link: String) -> String {
        guard let id = youTubeID(from: link) else { return link }
        return "https://www.youtube.com/watch?v=\(id)"
    }

    /// Sites that only have audio, so MP4 is left out of their downloads automatically.
    /// Add a site here as more audio-only sites are supported.
    static let audioOnlySites = ["soundcloud.com"]

    static func isAudioOnly(_ link: String) -> Bool {
        guard let host = URL(string: link)?.host?.lowercased() else { return false }
        return audioOnlySites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The 11-character video ID from a YouTube link (watch?v=…, youtu.be/…, shorts/…).
    static func youTubeID(from link: String) -> String? {
        guard let url = URL(string: link), let host = url.host?.lowercased(), host.contains("youtu") else { return nil }
        if host.contains("youtu.be") {
            return url.pathComponents.dropFirst().first
        }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { $0 == "shorts" || $0 == "live" || $0 == "embed" }), i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }

    private struct Job {
        let label: String
        let args: [String]
        let folder: URL                      // where this file is saved
        var folderName = ""                  // "Video", "Audio", or "WAV/AIFF" (for the Open … Folder buttons)
        var overwrite = false
        var fileName = "%(title)s.%(ext)s"   // yt-dlp output name
        var convertToAIFF = false
        var isInfo = false                   // the first step: ask YouTube about the video once
    }

    /// AIFF: yt-dlp can't make AIFF directly, so it saves a temporary WAV
    /// ("Title.glasscrate-tmp.wav"), then ffmpeg converts it to "Title.aiff" and the WAV is deleted.
    private static let aiffTempSuffix = ".glasscrate-tmp"

    private func aiffArgs(overwrite: Bool) -> [String] {
        let cut = -(Self.aiffTempSuffix.count + 4)          // strip ".glasscrate-tmp.wav"
        let out = "%(filepath.:\(cut))q.aiff"
        let wav = "%(filepath)q"
        let convert = "ffmpeg -y -loglevel error -i \(wav) -c:a pcm_s16be -write_id3v2 1 \(out)"
        let cmd = overwrite
            ? "\(convert) && rm -f \(wav)"
            : "if [ -e \(out) ]; then echo \"[download] \"\(out)\" has already been downloaded\"; rm -f \(wav); else \(convert) && rm -f \(wav); fi"
        return ["--exec", "after_move:" + cmd]
    }
    private var jobs: [Job] = []
    private var totalJobs = 0
    private var existingFile: String? = nil   // set when yt-dlp reports the file is already there
    private var process: Process?
    private var cancelled = false
    private var lastError = ""
    private var infoFile: URL?          // YouTube's answer about the video, reused by every format
    /// How many times in a row YouTube has asked to slow down for this download.
    var slowDownCount = 0
    /// Called when YouTube asks to slow down, so the queue can wait before trying again.
    var onSlowDown: (() -> Void)?

    /// Called by the queue when it's this item's turn.
    /// Any combination of formats can be checked; each one is saved as its own file.
    func begin() {
        let r = request
        isWaiting = false
        cancelled = false
        succeeded = false
        failed = false
        wasCancelled = false
        lastError = ""
        isRunning = true
        progress = nil
        status = "Starting…"

        jobs = []
        if r.video {
            let h = r.quality == "Best available" ? "" : "[height<=\(r.quality.dropLast())]"
            jobs.append(Job(label: "Video", args: [
                "-f", "bv*\(h)[ext=mp4]+ba[ext=m4a]/b\(h)[ext=mp4]/bv*\(h)+ba/b\(h)",
                "--merge-output-format", "mp4",
            ] + Tagging.videoArt, folder: r.videoFolder, folderName: "Video"))
        }
        if r.mp3 {
            jobs.append(Job(label: "MP3", args: [
                "-x", "--audio-format", "mp3", "--audio-quality", "0",
            ] + Tagging.squareAlbumArt, folder: r.mp3Folder, folderName: "Audio"))
        }
        // WAV/AIFF counts as the Audio folder unless it has its own
        let losslessName = r.losslessFolder.standardizedFileURL.path == r.mp3Folder.standardizedFileURL.path ? "Audio" : "WAV/AIFF"
        if r.wav {
            jobs.append(Job(label: "WAV", args: [
                "-x", "--audio-format", "wav",
            ] + Tagging.wavArt, folder: r.losslessFolder, folderName: losslessName))
        }
        if r.aiff {
            jobs.append(Job(label: "AIFF", args: [
                "-x", "--audio-format", "wav",
            ] + Tagging.aiffArt,
                folder: r.losslessFolder,
                folderName: losslessName,
                fileName: "%(title)s\(Self.aiffTempSuffix).%(ext)s",
                convertToAIFF: true))
        }
        // Remember which folders this download uses, without repeats
        // If video and audio share one folder (for example "Ask where to save each time"),
        // the button uses that folder's own name instead, like "Open Desktop Folder".
        usedFolders = []
        for job in jobs {
            let path = job.folder.standardizedFileURL.path
            if let i = usedFolders.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                if usedFolders[i].name != job.folderName {
                    usedFolders[i] = UsedFolder(name: job.folder.lastPathComponent, url: job.folder)
                }
            } else {
                usedFolders.append(UsedFolder(name: job.folderName, url: job.folder))
            }
        }
        // Skip formats that already finished (after Resume or Try Again)
        jobs.removeAll { doneJobs.contains($0.label) }
        totalJobs = jobs.count
        // Ask YouTube about the video once, first; every format then reuses the answer
        if !jobs.isEmpty {
            jobs.insert(Job(label: "Info", args: [], folder: r.videoFolder, isInfo: true), at: 0)
        }
        runNext()
    }

    /// "Resume": a download restored after quitting goes back in line.
    /// A partly downloaded file continues where it stopped, and finished formats are skipped.
    func resume() {
        guard isPaused else { return }
        slowDownCount = 0
        isPaused = false
        isWaiting = true
        status = "Waiting…"
        onChange?()
    }

    /// "Try Again": puts the item back in line with the same link, formats, quality, and folders.
    /// Formats that already finished are skipped.
    func retry() {
        guard !isRunning else { return }
        slowDownCount = 0
        isPaused = false
        succeeded = false
        failed = false
        wasCancelled = false
        isWaiting = true
        progress = nil
        status = "Waiting…"
        onChange?()
    }

    func cancel() {
        if isWaiting || isPaused {
            // Not started yet: just take it out of line
            isWaiting = false
            isPaused = false
            wasCancelled = true
            status = "Cancelled."
            onChange?()
            return
        }
        cancelled = true
        jobs.removeAll()
        process?.terminate()
    }

    private func runNext() {
        guard !jobs.isEmpty else {
            removeInfoFile()
            slowDownCount = 0
            isRunning = false
            process = nil
            succeeded = true
            progress = 1
            status = "Done!"
            onChange?()
            return
        }
        let job = jobs.removeFirst()
        // Shown in the status line, e.g. "MP3 (file 2 of 3): downloading 40% · 12.1 MB of 30.2 MB · 2.3 MB/s"
        let label = job.isInfo ? "Info"
            : (totalJobs > 1 ? "\(job.label) (file \(totalJobs - jobs.count) of \(totalJobs))" : job.label)
        status = job.isInfo ? "Getting video info…" : "\(label): starting…"
        progress = nil
        existingFile = nil

        let binDir = request.binDir
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binDir + "/yt-dlp")
        let infoBase = FileManager.default.temporaryDirectory.appendingPathComponent("glasscrate-\(id.uuidString)")
        if job.isInfo {
            // Step 1: ask YouTube about the video once and save the answer (downloads nothing)
            p.arguments = [
                "--no-playlist", "--force-ipv4",
                "--js-runtimes", "deno:" + binDir + "/deno",
                "--skip-download", "--write-info-json",
                "-o", infoBase.path + ".%(ext)s",
                request.link,
            ]
        } else {
        p.arguments = [
            "--no-playlist", "--newline", "--progress",
            // IPv4 only: YouTube's "confirm you're not a bot" check flags some IPv6 connections
            "--force-ipv4",
            "--ffmpeg-location", binDir,
            "--js-runtimes", "deno:" + binDir + "/deno",
            "--progress-template",
            // The thumbnail link, then the title last because it can contain spaces
            // vcodec/acodec tell whether this part is the picture, the sound, or both
            "download:PROG %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s %(info.vcodec)s %(info.acodec)s %(info.thumbnail)s %(info.title)s",
            "-o", job.folder.path + "/" + job.fileName,
        ] + Tagging.common + job.args
          + (job.convertToAIFF ? aiffArgs(overwrite: job.overwrite) : [])
          + (job.overwrite ? ["--force-overwrites"] : [])
          // Reuse the saved answer instead of asking YouTube again
          + (infoFile.map { ["--load-info-json", $0.path] } ?? [request.link])
        }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = binDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let splitter = LineSplitter { [weak self] line in
            DispatchQueue.main.async { self?.handle(line, label: label) }
        }
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil } else { splitter.feed(data) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                if proc.terminationStatus == 0 && !self.cancelled && job.isInfo {
                    self.useInfoFile(infoBase.appendingPathExtension("info.json"))
                    self.runNext()
                } else if proc.terminationStatus == 0 && !self.cancelled {
                    if let name = self.existingFile, !job.overwrite {
                        self.askToReplace(name, job: job)  // job.folder says where
                    } else {
                        self.doneJobs.insert(job.label)
                        self.partialFiles = []            // this format finished: its files are the real thing now
                        self.onChange?()                  // saves progress in the queue
                        self.runNext()
                    }
                } else {
                    self.fail()
                }
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            lastError = "Couldn't start yt-dlp."
            fail()
        }
    }

    /// A byte count as a readable size, like "41.2 MB".
    static func size(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func handle(_ line: String, label: String) {
        guard isRunning else { return }
        if line.hasPrefix("PROG ") {
            // "PROG downloaded total estimate speed vcodec acodec thumbnail-link Title of the video"
            let parts = line.split(separator: " ", maxSplits: 8)
            if parts.count == 9 {
                if thumbnail == nil, parts[7] != "NA" { thumbnail = URL(string: String(parts[7])) }
                if title == nil, parts[8] != "NA" { title = String(parts[8]) }
            }
            guard parts.count >= 7, let done = Double(parts[1]) else { return }
            if let total = Double(parts[2]) ?? Double(parts[3]), total > 0 {
                let f = min(done / total, 1)
                progress = f
                // A video usually comes in two parts, the picture and then the sound, each going 0–100%,
                // before they're joined. Say which part it is so it doesn't look like it restarted.
                let v = parts[5], a = parts[6]
                var step = "downloading"
                if label.hasPrefix("Video") {
                    if v == "none" { step = "downloading sound" }
                    else if v != "NA", a == "none" { step = "downloading picture" }
                }
                // e.g. "Video (file 1 of 2): downloading picture 42% · 41.2 MB of 98.6 MB · 2.3 MB/s"
                var text = "\(label): \(step) \(Int(f * 100))% · \(Self.size(done)) of \(Self.size(total))"
                if let speed = Double(parts[4]), speed > 0 { text += " · \(Self.size(speed))/s" }
                status = text
            }
        } else if line.contains("Writing video thumbnail"), let r = line.range(of: " to: ") {
            // e.g. "[info] Writing video thumbnail 41 to: /Users/you/Movies/Glass Crate/Song.webp"
            // A temporary file: it's embedded as cover art at the end and then deleted by yt-dlp.
            remember(String(line[r.upperBound...]))
        } else if line.hasPrefix("[download] Destination: ") {
            // e.g. "[download] Destination: /Users/you/Movies/Glass Crate/Song.f137.mp4"
            remember(String(line.dropFirst("[download] Destination: ".count)))
        } else if line.contains("[Merger]") {
            // e.g. [Merger] Merging formats into "/Users/you/Movies/Glass Crate/Song.mp4"
            if let start = line.firstIndex(of: "\""), let end = line.lastIndex(of: "\""), start < end {
                remember(String(line[line.index(after: start)..<end]))
            }
            progress = nil
            status = "\(label): joining picture and sound…"
        } else if line.contains("[ExtractAudio]") {
            progress = nil
            status = "\(label): converting audio…"
        } else if line.contains("[EmbedThumbnail]") || line.contains("[ThumbnailsConvertor]") {
            progress = nil
            status = "\(label): adding album art…"
        } else if line.contains("[Exec]") {
            progress = nil
            status = "\(label): converting to AIFF…"
        } else if line.contains("[Metadata]") {
            progress = nil
            status = "\(label): adding artist and title…"
        } else if line.hasSuffix(" has already been downloaded") {
            // e.g. "[download] /Users/you/Downloads/Song.mp3 has already been downloaded"
            let path = line
                .replacingOccurrences(of: "[download] ", with: "")
                .replacingOccurrences(of: " has already been downloaded", with: "")
            let name = (path as NSString).lastPathComponent
            existingFile = name
            if title == nil { title = (name as NSString).deletingPathExtension }
            progress = nil
            status = "\(label): already in this folder"
        } else if line.hasPrefix("ERROR:") {
            lastError = line
        }
    }

    private func remember(_ path: String) {
        if !partialFiles.contains(path) { partialFiles.append(path) }
    }

    /// Deletes Glass Crate's own unfinished files for this download, and nothing else:
    ///   "Song.f137.mp4.part", "Song.f137.mp4.ytdl", "Song.f137.mp4.part-Frag3" (partial downloads),
    ///   "Song.f137.mp4" (a picture or sound part that was never joined), "Song.temp.mp4" (an unfinished join),
    ///   and "Song.webp" (the thumbnail, saved first and normally deleted after it's embedded as cover art).
    /// A finished file ("Song.mp4") is never deleted, even if it has the same name as one Glass Crate was writing.
    func deletePartialFiles() {
        let fm = FileManager.default
        for path in partialFiles {
            let url = URL(fileURLWithPath: path)
            let dir = url.deletingLastPathComponent()
            let name = url.lastPathComponent
            var doomed = [path + ".part", path + ".ytdl"]
            // A format-only part, like "Song.f137.mp4" or "Song.f251-drc.webm"
            if name.range(of: #"\.f[0-9][0-9A-Za-z-]*\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil {
                doomed.append(path)
            }
            // The temporary thumbnail ("Song.webp"), and the copy made when it's converted ("Song.jpg" or "Song.png")
            if ["webp", "jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
                let base = url.deletingPathExtension().path
                doomed += [path, base + ".jpg", base + ".png"]
            }
            // An unfinished join: "Song.temp.mp4"
            doomed.append(url.deletingPathExtension().path + ".temp." + url.pathExtension)
            // Fragments: "Song.f137.mp4.part-Frag1", …
            if let names = try? fm.contentsOfDirectory(atPath: dir.path) {
                for n in names where n.hasPrefix(name + ".part-Frag") {
                    doomed.append(dir.appendingPathComponent(n).path)
                }
            }
            for f in doomed where fm.fileExists(atPath: f) {
                try? fm.removeItem(atPath: f)
            }
        }
        partialFiles = []
    }

    /// After the info step: keep the saved answer, and use its title and thumbnail if we don't have them yet.
    private func useInfoFile(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        infoFile = file
        if let data = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if title == nil, let t = json["title"] as? String { title = t }
            if thumbnail == nil, let t = json["thumbnail"] as? String { thumbnail = URL(string: t) }
        }
    }

    private func removeInfoFile() {
        if let infoFile { try? FileManager.default.removeItem(at: infoFile) }
        infoFile = nil
    }

    /// The file is already there: ask whether to replace it (download again) or skip it.
    private func askToReplace(_ name: String, job: Job) {
        let alert = NSAlert()
        alert.messageText = "“\(name)” already exists"
        alert.informativeText = "It's already in \(job.folder.lastPathComponent). Do you want to replace it with a new download?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")

        if alert.runModal() == .alertFirstButtonReturn {
            var again = job
            again.overwrite = true
            jobs.insert(again, at: 0)
        } else {
            doneJobs.insert(job.label)   // skipped: counts as done
        }
        runNext()
    }

    private func fail() {
        removeInfoFile()
        // YouTube says "too many requests" or "confirm you're not a bot": don't hammer it with retries.
        // Go back in line; the queue waits a few minutes (longer each time) before trying again.
        let slowDown = lastError.contains("not a bot") || lastError.contains("429") || lastError.contains("Too Many Requests")
        if !cancelled, slowDown, slowDownCount < 3 {
            slowDownCount += 1
            isRunning = false
            process = nil
            progress = nil
            isWaiting = true
            status = "YouTube asked Glass Crate to slow down. This download will try again automatically."
            let ytdlp = request.binDir + "/yt-dlp"
            DispatchQueue.global().async { _ = try? ToolManager.run(ytdlp, ["--rm-cache-dir"]) }   // local only
            onSlowDown?()
            onChange?()
            return
        }
        isRunning = false
        process = nil
        progress = nil
        if cancelled {
            wasCancelled = true
            status = "Cancelled."
        } else if lastError.contains("Requested format is not available") {
            failed = true
            status = "This link doesn't have a video to save. Uncheck MP4 and keep an audio format checked to save the sound."
        } else if slowDown {
            failed = true
            status = "YouTube is limiting downloads from your internet connection right now. This usually clears on its own, sometimes after an hour or more. Wait a while, then click Try Again."
        } else if lastError.contains("Unsupported URL") {
            failed = true
            status = "Glass Crate doesn't recognize this link. Make sure you copied the link to the video or track itself."
        } else if !lastError.isEmpty {
            failed = true
            status = lastError.replacingOccurrences(of: "ERROR: ", with: "")
        } else {
            failed = true
            status = "Download failed. Check the link and try again."
        }
        onChange?()
    }
}
