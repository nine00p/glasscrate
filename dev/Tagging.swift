// Glass Crate — TAGGING ADD-ON
// Artist and album tags, album art, and the "Encoded by" tag.
// These are yt-dlp settings that Downloader.swift adds to each download.

enum Tagging {
    /// Written to the "Encoded by" tag (MP3, WAV, and AIFF), like other apps that make audio files.
    static let signature = "Glass Crate"

    /// Added to every download (video, MP3, and WAV).
    static var common: [String] {
        [
            "--embed-metadata",
            // Artist: the official artist if the site lists one, otherwise the channel or account name
            "--parse-metadata", "%(artist,channel,uploader)s:%(meta_artist)s",
            // Album: the video title (so songs don't land under "Unknown Album")
            "--parse-metadata", "%(album,title)s:%(meta_album)s",
            // "Encoded by: Glass Crate"
            "--parse-metadata", "%(glasscrate_tag|\(signature))s:%(meta_encoded_by)s",
        ]
    }

    /// Video (MP4): the full-size thumbnail as the cover image.
    static let videoArt: [String] = [
        "--embed-thumbnail",
    ]

    /// MP3: the thumbnail as album art, cropped to a centered square.
    static let squareAlbumArt: [String] = [
        "--embed-thumbnail", "--convert-thumbnails", "jpg",
        "--ppa", "ThumbnailsConvertor+FFmpeg_o:-c:v mjpeg -vf crop=\"'if(gt(ih,iw),iw,ih)':'if(gt(iw,ih),ih,iw)'\"",
    ]

    /// WAV: no album art (WAV doesn't reliably support it).
    static let wavArt: [String] = []

    /// AIFF: no album art for now. Tags carry over from the temporary WAV during conversion.
    static let aiffArt: [String] = []
}
