# Glass Crate

*Glass Crate is named for what makes it different: like a crate made of glass, there's nothing hidden inside. It tells you exactly what it uses, where it keeps it, and removes all of it when you're done.*

Glass Crate is **free and open source** (GPL-3.0). See the code, report a problem, or get the latest version at [github.com/nine00p/glasscrate](https://github.com/nine00p/glasscrate).

Download video and audio in the best quality available. Paste a link (or find something in the browser on the left), check the formats you want (as many as you like), and click **Add to Crate**. Then paste the next one: downloads line up in the Download Queue and run on their own.

## How it works

Glass Crate is a simple, friendly window on top of free, open-source tools that do the actual work:

- **yt-dlp** downloads the video or audio from YouTube.
- **ffmpeg** joins video and audio together, converts audio to MP3, WAV, or AIFF, and adds album art.
- **Deno** helps yt-dlp read YouTube's pages so downloads keep working.

The first time the app opens, it downloads these tools (about 200 MB) into its own private folder. Nothing else on your Mac is changed, and no password or Terminal is needed.

## Staying up to date

YouTube changes things often, so the tools Glass Crate uses get updates now and then. Updates work like they do on a Mac: always there when you want them, never in your way.

- Open **Settings → Updates** any time (the gear at the top right, or ⌘,). When an update is available or downloaded and ready, a small **Update available** appears at the bottom of the window; click it to go straight there.
- Each tool updates on its own: yt-dlp, FFmpeg + FFprobe (they update together), and Deno. Each shows the version you have, the newer version, and its size.
- **Download** gets the update, with a progress bar and **Cancel**. Then **Install** whenever you're ready. Downloaded updates wait, even if you quit the app.
- **Skip** hides that version until an even newer one comes out.
- You can keep using the app the whole time. Updates install between downloads, never in the middle of one.
- By default, Glass Crate checks once a week and never downloads or installs on its own. You can change that in Settings → Updates, or click **Check Now** any time.

## What you get

- **Video: MP4** at the best quality available, or the quality you choose in **Settings → Downloads** (or the closest one below it).
- **Audio: MP3** at the highest MP3 quality, with the thumbnail as square album art.
- **Audio: WAV and AIFF**, uncompressed, for editing, production, or your DJ library. AIFF is the Apple-friendly version of WAV.

Check any combination and each one is saved as its own file, so one click can get you the video, an MP3, a WAV, and an AIFF.

Each file is tagged with the title, the artist (the official artist when YouTube lists one, otherwise the channel name), and the video title as the album.

## Downloading several at once

Each time you click **Add to Crate**, the link goes into the **Download Queue**, which slides out on the right, and the link box clears so you can paste the next one. Each download keeps the formats and folders that were chosen when you added it.

You can add as many downloads as you like. They download one after another, and the rest wait their turn and start automatically. One at a time keeps YouTube from treating your downloads as a bot, and on a slow internet connection each download gets your full speed, so it finishes sooner and is less likely to stall.

The download in progress is at the top of the queue, showing its size and speed as it goes. Below it, **Up Next** lists the downloads waiting their turn, one line each, in the order they'll run, and **Finished** shows the ones that are done.

Each download shows its progress, with **Cancel**, **Try Again**, or buttons to open its folders. **Try Again** keeps the same link, formats, and folders, so there's nothing to set up again, and skips any formats that already finished.

The **Clear** menu at the top of the queue has **Clear Finished**, which removes downloads that finished, and **Clear All**, which empties the whole queue after asking. Failed and paused downloads stay until you clear them all, so you can try them again. Your files always stay where they are.

The **Download Queue icon** at the top right, next to the gear, opens and closes the queue. It lights up when the queue is open, and a small number shows how many downloads are in it.

Your Download Queue is saved. If you quit while downloads are running or waiting, Glass Crate asks first. When you open it again, unfinished downloads come back paused: click **Resume** on one, or **Resume All**. A file that was partly downloaded continues where it stopped, and formats that already finished aren't downloaded again. The queue is kept in one small file, `queue.json`, in Glass Crate's own folder, and Uninstall removes it.

## Browse Media

**Browse Media** is the phone-sized browser on the left side of the window. Pick **YouTube** or **SoundCloud** and browse their mobile sites right inside Glass Crate. It follows your theme (light or dark), and the website sits inside its own outlined "screen," so it's easy to tell the website from Glass Crate.

When you're on a video or track, **Add to Crate** at the bottom of the browser lights up. Click it to add that video or track to the Download Queue with the formats checked on the right. It's the same button as the one on the right, so you always know it's Glass Crate's, not part of the website. Use the arrows to go back and forward, and **Sites** to return to the list of sites (anything playing pauses).

On SoundCloud, which only has audio, the Video choice disappears and only the Audio formats show.

**About ads:** Glass Crate itself has no ads. The websites you browse, like YouTube and SoundCloud, show their own ads, the same as they would in any browser.

Your browsing (history, cookies, and any sign-ins) is kept inside Glass Crate, separate from Safari and Chrome. Uninstall removes it.

## Keep it on top

Click the **pin** at the top right to keep Glass Crate, and its Download Queue, above all your other windows. It's handy for browsing YouTube while you watch your downloads. Click the pin again to turn it off. Glass Crate remembers your choice.

## Where files are saved

Videos go to a **Glass Crate** folder inside your **Movies** folder, and audio goes to a **Glass Crate** folder inside your **Music** folder, unless you choose different ones. Each folder is created the first time something is saved to it, and uninstalling the app leaves your downloads where they are.

WAV and AIFF files go to the Audio folder too, unless you give them a separate one, like a folder your music software uses.

To see or change the folders, click the gear at the top right, or press ⌘, to open **Settings**, then choose the **Downloads** tab. If you'd rather pick a folder every time, check **Ask where to save each time** there.

## Themes and size

In **Settings → General**, pick a theme:

- **Glass Crate themes:** **Light**, **Crimson**, **Dark**, and **Blackout**, in Glass Crate's own colors, the red of the app icon.
- **System themes:** **Match System** (follows your Mac, and switches when your Mac does), **Light**, and **Dark**, using your Mac's look and accent color.

**Interface Size** (70% to 130%, in 5% steps) makes everything smaller or larger: text, icons, the browser, and the windows. On a laptop screen, a smaller size gives you more room.

## Tips

- If a download fails, click **Try Again**. If it keeps failing, open **Settings → Updates** and click **Check Now**. An update fixes most problems.
- If YouTube says to slow down (or to "confirm you're not a bot"), it's seen a lot of requests from your internet connection. Glass Crate pauses the queue and tries again on its own after a few minutes; you'll see a countdown with **Try Now**. A VPN can make this happen more often.
- Only download content you own or have permission to save.

## Other sites

YouTube is the only officially supported site. Links from some other sites may also work, since yt-dlp understands many of them, but they aren't tested or supported. If a link has no video, like a music track, uncheck **MP4** and keep an audio format checked.

## Uninstalling

Open **Settings → Uninstall**, or choose **Uninstall Glass Crate…** from the **Glass Crate** menu at the top left. The Uninstall tab lists exactly what's removed: the app (moved to the Trash), the tools it downloaded, its settings, the saved Download Queue, downloaded updates that weren't installed, and the partial files of unfinished downloads. Files you've downloaded, and their folders, are not touched.

Use Uninstall instead of dragging the app to the Trash, so the tools it downloaded (about 200 MB) are removed too.

This app was made by [MadebyJP](http://www.madebyjp.net).
