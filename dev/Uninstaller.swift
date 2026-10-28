// Glass Crate — UNINSTALLER 
// Uninstall (Settings → Uninstall, and the Glass Crate menu), and the Quit button on the setup screen.
// Removes the app, the tools it downloaded, its settings, the saved queue, and Glass Crate's own
// partial downloads. Downloaded videos and music are not touched.

import AppKit

enum Uninstaller {
    /// "Uninstall" (Settings → Uninstall, and the menu item): asks first, then removes everything.
    static func run() {
        // Not while something is downloading or installing (the Settings button is greyed out then too)
        if DownloadQueue.shared.anyRunning || ToolManager.shared.busy || UpdateManager.shared.isWorking {
            let wait = NSAlert()
            wait.messageText = "Glass Crate is busy"
            wait.informativeText = "Wait for downloads and updates to finish, or cancel them, then uninstall."
            wait.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Uninstall Glass Crate?"
        alert.informativeText = "This moves the app to the Trash and removes the tools it downloaded, its settings, the saved Download Queue, Browse Media's browsing data, and any unfinished partial downloads. Videos and music you've already downloaded are not touched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Browse Media's history, cookies, and sign-ins first (this finishes in a moment), then everything else
        BrowserModel.removeAllBrowsingData { removeEverything() }
    }

    /// "Quit" on the setup screen: confirms, then closes the app.
    /// Anything setup already downloaded is deleted as the app closes (see AppDelegate in GlassCrate.swift).
    static func quitSetup() {
        let alert = NSAlert()
        alert.messageText = "Quit setup?"
        alert.informativeText = "Glass Crate will close. You can finish setup the next time you open it."
        alert.addButton(withTitle: "Go Back")   // first: Return key goes back, the safe choice
        alert.addButton(withTitle: "Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        NSApp.terminate(nil)
    }

    /// Deletes the tools folder and settings, moves the app to the Trash, and quits.
    private static func removeEverything() {
        let fm = FileManager.default

        // Glass Crate's own unfinished files for downloads still in the queue (".part" and similar).
        // Only files Glass Crate itself was writing; anything else in those folders is left alone.
        DownloadQueue.shared.deleteAllPartialFiles()

        // Tools folder: ~/Library/Application Support/Glass Crate
        let supportDir = ToolManager.shared.binDir.deletingLastPathComponent()
        try? fm.removeItem(at: supportDir)

        // Saved settings (download folder, dark mode, checkboxes, last update check)
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }

        // The app itself goes to the Trash
        var appGone = true
        do {
            try fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        } catch {
            appGone = false
        }

        let done = NSAlert()
        done.messageText = appGone ? "Glass Crate has been removed." : "Almost done"
        done.informativeText = appGone
            ? "Empty the Trash whenever you like to finish."
            : "The tools and settings were removed. Drag Glass Crate from your Applications folder to the Trash to finish."
        done.runModal()
        NSApp.terminate(nil)
    }
}
