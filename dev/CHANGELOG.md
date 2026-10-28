# What's New

## Version 1.3.0

### New
- **A new look.** A new red icon, and every Glass Crate theme uses the same red: **Light**, **Crimson** (a deep red), **Dark**, and **Blackout**.
- **Open source.** Glass Crate's code is public on GitHub under the GPL-3.0 license, so anyone can see exactly what it does. New versions are downloaded from GitHub.

## Version 1.2.0

### New
- **Browse Media.** A phone-sized browser on the left side of the window. Pick **YouTube** or **SoundCloud**, find a video or track, and click **Add to Crate** at the bottom. It goes straight into the Download Queue with the formats checked on the right, with no copying and pasting. The website sits inside its own outlined "screen," and the browser follows your light or dark theme.
- **Add to Crate.** The main window and the browser now share one button, **Add to Crate**, with the same look, so it's always clear it's Glass Crate's button and not part of a website.
- **Themes.** Settings → General has two rows: **Glass Crate themes** (Light, Crimson, Dark, and Blackout, in Glass Crate's own colors) and **System themes** (Match System, Light, and Dark, using your Mac's accent color).
- **Interface Size.** Settings → General: any size from 70% to 130%, in 5% steps. Makes everything smaller or larger (text, icons, the browser, and the windows), which helps on laptop screens.
- **SoundCloud downloads are audio only.** MP4 is left out automatically, without changing your checkboxes. With no audio format checked, SoundCloud saves an MP3. While you browse SoundCloud, the main window shows only the Audio choices.
- **SoundCloud tracks show their title and artwork right away** when added to the queue, like YouTube videos. (SoundCloud is still unofficial.)

### Changed
- **Video quality moved to Settings → Downloads.** Best available is used unless you choose otherwise, so the main window is simpler.
- **Solid title bars** on every window, in the theme's color, that look the same whether the window is active or not.
- **Settings, About, and What's New open centered over the main window.**
- **The "slow down" countdown disappears** once no downloads from that site are left in the queue.

### Fixed
- **Switching themes now updates every open window** (Settings, About, and What's New used to keep the old colors).
- **Hiding or leaving a page pauses** anything playing, including SoundCloud.

### Good to know
- Browsing data (history, cookies, and sign-ins) stays inside Glass Crate, separate from Safari and Chrome, and Uninstall removes it.
- Glass Crate itself has no ads. The websites you browse show their own.

## Version 1.1.0

### New
- **Download Queue.** Add as many downloads as you like. Each time you click Download, the link goes into the Download Queue, which slides out from the right side of the window, and the link box clears so you can paste the next one.
- **One at a time.** Downloads run one after another, and the rest wait their turn and start automatically. This keeps YouTube from treating your downloads as a bot, and on a slow connection each download gets your full speed.
- **Each download has its own controls.** Cancel, Try Again (which keeps the same link, formats, and folders, and skips formats that already finished), and Open Video Folder / Open Audio Folder when it's done.
- **Easy to follow.** The download in progress is at the top, with its size and speed ("41.2 MB of 98.6 MB · 2.3 MB/s"). **Up Next** lists what's waiting, one line each, and **Finished** shows what's done.
- **Thumbnails and titles.** Each download shows the video's thumbnail and title as soon as you add it.
- **Clear menu.** Clear Finished removes downloads that finished. Clear All empties the whole queue, after asking. Your files stay where they are.
- **Download Queue icon.** Next to the gear, it opens and closes the queue, lights up when the queue is open, and shows how many downloads are in it.
- **Press Return** in the link box to download.
- **Your queue is saved.** Quitting with downloads running asks first, then saves the queue. Next time you open Glass Crate, unfinished downloads come back paused, ready to **Resume** one at a time or with **Resume All**. A partly downloaded file continues where it stopped.
- **Keep on top.** The pin button keeps Glass Crate, its Download Queue, and its Settings above all other windows, so you can keep browsing YouTube and still see your downloads. Glass Crate remembers your choice.
- **Settings in tabs:** General (appearance), Downloads (where files are saved), Updates, and Uninstall. The selected tab uses your Mac's accent color.
- **Uninstall tab.** Settings → Uninstall explains exactly what's removed and what stays. Uninstall also deletes the partial files of unfinished downloads, so nothing is left behind except your downloaded files.
- **Updates, Mac-style.** Settings → Updates lists each tool (yt-dlp, FFmpeg + FFprobe, and Deno) with the version you have and the newest version. Download, Install, or Skip each one on its own, and Retry a check that didn't go through. Downloaded updates wait until you choose to install them, even if you quit the app.
- **Update options.** Check once a week (on by default), download automatically (off), and install automatically (off). Check Now any time.
- **A quiet heads-up.** When an update is available or ready to install, a small **Update available** appears at the bottom of the window. No pop-ups.

### Changed
- **A simpler footer** with the version number. Click it for What's New. About is in the Glass Crate menu, and Uninstall is in Settings.
- **The gear lights up** while Settings is open, and clicking it again closes Settings.
- **Folder buttons always say which folder,** like **Open Audio Folder**.
- **Setup shows size and speed** while the tools download.
- **Dark mode by default,** and every window now uses the same background color, so the main window, the Download Queue, and Settings match.
- **A cleaner main window.** The Download Locations box moved to Settings → Downloads.
- **Closing the window quits Glass Crate,** including Settings and any other open windows.

### Fixed
- **Partial files are cleaned up.** Removing or clearing an unfinished download deletes its partial files (like `.part`), and so does quitting after cancelling one. Finished files are never touched.
- **Far fewer "confirm you're not a bot" blocks from YouTube.** YouTube shows this when it gets too many requests from one internet connection. Glass Crate now asks YouTube about each video only once, no matter how many formats you pick (before, it asked once per format). It connects over IPv4, which YouTube flags less often, and takes a short breather between downloads.
- **When YouTube says to slow down, Glass Crate waits instead of retrying.** The queue pauses and shows a countdown ("Trying again in 2:41") with a **Try Now** button, then picks up on its own. If it happens again, it waits longer (3, then 10, then 30 minutes).
- **Checking for updates no longer freezes the app.** Before, Check for Updates downloaded every tool again (about 200 MB) and blocked downloads until it finished, which could take a long time on a slow connection. Now checking downloads nothing, only the tools you choose are downloaded, every update can be cancelled, and you can keep downloading the whole time. Updates install between downloads, never in the middle of one.
- **The Download button stays blue** while the Download Queue is open.
- **The FFmpeg update check** works more reliably.

### Improved
- A clear message when YouTube asks to "confirm you're not a bot," explaining what it means and what to do.

### Good to know
- The saved queue is one small file, `queue.json`, in Glass Crate's own folder (`~/Library/Application Support/Glass Crate`). Uninstall removes it with everything else.

## Version 1.0.0

The first release.

- Download YouTube video as MP4, and audio as MP3, WAV, and AIFF, in any combination.
- Choose the video quality, from Best available down to 360p.
- MP3s get the thumbnail as square album art, and files are tagged with the title, artist, and album.
- Separate save folders for video and audio, with an optional folder for WAV and AIFF, or "Ask where to save each time."
- One-time setup that downloads the 4 tools Glass Crate uses into its own folder, with no Homebrew, Terminal, or password.
- Weekly update check for yt-dlp, plus Check for Updates for everything.
- Light, Dark, or Match System appearance, and larger-than-usual text.
- Uninstall removes the app, its tools, and its settings, and leaves your downloads alone.
