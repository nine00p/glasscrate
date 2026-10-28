// Glassbox — MOVING OVER FROM GHOST CRATE (new in 1.3.0)
// Glassbox used to be called Ghost Crate. The first time Glassbox opens, this brings everything along,
// so nothing has to be set up again:
//   • the tools, the saved Download Queue, and any waiting updates
//     (~/Library/Application Support/Ghost Crate → …/Glassbox)
//   • settings: folders, checkboxes, theme, Interface Size, update options
//   • download folders: if you were using the default "Ghost Crate" folders in Movies and Music,
//     Glassbox keeps saving there, so your files stay together and your DJ software's library
//     doesn't break. (Your files are never moved or renamed.) You can change them in Settings → Downloads.
// Ghost Crate's old browser data is removed (sign in again in the browser), and if the old
// Ghost Crate app is still in Applications, Glassbox offers to move it to the Trash.

import AppKit

enum Migration {
    private static let oldName = "Ghost Crate"
    private static let oldID = "net.madebyjp.ghostcrate"
    private static let doneKey = "movedFromGhostCrate"

    /// Runs once, at the very start, before anything else uses the settings or the tools folder.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFolder = support.appendingPathComponent(oldName, isDirectory: true)
        let newFolder = support.appendingPathComponent("Glassbox", isDirectory: true)

        // 1. Tools, saved queue, and waiting updates
        if fm.fileExists(atPath: oldFolder.path) && !fm.fileExists(atPath: newFolder.path) {
            try? fm.moveItem(at: oldFolder, to: newFolder)
        }

        // 2. Settings (only ones Glassbox doesn't already have)
        guard let old = defaults.persistentDomain(forName: oldID) else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }

        // 3. Keep saving into the old default folders, if those are the ones in use
        let movies = fm.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent(oldName)
        let music = fm.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent(oldName)
        if (defaults.string(forKey: SaveFolders.videoKey) ?? "").isEmpty, fm.fileExists(atPath: movies.path) {
            defaults.set(movies.path, forKey: SaveFolders.videoKey)
        }
        if (defaults.string(forKey: SaveFolders.mp3Key) ?? "").isEmpty, fm.fileExists(atPath: music.path) {
            defaults.set(music.path, forKey: SaveFolders.mp3Key)
        }

        // 4. Clean up what Ghost Crate left behind
        defaults.removePersistentDomain(forName: oldID)
        removeOldBrowserData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { offerToTrashOldApp() }
    }

    /// Ghost Crate's browser history, cookies, and sign-ins (kept under its old name)
    static func removeOldBrowserData() {
        let fm = FileManager.default
        let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        for sub in ["WebKit/\(oldID)", "Caches/\(oldID)", "HTTPStorages/\(oldID)", "HTTPStorages/\(oldID).binarycookies"] {
            try? fm.removeItem(at: lib.appendingPathComponent(sub))
        }
    }

    /// Uninstall: anything of Ghost Crate's that's still around
    static func removeLeftovers() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.removeItem(at: support.appendingPathComponent(oldName, isDirectory: true))
        UserDefaults.standard.removePersistentDomain(forName: oldID)
        removeOldBrowserData()
    }

    /// If "Ghost Crate.app" is still in Applications, ask before moving it to the Trash.
    private static func offerToTrashOldApp() {
        let oldApp = URL(fileURLWithPath: "/Applications/\(oldName).app")
        guard FileManager.default.fileExists(atPath: oldApp.path),
              Bundle.main.bundleURL.standardizedFileURL != oldApp.standardizedFileURL else { return }
        let alert = NSAlert()
        alert.messageText = "Ghost Crate is now Glassbox"
        alert.informativeText = "Your settings, tools, and Download Queue came along. The old Ghost Crate app is still in your Applications folder. Move it to the Trash?"
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep It")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.trashItem(at: oldApp, resultingItemURL: nil)
    }
}
