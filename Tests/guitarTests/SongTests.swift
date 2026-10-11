import Foundation
import Testing
import SwiftData
@testable import guitar

struct TabStripLayoutTests {
    let layout = TabStripLayout(size: CGSize(width: 400, height: 150), window: 4, stringCount: 6, chordBand: 20)

    @Test func playheadSitsAThirdInAndTimeMapsToX() {
        #expect(layout.playheadX == 120)
        #expect(layout.pixelsPerSecond == 100)
        #expect(layout.x(forTime: 10, now: 10) == 120)
        #expect(layout.x(forTime: 11, now: 10) == 220)
        #expect(layout.x(forTime: 9.5, now: 10) == 70)
        let range = layout.visibleRange(now: 10)
        #expect(abs(range.lowerBound - 8.8) < 1e-9 && abs(range.upperBound - 12.8) < 1e-9)
    }

    @Test func stringsAreEvenlySpacedBelowTheChordBand() {
        // 130 points for 6 lines + 2 margins → 18.57 per spacing; string 1 is at the top.
        #expect(abs(layout.lineSpacing - 130.0 / 7) < 1e-9)
        #expect(abs(layout.y(string: 1) - (20 + 130.0 / 7)) < 1e-9)
        #expect(layout.y(string: 6) > layout.y(string: 1))
        #expect(layout.y(string: 9) == layout.y(string: 6), "clamped")
        #expect(layout.fretFontSize >= 9)
    }
}

struct SongLibraryTests {
    private func fixture() -> Data {
        GP5Fixture(title: "Fixture Song", artist: "Someone", tempo: 90,
                   tracks: [.init(name: "Drums", tunings: [], channel: 10), .init(name: "Lead", tunings: GP5ReaderTests.standard, capo: 3)],
                   measures: [.init(numerator: 4, denominator: 4, beats: [[], [.init(notes: [.init(string: 1, fret: 0)])]])]).data()
    }

    @Test func importPicksTheFirstGuitarTrackAndKeepsTheFile() throws {
        let data = fixture()
        let song = try SongLibrary.makeSong(from: data, fileName: "x.gp5")
        #expect(song.title == "Fixture Song" && song.artist == "Someone" && song.trackIndex == 1 && song.capo == 3)
        #expect(song.sourceData == data && song.sourceFormat == "gp5")
        let score = try SongLibrary.score(of: song)
        #expect(score.tracks.count == 2 && score.tracks[1].name == "Lead")
    }

    @Test func untitledFilesTakeTheFileName() throws {
        var w = GP5Fixture(tracks: [.init(name: "G", tunings: GP5ReaderTests.standard)], measures: [.init(beats: [[.init(rest: true)]])])
        w.title = ""
        let song = try SongLibrary.makeSong(from: w.data(), fileName: "My Riff.gp5")
        #expect(song.title == "My Riff")
    }

    @Test func otherFormatsAndDrumOnlyTabsAreRefused() {
        #expect(throws: SongLibrary.ImportError.self) { _ = try SongLibrary.makeSong(from: Data("not a tab".utf8), fileName: "a.gp5") }
        let drums = GP5Fixture(tracks: [.init(name: "Drums", tunings: [], channel: 10)], measures: [.init(beats: [[.init(rest: true)]])]).data()
        #expect(throws: SongLibrary.ImportError.self) { _ = try SongLibrary.makeSong(from: drums, fileName: "d.gp5") }
    }

    @Test func songsStoreAndLinkToBlocks() throws {
        let container = try ModelContainer(for: SkillCard.self, PracticeSession.self, PracticeBlock.self, Song.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let song = try SongLibrary.makeSong(from: fixture(), fileName: "x.gp5")
        context.insert(song)
        let block = PracticeBlock(kind: RoutineKind.song.rawValue, title: song.title)
        block.song = song
        context.insert(block)
        try context.save()
        #expect(song.blocks?.count == 1)
        #expect(try context.fetch(FetchDescriptor<Song>()).count == 1)
    }
}
