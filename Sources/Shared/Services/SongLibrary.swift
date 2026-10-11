import Foundation
import SwiftData

/// Imports Guitar Pro files into the store and opens them again.
nonisolated enum SongLibrary {
    enum ImportError: LocalizedError {
        case unreadable(String)
        case noGuitarTrack

        var errorDescription: String? {
            switch self {
            case .unreadable(let reason): reason
            case .noGuitarTrack: "This tab has no string track to play."
            }
        }
    }

    /// Parses the file and makes a `Song` (not yet inserted). The first guitar track is the one to play.
    static func makeSong(from data: Data, fileName: String) throws -> Song {
        let score: TabScore
        do { score = try GP5Reader.read(data) } catch { throw ImportError.unreadable(error.localizedDescription) }
        guard let track = score.guitarTracks.first else { throw ImportError.noGuitarTrack }
        let title = score.title.isEmpty ? (fileName as NSString).deletingPathExtension : score.title
        let song = Song(title: title, artist: score.artist, sourceData: data, sourceFormat: "gp5", trackIndex: track)
        song.capo = score.tracks[track].capo
        return song
    }

    /// The song's score, parsed from the stored file.
    static func score(of song: Song) throws -> TabScore {
        guard let data = song.sourceData else { throw ImportError.unreadable("The song's file is missing.") }
        return try GP5Reader.read(data)
    }
}
