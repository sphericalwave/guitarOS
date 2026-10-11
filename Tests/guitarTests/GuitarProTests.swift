import Foundation
import Testing
@testable import guitar

/// Builds Guitar Pro 5.10 bytes in test code, so the reader is checked without committing anyone's tabs.
nonisolated struct GP5Fixture {
    struct Note { var string: Int; var fret: Int; var tie = false; var dead = false }
    struct Beat {
        /// −2 whole … 4 64th.
        var value: Int8 = 0
        var dotted = false
        var tuplet: Int32? = nil
        var rest = false
        var notes: [Note] = []
        var tempo: Int32? = nil
        var text: String? = nil
    }
    struct Measure {
        var numerator: Int8? = nil
        var denominator: Int8? = nil
        var repeatOpen = false
        var repeatClose: Int8? = nil
        var alternative: UInt8? = nil
        var marker: String? = nil
        /// Beats per track, voice 1 only.
        var beats: [[Beat]]
    }
    struct Track {
        var name: String
        var tunings: [Int32]
        var capo: Int32 = 0
        var channel: Int32 = 1
        var program: Int32 = 25
    }

    var title = "Test"
    var artist = "Nobody"
    var tempo: Int32 = 120
    var tracks: [Track]
    var measures: [Measure]

    func data() -> Data {
        var w = Writer()
        w.byteSizeString("FICHIER GUITAR PRO v5.10", block: 30)
        w.intByteSizeString(title)
        for text in ["", artist, "", "", "", "", "", ""] { w.intByteSizeString(text) }
        w.int32(1); w.intByteSizeString("a notice")
        w.int32(1)
        for _ in 0..<5 { w.int32(1); w.intSizeString("") }
        w.int32(100); w.int32(0); w.bytes(count: 11)                        // RSE master
        for _ in 0..<7 { w.int32(0) }; w.int16(0)                            // page setup
        for _ in 0..<10 { w.intByteSizeString("") }
        w.intByteSizeString("Moderate")
        w.int32(tempo); w.byte(0); w.byte(0); w.int32(0)
        for index in 0..<64 {
            let program = tracks.first { $0.channel == Int32(index + 1) }?.program ?? 0
            w.int32(program); w.byte(100); w.bytes(count: 7)
        }
        w.bytes(count: 38); w.int32(0)
        w.int32(Int32(measures.count)); w.int32(Int32(tracks.count))

        for (index, measure) in measures.enumerated() {
            if index > 0 { w.byte(0) }
            var flags: UInt8 = 0
            if measure.numerator != nil { flags |= 0x01 }
            if measure.denominator != nil { flags |= 0x02 }
            if measure.repeatOpen { flags |= 0x04 }
            if measure.repeatClose != nil { flags |= 0x08 }
            if measure.alternative != nil { flags |= 0x10 }
            if measure.marker != nil { flags |= 0x20 }
            w.byte(flags)
            if let n = measure.numerator { w.byte(UInt8(bitPattern: n)) }
            if let d = measure.denominator { w.byte(UInt8(bitPattern: d)) }
            if let close = measure.repeatClose { w.byte(UInt8(bitPattern: close)) }
            if let marker = measure.marker { w.intByteSizeString(marker); w.bytes(count: 4) }
            if let alternative = measure.alternative { w.byte(alternative) }
            if flags & 0x03 != 0 { w.bytes(count: 4) }
            if measure.alternative == nil { w.byte(0) }
            w.byte(0)
        }

        for (index, track) in tracks.enumerated() {
            if index == 0 { w.byte(0) }
            w.byte(0x08)
            w.byteSizeString(track.name, block: 40)
            w.int32(Int32(track.tunings.count))
            for string in 0..<7 { w.int32(string < track.tunings.count ? track.tunings[string] : 0) }
            w.int32(1); w.int32(track.channel); w.int32(track.channel + 1)
            w.int32(24); w.int32(track.capo); w.bytes(count: 4)
            w.int16(0); w.bytes(count: 3); w.bytes(count: 24)
            w.int32(0); w.int32(0); w.int32(0); w.int32(0)                   // RSE instrument
            w.bytes(count: 4); w.intByteSizeString(""); w.intByteSizeString("")
        }
        w.byte(0)

        for measure in measures {
            for (trackIndex, _) in tracks.enumerated() {
                let beats = trackIndex < measure.beats.count ? measure.beats[trackIndex] : []
                w.int32(Int32(beats.count))
                for beat in beats { write(beat, to: &w) }
                w.int32(0)                                                      // voice 2: empty
                w.byte(0)                                                       // line break
            }
        }
        return w.data
    }

    private func write(_ beat: Beat, to w: inout Writer) {
        var flags: UInt8 = 0
        if beat.dotted { flags |= 0x01 }
        if beat.text != nil { flags |= 0x04 }
        if beat.tempo != nil { flags |= 0x10 }
        if beat.tuplet != nil { flags |= 0x20 }
        if beat.rest { flags |= 0x40 }
        w.byte(flags)
        if beat.rest { w.byte(2) }
        w.byte(UInt8(bitPattern: beat.value))
        if let tuplet = beat.tuplet { w.int32(tuplet) }
        if let text = beat.text { w.intByteSizeString(text) }
        if let tempo = beat.tempo {
            w.byte(UInt8(bitPattern: -1))                                       // instrument
            w.int32(0); w.int32(0); w.int32(0); w.int32(0)                     // RSE
            for _ in 0..<6 { w.byte(UInt8(bitPattern: -1)) }                    // volume … tremolo
            w.intByteSizeString("")
            w.int32(tempo)
            w.byte(0); w.byte(0)                                                // tempo duration, hide
            w.byte(0); w.byte(0)                                                // flags, wah
            w.intByteSizeString(""); w.intByteSizeString("")
        }
        var stringFlags: UInt8 = 0
        for note in beat.notes { stringFlags |= 1 << (7 - note.string) }
        w.byte(stringFlags)
        for note in beat.notes.sorted(by: { $0.string < $1.string }) {
            w.byte(0x20 | 0x10)
            w.byte(note.tie ? 2 : (note.dead ? 3 : 1))
            w.byte(6)                                                           // dynamic f
            w.byte(UInt8(bitPattern: Int8(note.fret)))
            w.byte(0)                                                           // flags2
        }
        w.int16(0)
    }

    struct Writer {
        var data = Data()
        mutating func byte(_ value: UInt8) { data.append(value) }
        mutating func bytes(count: Int) { data.append(Data(repeating: 0, count: count)) }
        mutating func int16(_ value: Int16) { let v = UInt16(bitPattern: value); byte(UInt8(v & 0xFF)); byte(UInt8(v >> 8)) }
        mutating func int32(_ value: Int32) { let v = UInt32(bitPattern: value); for shift in stride(from: 0, to: 32, by: 8) { byte(UInt8((v >> UInt32(shift)) & 0xFF)) } }
        mutating func byteSizeString(_ text: String, block: Int) {
            let raw = Array(text.utf8).prefix(block)
            byte(UInt8(raw.count)); data.append(contentsOf: raw); bytes(count: block - raw.count)
        }
        mutating func intByteSizeString(_ text: String) {
            let raw = Array(text.utf8); int32(Int32(raw.count + 1)); byte(UInt8(raw.count)); data.append(contentsOf: raw)
        }
        mutating func intSizeString(_ text: String) { let raw = Array(text.utf8); int32(Int32(raw.count)); data.append(contentsOf: raw) }
    }
}

struct GP5ReaderTests {
    static let standard: [Int32] = [64, 59, 55, 50, 45, 40]

    /// Two measures: C major arpeggio in quarters, then a dotted half rest and an eighth with a tempo change.
    private func song() -> GP5Fixture {
        GP5Fixture(
            title: "Arpeggio", artist: "Fixture", tempo: 100,
            tracks: [.init(name: "Guitar", tunings: Self.standard, capo: 0), .init(name: "Bass", tunings: [43, 38, 33, 28], channel: 2, program: 33)],
            measures: [
                .init(numerator: 4, denominator: 4, beats: [
                    [.init(notes: [.init(string: 5, fret: 3)]), .init(notes: [.init(string: 4, fret: 2)]), .init(notes: [.init(string: 3, fret: 0)]), .init(notes: [.init(string: 2, fret: 1), .init(string: 1, fret: 0)])],
                    [.init(value: -1, notes: [.init(string: 4, fret: 3)]), .init(value: -1, rest: true)],
                ]),
                .init(marker: "Chorus", beats: [
                    [.init(value: -1, dotted: true, rest: true), .init(value: 1, notes: [.init(string: 1, fret: 3, tie: true)], tempo: 140)],
                    [.init(value: -2, notes: [.init(string: 4, fret: 3)])],
                ]),
            ]
        )
    }

    @Test func readsHeaderTracksAndNotes() throws {
        let score = try GP5Reader.read(song().data())
        #expect(score.title == "Arpeggio" && score.artist == "Fixture" && score.tempo == 100)
        #expect(score.measureHeaders.count == 2 && score.tracks.count == 2)
        #expect(score.measureHeaders[0].numerator == 4 && score.measureHeaders[1].numerator == 4, "time signature carries over")
        #expect(score.measureHeaders[1].marker == "Chorus")
        #expect(score.measureHeaders[1].tempo == nil, "the change isn't on the first beat")
        let guitar = score.tracks[0]
        #expect(guitar.name == "Guitar" && guitar.tunings == [64, 59, 55, 50, 45, 40] && guitar.program == 25 && guitar.channel == 0)
        #expect(guitar.tuningDescription == "E2 A2 D3 G3 B3 E4")
        #expect(score.tracks[1].program == 33 && score.tracks[1].stringCount == 4)
        let first = guitar.measures[0].voices[0]
        #expect(first.count == 4 && first.map(\.start) == [0, 960, 1920, 2880])
        #expect(first[3].notes.map(\.string) == [1, 2] && first[3].notes.map(\.fret) == [0, 1])
        #expect(first[0].notes.first?.velocity == 95)
        let second = guitar.measures[1].voices[0]
        #expect(second[0].isRest && second[0].duration == 2880)
        #expect(second[1].duration == 480 && second[1].tempo == 140 && second[1].notes.first?.isTie == true)
        #expect(score.tracks[1].measures[1].voices[0][0].duration == 3840)
    }

    @Test func rejectsOtherFormats() {
        #expect(throws: GP5Reader.ReadError.notGuitarPro5("FICHIER GUITAR PRO v4.06")) {
            var w = GP5Fixture.Writer(); w.byteSizeString("FICHIER GUITAR PRO v4.06", block: 30); w.bytes(count: 100)
            _ = try GP5Reader.read(w.data)
        }
        #expect(throws: GP5Reader.ReadError.truncated) { _ = try GP5Reader.read(song().data().prefix(400)) }
    }

    @Test func tupletsAndDotsScaleTheDuration() throws {
        let fixture = GP5Fixture(tracks: [.init(name: "G", tunings: Self.standard)], measures: [.init(beats: [[
            .init(value: 1, tuplet: 3, notes: [.init(string: 1, fret: 0)]), .init(value: 1, tuplet: 3, notes: [.init(string: 1, fret: 1)]), .init(value: 1, tuplet: 3, notes: [.init(string: 1, fret: 2)]),
            .init(value: 0, dotted: true, rest: true), .init(value: 1, rest: true),
        ]])])
        let beats = try GP5Reader.read(fixture.data()).tracks[0].measures[0].voices[0]
        #expect(beats.map(\.duration) == [320, 320, 320, 1440, 480])
        #expect(beats.last?.start == 2400)
    }
}

struct TabTimelineTests {
    private let plain = TabMeasureHeader()

    @Test func repeatsAndAlternateEndingsUnroll() {
        var open = TabMeasureHeader(); open.isRepeatOpen = true
        var first = TabMeasureHeader(); first.repeatAlternative = 0b01; first.repeatClose = 2
        var second = TabMeasureHeader(); second.repeatAlternative = 0b10
        #expect(TabTimeline.unrolledOrder([open, plain, first, second, plain]) == [0, 1, 2, 0, 1, 3, 4])
        var thrice = TabMeasureHeader(); thrice.repeatClose = 3
        #expect(TabTimeline.unrolledOrder([plain, open, thrice, plain]) == [0, 1, 2, 1, 2, 1, 2, 3])
        var bare = TabMeasureHeader(); bare.repeatClose = 1
        #expect(TabTimeline.unrolledOrder([open, bare]) == [0, 1, 0, 1], "a bare repeat sign plays twice")
    }

    @Test func notesGetSecondsFromTempoAndTempoChangesApply() throws {
        let fixture = GP5Fixture(tempo: 120, tracks: [.init(name: "G", tunings: GP5ReaderTests.standard, capo: 2)], measures: [
            .init(numerator: 4, denominator: 4, beats: [[.init(notes: [.init(string: 1, fret: 0)]), .init(notes: [.init(string: 1, fret: 1)]), .init(value: -1, rest: true)]]),
            .init(beats: [[.init(notes: [.init(string: 6, fret: 0)], tempo: 60), .init(value: -1, dotted: true, notes: [.init(string: 6, fret: 0, tie: true)])]]),
        ])
        let timeline = TabTimeline(score: try GP5Reader.read(fixture.data()))
        #expect(timeline.measures.count == 2)
        #expect(timeline.measures[0].duration == 2.0 && timeline.measures[0].tempo == 120)
        #expect(timeline.measures[1].start == 2.0 && timeline.measures[1].tempo == 60 && timeline.measures[1].duration == 4.0)
        #expect(timeline.duration == 6.0)
        let pitches = timeline.notes.map(\.pitch)
        #expect(pitches == [66, 67, 42, 42], "capo 2 raises every note")
        #expect(timeline.notes.map(\.start) == [0, 0.5, 2.0, 3.0])
        let expected = timeline.expectedNotes(track: 0)
        #expect(expected.count == 3 && expected.last?.time == 2.0, "the tie isn't struck")
        #expect(timeline.measureIndex(at: 1.9) == 0 && timeline.measureIndex(at: 2.0) == 1 && timeline.measureIndex(at: 99) == 1)
    }
}

/// The user's own Guitar Pro files, when this Mac has them. Nothing is committed; the test passes when the
/// folder is absent.
struct GP5RealFilesSmokeTest {
    @Test func everyLocalFileParsesAndUnrolls() throws {
        let folder = URL(filePath: NSHomeDirectory()).appending(path: "Documents/GuitarPro")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasSuffix(".gp5") {
            let data = try Data(contentsOf: folder.appending(path: name))
            let score = try GP5Reader.read(data)
            let timeline = TabTimeline(score: score)
            #expect(!score.tracks.isEmpty && !score.measureHeaders.isEmpty, Comment(rawValue: name))
            #expect(!score.guitarTracks.isEmpty, Comment(rawValue: name))
            #expect(timeline.duration > 10 && timeline.duration < 3600, "\(name): \(timeline.duration) s")
            #expect(timeline.notes.count > 50, "\(name): \(timeline.notes.count) notes")
            #expect(timeline.notes.allSatisfy { (20...100).contains(Int($0.pitch)) || score.tracks[$0.track].isPercussion }, Comment(rawValue: name))
        }
    }
}
