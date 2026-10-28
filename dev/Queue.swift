// Glass Crate — DOWNLOAD QUEUE
// The list of downloads, and the Download Queue panel: a drawer that slides out from behind the main window's right edge.
// Up to `maxPerSite` downloads run at the same time from one site; the rest wait their turn.
// Unfinished downloads are saved to "Glass Crate/queue.json" and come back paused after quitting.

import SwiftUI
import AppKit
import QuartzCore

final class DownloadQueue: ObservableObject {
    static let shared = DownloadQueue()

    /// How many downloads can run at once from the same site (YouTube, etc.).
    /// Lower this if YouTube starts refusing downloads ("HTTP Error 403").
    static let maxPerSite = 1

    @Published private(set) var items: [DownloadItem] = []   // newest first
    fileprivate func setItems(_ list: [DownloadItem]) { items = list }

    init() {
        restore()
        // After updated tools are swapped in, start anything that was waiting
        NotificationCenter.default.addObserver(forName: .glassCrateToolsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.schedule()
        }
    }

    var runningCount: Int { items.filter(\.isRunning).count }
    var waitingCount: Int { items.filter(\.isWaiting).count }
    var anyRunning: Bool { items.contains { $0.isRunning } }
    var hasCompleted: Bool { items.contains { $0.succeeded } }
    var pausedCount: Int { items.filter(\.isPaused).count }

    /// Download button: adds an item and starts it if there's room.
    func add(_ request: DownloadRequest) {
        let item = DownloadItem(request)
        attach(item)
        items.insert(item, at: 0)
        schedule()
    }

    /// "Resume All": everything restored after quitting goes back in line.
    func resumeAll() {
        for item in items.reversed() where item.isPaused { item.resume() }
    }

    func remove(_ item: DownloadItem) {
        guard !item.isRunning else { return }
        if !item.succeeded { item.deletePartialFiles() }   // its unfinished files go too; finished files stay
        items.removeAll { $0.id == item.id }
        schedule()
    }

    /// Quitting: save the queue (running and waiting downloads come back paused), then stop everything.
    func stopAll() {
        save()
        isQuitting = true
        // Cancelled downloads aren't saved, so their unfinished files would be left behind: delete them now
        for item in items where item.wasCancelled { item.deletePartialFiles() }
        for item in items where item.isRunning || item.isWaiting { item.cancel() }
    }
    /// Set once the user has chosen Quit, so the warning isn't shown twice.
    private(set) var isQuitting = false

    /// "Clear Finished": removes downloads that finished successfully. Failed, cancelled,
    /// waiting, and paused ones stay so you can try them again.
    func clearFinished() {
        items.removeAll { $0.succeeded }
        schedule()
    }

    /// "Clear All": empties the whole queue, after asking. Downloads in progress are stopped.
    func clearAllAsking() {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear the whole Download Queue?"
        alert.informativeText = anyRunning
            ? "Downloads in progress will be stopped, and everything waiting, paused, or failed will be removed. Files that already finished stay where they are."
            : "Everything waiting, paused, or failed will be removed. Files that already finished stay where they are."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        let clear = alert.addButton(withTitle: "Clear All")
        clear.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let all = items
        for item in all where item.isRunning { item.cancel() }
        items.removeAll()
        schedule()
        // Delete their unfinished files once yt-dlp has had a moment to stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for item in all where !item.succeeded { item.deletePartialFiles() }
        }
    }

    /// Uninstall: deletes the unfinished files of every download in the queue (nothing is running by then).
    func deleteAllPartialFiles() {
        isQuitting = true   // no more saving, and no "Downloads are still running" question
        for item in items where !item.succeeded { item.deletePartialFiles() }
    }

    // MARK: Being gentle with YouTube

    /// A short breather after each download before the next one from the same site starts.
    static let breather: TimeInterval = 8
    /// How long to wait when a site says "slow down": 3, then 10, then 30 minutes.
    static let slowDownWaits: [TimeInterval] = [3 * 60, 10 * 60, 30 * 60]

    /// No new downloads from a site until this time (breather or slow-down).
    private var holdUntil: [String: Date] = [:]
    /// When a site asked to slow down, the time it's waiting until (shown as a countdown in the queue).
    @Published private(set) var slowDownUntil: Date?
    /// Which site asked to slow down ("youtube", …)
    private(set) var slowDownSite: String?

    /// The countdown shows only while a download from that site is actually waiting.
    /// (Remove or clear them and it goes away. The wait itself still applies, so a new download
    /// from that site added before the time is up shows the countdown again.)
    var visibleSlowDown: Date? {
        guard let until = slowDownUntil, let site = slowDownSite,
              items.contains(where: { $0.site == site && ($0.isWaiting || $0.isRunning) }) else { return nil }
        return until
    }
    /// The site's name for the countdown message, e.g. "YouTube"
    var slowDownSiteName: String {
        items.first(where: { $0.site == slowDownSite })?.siteName ?? "The site"
    }
    private var slowDownLevel: [String: Int] = [:]
    private var succeededIDs: Set<UUID> = []
    private var wakeUp: DispatchWorkItem?

    /// Hooks up a download so the queue hears about its changes.
    private func attach(_ item: DownloadItem) {
        item.onChange = { [weak self, weak item] in
            guard let self else { return }
            if let item, item.succeeded, !self.succeededIDs.contains(item.id) {
                self.succeededIDs.insert(item.id)
                self.slowDownLevel[item.site] = 0                                       // all good again
                self.hold(item.site, until: Date().addingTimeInterval(Self.breather))   // short breather
            }
            self.schedule()
        }
        item.onSlowDown = { [weak self, weak item] in
            guard let self, let item else { return }
            let level = self.slowDownLevel[item.site, default: 0]
            let wait = Self.slowDownWaits[min(level, Self.slowDownWaits.count - 1)]
            self.slowDownLevel[item.site] = level + 1
            let until = Date().addingTimeInterval(wait)
            self.hold(item.site, until: until)
            self.slowDownUntil = until
            self.slowDownSite = item.site
        }
    }

    private func hold(_ site: String, until: Date) {
        if let existing = holdUntil[site], existing > until { return }
        holdUntil[site] = until
        scheduleWakeUp()
    }

    /// Checks the queue again when the next hold ends.
    private func scheduleWakeUp() {
        wakeUp?.cancel()
        guard let next = holdUntil.values.filter({ $0 > Date() }).min() else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let s = self.slowDownUntil, s <= Date() { self.slowDownUntil = nil }
            self.schedule()
            self.scheduleWakeUp()
        }
        wakeUp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, next.timeIntervalSinceNow), execute: work)
    }

    /// "Try Now": stop waiting and try right away.
    func tryNow() {
        holdUntil.removeAll()
        slowDownUntil = nil
        schedule()
    }

    /// Starts waiting items, oldest first, while each site is under its limit.
    func schedule() {
        // Don't start anything during the second or two that updated tools are being swapped in
        guard !UpdateManager.shared.isSwapping else { objectWillChange.send(); return }
        let now = Date()
        for item in items.reversed() where item.isWaiting {
            // Waiting out a "slow down" from the site, or the short breather after the last download
            if let until = holdUntil[item.site], until > now { continue }
            let running = items.filter { $0.isRunning && $0.site == item.site }.count
            if running < Self.maxPerSite { item.begin() }
        }
        ToolManager.shared.downloadsRunning = anyRunning   // so updates wait until downloads finish
        objectWillChange.send()                             // refresh counts in the panel and header
        save()
    }
}

// MARK: - Saving the queue

/// What's saved for each unfinished download.
private struct SavedItem: Codable {
    let request: DownloadRequest
    let title: String?
    let thumbnail: URL?
    let doneJobs: [String]
    let failedMessage: String?   // set if it had failed; it comes back with Try Again
    var partialFiles: [String]? = nil   // its unfinished files, so they can be cleaned up later (added in 1.1.0)
}

extension DownloadQueue {
    /// ~/Library/Application Support/Glass Crate/queue.json (removed by Uninstall with the rest of the folder)
    private var queueFile: URL {
        ToolManager.shared.binDir.deletingLastPathComponent().appendingPathComponent("queue.json")
    }

    /// Saves every download that isn't finished: running, waiting, paused, or failed.
    func save() {
        guard !isQuitting else { return }
        let keep = items.filter { $0.isRunning || $0.isWaiting || $0.isPaused || $0.failed }
        let saved = keep.map {
            SavedItem(request: $0.request, title: $0.title, thumbnail: $0.thumbnail,
                      doneJobs: Array($0.doneJobs), failedMessage: $0.failed ? $0.status : nil,
                      partialFiles: $0.partialFiles)
        }
        if saved.isEmpty {
            try? FileManager.default.removeItem(at: queueFile)
        } else if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: queueFile, options: .atomic)
        }
    }

    /// When the app opens: brings back the saved downloads, paused (or failed, with Try Again).
    fileprivate func restore() {
        guard let data = try? Data(contentsOf: queueFile),
              let saved = try? JSONDecoder().decode([SavedItem].self, from: data) else { return }
        let restored: [DownloadItem] = saved.map { s in
            let item = DownloadItem(s.request)
            item.title = s.title
            if let t = s.thumbnail { item.thumbnail = t }
            item.doneJobs = Set(s.doneJobs)
            item.partialFiles = s.partialFiles ?? []
            item.isWaiting = false
            if let msg = s.failedMessage {
                item.failed = true
                item.status = msg
            } else {
                item.isPaused = true
                item.status = s.doneJobs.isEmpty
                    ? "Paused. Click Resume to continue where it left off."
                    : "Paused after \(s.doneJobs.sorted().joined(separator: ", ")). Click Resume to finish the rest."
            }
            attach(item)
            return item
        }
        setItems(restored)
    }
}

// MARK: - The Download Queue panel

struct QueuePanel: View {
    @AppStorage(Appearance.key) private var themeMode = Appearance.defaultMode   // redraw when the theme changes
    @AppStorage(UIScale.key) private var uiScale = 1.0
    @ObservedObject var queue: DownloadQueue

    private var summary: String {
        var parts: [String] = []
        if queue.runningCount > 0 { parts.append("\(queue.runningCount) downloading") }
        if queue.waitingCount > 0 { parts.append("\(queue.waitingCount) waiting") }
        if queue.pausedCount > 0 { parts.append("\(queue.pausedCount) paused") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Download Queue").font(.gcTitle)
                Spacer()
                if queue.pausedCount > 0 {
                    Button("Resume All") { queue.resumeAll() }
                }
                Menu("Clear") {
                    Button("Clear Finished") { queue.clearFinished() }
                        .disabled(!queue.hasCompleted)
                    Button("Clear All…") { queue.clearAllAsking() }
                        .disabled(queue.items.isEmpty)
                }
                .fixedSize()
            }
            // "YouTube asked Glass Crate to slow down. Trying again in 2:41"  [Try Now]
            if let until = queue.visibleSlowDown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(until.timeIntervalSince(context.date)))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "hourglass")
                        Text("\(queue.slowDownSiteName) asked Glass Crate to slow down. Trying again in \(left / 60):\(String(format: "%02d", left % 60)).")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Try Now") { queue.tryNow() }
                            .controlSize(.small)
                    }
                    .font(.gcCallout)
                    .foregroundStyle(.secondary)
                }
            }
            if !summary.isEmpty {
                Text(summary)
                    .font(.gcCaption)
                    .foregroundStyle(.secondary)
            }

            if queue.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Nothing here yet")
                        .font(.gcHeadline)
                    Text("Paste a link and click Download. Each download shows up here with its progress, and you can keep adding more.")
                        .font(.gcCallout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Downloading at the top, then what's next (one line each), then finished ones
                let running = queue.items.filter(\.isRunning)
                let upNext = queue.items.reversed().filter { $0.isWaiting || $0.isPaused }   // in the order they'll run
                let done = queue.items.filter(\.isFinished)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(running) { item in
                            QueueRow(item: item) { queue.remove(item) }
                        }
                        if !upNext.isEmpty {
                            SectionLabel(text: "Up Next")
                            VStack(spacing: 6) {
                                ForEach(upNext) { item in
                                    CompactRow(item: item) { queue.remove(item) }
                                }
                            }
                        }
                        if !done.isEmpty {
                            SectionLabel(text: "Finished")
                            ForEach(done) { item in
                                QueueRow(item: item) { queue.remove(item) }
                            }
                        }
                    }
                }
            }
        }
        .padding(UIScale.s(20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            DrawerShape(radius: 10)
                .fill(Color.gcBackground)          // the app's background: very dark grey, or white in Light mode
        )
        .overlay(
            DrawerShape(radius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)   // thin grey border
        )
        .font(.gcBody)
        .controlSize(UIScale.controlSize)
        .tint(Color.gcAccent)
        .id("\(themeMode)-\(uiScale)")   // redraw when the theme or Interface Size changes
    }
}

/// A small heading in the queue, like "Up Next" or "Finished".
private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.gcCaption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

/// A waiting or paused download, on one line: small thumbnail, title, formats, and Resume or ✕.
private struct CompactRow: View {
    @ObservedObject var item: DownloadItem
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Thumbnail(url: item.thumbnail, site: item.siteName, small: true)
            Text(item.title ?? item.request.link)
                .font(.gcCallout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(item.request.summary)
                .font(.gcCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            if item.isPaused {
                Button("Resume") { item.resume() }
                    .controlSize(.small)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove from list")
        }
        .help(item.status)   // hover to see the full status, e.g. "Paused after Video…"
    }
}

/// The video's thumbnail (16:9). Until it loads, or if it can't, a plain video symbol
/// with the site's name ("YouTube", "soundcloud.com") shows where the download is from.
private struct Thumbnail: View {
    let url: URL?
    let site: String
    var small = false   // the one-line rows in "Up Next"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
            if small {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    Image(systemName: "play.rectangle")
                    Text(site)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)
            }
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: UIScale.s(small ? 32 : 64), height: UIScale.s(small ? 18 : 36))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// The drawer's outline: square on the left, where it meets the main window, rounded on the right.
private struct DrawerShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A progress bar that stays blue. (The Mac's standard one turns grey whenever its window isn't
/// the active one, and the Download Queue panel never becomes the active window.)
/// With no value (joining, converting), a short blue segment slides back and forth.
struct BlueProgressBar: View {
    @AppStorage(Appearance.key) private var themeMode = Appearance.defaultMode   // redraw when the theme changes
    let value: Double?
    private let height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                if let v = value {
                    Capsule()
                        .fill(Color.gcAccent)
                        .frame(width: max(height, geo.size.width * v))
                        .animation(.linear(duration: 0.2), value: v)
                } else {
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let segment = geo.size.width * 0.3
                        // eases back and forth across the bar every 1.2 seconds
                        let pos = (sin(t * .pi / 1.2) + 1) / 2
                        Capsule()
                            .fill(Color.gcAccent)
                            .frame(width: segment)
                            .offset(x: pos * (geo.size.width - segment))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// One download in the panel: title, formats, progress, status, and buttons.
private struct QueueRow: View {
    @ObservedObject var item: DownloadItem
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Thumbnail(url: item.thumbnail, site: item.siteName)
                Text(item.title ?? item.request.link)
                    .font(.gcHeadline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if !item.isRunning {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove from list (your files stay where they are)")
                }
            }
            Text(item.request.summary)
                .font(.gcCaption)
                .foregroundStyle(.secondary)

            if item.isRunning {
                BlueProgressBar(value: item.progress)
            }

            if item.failed {
                Label(item.status, systemImage: "exclamationmark.triangle.fill")
                    .font(.gcCallout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(item.status)
                    .font(.gcCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Spacer()
                if item.isPaused {
                    Button("Resume") { item.resume() }
                } else if item.isRunning || item.isWaiting {
                    Button("Cancel") { item.cancel() }
                } else if item.failed || item.wasCancelled {
                    Button("Try Again") { item.retry() }
                } else if item.succeeded {
                    ForEach(item.usedFolders) { f in
                        Button("Open \(f.name) Folder") {   // always names the folder, e.g. "Open Audio Folder"
                            NSWorkspace.shared.open(f.url)
                        }
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

// MARK: - The drawer: the Download Queue panel slides out from behind the main window's right edge

/// A borderless panel that can still take clicks and typing.
private final class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows and hides the Download Queue panel as a drawer attached to the main window.
/// It moves with the main window and never changes the main window's size or layout.
final class QueueDrawer {
    static let shared = QueueDrawer()

    /// The main window (set by WindowAccessor in GlassCrate.swift).
    weak var parent: NSWindow? {
        didSet { watchParent() }
    }

    private var panel: DrawerPanel?
    private(set) var isOpen = false
    private var onTop = false

    /// The pin button: keeps the main window (and this drawer) above all other windows.
    func setOnTop(_ on: Bool) {
        onTop = on
        let level: NSWindow.Level = on ? .floating : .normal
        parent?.level = level
        panel?.level = level
    }
    private var resizeObserver: NSObjectProtocol?

    static var width: CGFloat { UIScale.s(400) }   // follows Interface Size
    private static let insetTop: CGFloat = 40      // a little below the title bar
    private static let insetBottom: CGFloat = 12

    /// Where the drawer sits: hidden behind the main window, or slid out to its right.
    private func frame(open: Bool) -> NSRect {
        guard let p = parent?.frame else { return .zero }
        let height = max(200, p.height - Self.insetTop - Self.insetBottom)
        let x = open ? p.maxX - 1 : p.maxX - Self.width
        return NSRect(x: x, y: p.minY + Self.insetBottom, width: Self.width, height: height)
    }

    func show<Content: View>(_ content: Content, attempt: Int = 0) {
        guard let parent else { return }
        // When the app is just starting, the main window may not be on screen yet, and a drawer
        // attached then never appears. Wait a moment and try again (up to about 2 seconds).
        if !parent.isVisible || parent.frame.width < 100 {
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.show(content, attempt: attempt + 1)
                }
            }
            return
        }
        if panel == nil {
            let p = DrawerPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isReleasedWhenClosed = false
            p.becomesKeyOnlyIfNeeded = true   // clicks work, but the main window stays active (Download stays blue)
            panel = p
        }
        panel?.level = onTop ? .floating : .normal
        guard let panel else { return }
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []   // the drawer sets its own size; don't let the content resize it
        panel.contentView = host
        guard !isOpen else { return }
        isOpen = true

        panel.setFrame(frame(open: false), display: false)
        parent.addChildWindow(panel, ordered: .below)   // behind the main window, so it slides out from under it
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame(open: true), display: true)
        }
    }

    func hide() {
        guard isOpen, let panel else { return }
        isOpen = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(frame(open: false), display: true)
        }, completionHandler: { [weak self] in
            guard let self, !self.isOpen else { return }
            self.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        })
    }

    /// Keep the drawer's height matched to the main window when the main window changes size.
    private func watchParent() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        guard let parent else { return }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: parent, queue: .main
        ) { [weak self] _ in
            guard let self, self.isOpen, let panel = self.panel else { return }
            panel.setFrame(self.frame(open: true), display: true)
        }
    }
}

/// Finds the window a SwiftUI view lives in, so the drawer can attach to it.
struct WindowAccessor: NSViewRepresentable {
    let found: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { found(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Settings, About, and What's New: matching background, and they follow the pin

/// Gives a window the app's background, and makes it float when the pin is on,
/// so it opens in front of the pinned main window.
struct GlassCrateWindow: ViewModifier {
    @AppStorage(Appearance.key) private var themeMode = Appearance.defaultMode   // redraw when the theme changes
    @AppStorage(UIScale.key) private var uiScale = 1.0
    @AppStorage("keepOnTop") private var keepOnTop = false
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .controlSize(UIScale.controlSize)
            .id("\(themeMode)-\(uiScale)")   // redraw when the theme or Interface Size changes
            .glassCrateChrome()                // solid title bar and the theme's background
            .background(WindowAccessor { w in
                window = w
                w.useGlassCrateBackground()
                w.isRestorable = false        // don't reopen this window by itself next time the app opens
                w.level = keepOnTop ? .floating : .normal
                // Open centered over the main window, wherever that is, so it's never off to the side
                DispatchQueue.main.async {
                    if let main = QueueDrawer.shared.parent { Self.center(w, over: main) }
                    w.makeKeyAndOrderFront(nil)   // bring it in front of the pinned main window
                }
            })
            .onChange(of: keepOnTop) { on in
                window?.level = on ? .floating : .normal
            }
    }

    /// Moves `w` so it's centered over `main`, kept fully on the same screen.
    static func center(_ w: NSWindow, over main: NSWindow) {
        let m = main.frame
        var f = w.frame
        f.origin.x = m.midX - f.width / 2
        f.origin.y = m.midY - f.height / 2
        if let screen = (main.screen ?? NSScreen.main)?.visibleFrame {
            f.origin.x = min(max(f.origin.x, screen.minX), screen.maxX - f.width)
            f.origin.y = min(max(f.origin.y, screen.minY), screen.maxY - f.height)
        }
        w.setFrameOrigin(f.origin)
    }
}

extension View {
    /// Matching background, and floats when the pin is on (see GlassCrateWindow).
    func glassCrateWindow() -> some View { modifier(GlassCrateWindow()) }
}

// MARK: - Closing the main window quits the app

/// Glass Crate has one main window, so its red close button quits the whole app,
/// closing Settings and the other windows too. Quitting still warns if downloads are running.
final class QuitOnClose: NSObject {
    static let shared = QuitOnClose()

    static func attach(to window: NSWindow) {
        if let close = window.standardWindowButton(.closeButton) {
            close.target = shared
            close.action = #selector(quit)
        }
        // ⌘W or File > Close: once the main window is gone, quit too
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.terminate(nil)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)   // runs the "downloads still running" check first
    }
}
