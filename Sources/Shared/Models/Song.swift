import Foundation
import SwiftData

/// An imported Guitar Pro song. The file itself is kept (external storage) and parsed on open; only what
/// the user chose (track, position, best) is stored alongside. CloudKit-safe: defaults everywhere, the one
/// relationship optional with an inverse.
@Model
final class Song {
    var title: String = ""
    var artist: String = ""
    @Attribute(.externalStorage) var sourceData: Data?
    /// "gp5" for now; "gp" (GP7/8) later.
    var sourceFormat: String = "gp5"
    /// Which track the player plays, as an index into the file's tracks.
    var trackIndex: Int = 0
    var capo: Int = 0
    /// Seconds, so reopening lands where practice stopped.
    var lastPosition: TimeInterval = 0
    /// 0...1 from the best play-along pass.
    var bestAccuracy: Double?
    var importedAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \PracticeBlock.song)
    var blocks: [PracticeBlock]? = []

    init(title: String, artist: String, sourceData: Data, sourceFormat: String = "gp5", trackIndex: Int = 0) {
        self.title = title
        self.artist = artist
        self.sourceData = sourceData
        self.sourceFormat = sourceFormat
        self.trackIndex = trackIndex
        importedAt = .now
    }
}
