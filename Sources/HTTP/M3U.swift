import Foundation

/**
 - seealso: https://tools.ietf.org/html/draft-pantos-http-live-streaming-19
 */
struct M3U {
    static let header: String = "#EXTM3U"
    static let defaultVersion: Int = 3

    var version: Int = M3U.defaultVersion
    var mediaList: [M3UMediaInfo] = []
    var mediaSequence: Int = 0
    var targetDuration: Double = 5
}

extension M3U: CustomStringConvertible {
    // MARK: CustomStringConvertible
    var description: String {
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-PLAYLIST-TYPE:EVENT",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:4.2",
            "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)"
        ]
        for info in mediaList {
            guard info.duration < 6 else {
                print("LNT QUA", info.duration)
                continue
            }
            lines.append("#EXTINF:\(info.duration),")
            lines.append(info.url.pathComponents.last!)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: -
struct M3UMediaInfo {
    let url: URL
    let duration: Double
}
