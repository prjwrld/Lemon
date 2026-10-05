import Foundation

/// Where Lemon lives online. Lemon is free software (GPL-3.0); it never goes online by itself.
enum ProjectInfo {
    static let repositoryURL = URL(string: "https://github.com/prjwrld/Lemon")!
    static let issuesURL = URL(string: "https://github.com/prjwrld/Lemon/issues")!
    static let releasesURL = URL(string: "https://github.com/prjwrld/Lemon/releases")!
    /// The exact FFmpeg source Lemon's media helper is built from (see scripts/build-ffmpeg.sh).
    static let ffmpegSourceURL = URL(string: "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz")!
}
