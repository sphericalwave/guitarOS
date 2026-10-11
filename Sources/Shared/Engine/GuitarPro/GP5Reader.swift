import Foundation

/// Reads Guitar Pro 5 files (v5.00 and v5.10) into a `TabScore`. The format is little-endian binary with
/// three string encodings; it's documented by PyGuitarPro and TuxGuitar, read for the layout only.
///
/// What's read: title/artist/album, tempo (+ per-beat changes), time signatures, repeats and alternate
/// endings, markers, tracks (name, tuning, capo, program, channel), beats with duration/dots/tuplets, rests,
/// notes (string, fret, tie, dead, velocity) and the common effects as flags. Bends, graces, RSE and page
/// setup are skipped over, not interpreted.
nonisolated enum GP5Reader {
    enum ReadError: LocalizedError, Equatable {
        case notGuitarPro5(String)
        case truncated
        case badString

        var errorDescription: String? {
            switch self {
            case .notGuitarPro5(let version): "Not a Guitar Pro 5 file (\(version.isEmpty ? "unknown format" : version))."
            case .truncated: "The file ends early."
            case .badString: "The file has unreadable text."
            }
        }
    }

    static func read(_ data: Data) throws -> TabScore {
        var reader = ByteReader(data: data)
        let version = try reader.byteSizeString(block: 30)
        guard version.hasPrefix("FICHIER GUITAR PRO v5") else { throw ReadError.notGuitarPro5(version) }
        let isV510 = version != "FICHIER GUITAR PRO v5.00"
        var score = TabScore()

        // Info
        score.title = try reader.intByteSizeString()
        _ = try reader.intByteSizeString()            // subtitle
        score.artist = try reader.intByteSizeString()
        score.album = try reader.intByteSizeString()
        for _ in 0..<5 { _ = try reader.intByteSizeString() }   // words, music, copyright, tab, instructions
        let noticeLines = try reader.int32()
        for _ in 0..<max(0, noticeLines) { _ = try reader.intByteSizeString() }

        // Lyrics: track number, then five lines of (starting measure, text).
        _ = try reader.int32()
        for _ in 0..<5 {
            _ = try reader.int32()
            _ = try reader.intSizeString()
        }

        // RSE master effect (5.10): volume, unknown, 11-band equalizer.
        if isV510 {
            _ = try reader.int32()
            _ = try reader.int32()
            try reader.skip(11)
        }
        // Page setup: size, margins, score proportion, header/footer flags, ten template strings.
        try reader.skip(4 * 7 + 2)
        for _ in 0..<10 { _ = try reader.intByteSizeString() }

        _ = try reader.intByteSizeString()           // tempo name
        score.tempo = Int(try reader.int32())
        if isV510 { try reader.skip(1) }              // hide tempo
        try reader.skip(1)                            // key signature
        _ = try reader.int32()                        // octave

        // 64 MIDI channels: instrument then volume, balance, chorus, reverb, phaser, tremolo, two blanks.
        var channels: [(program: Int, volume: UInt8)] = []
        for _ in 0..<64 {
            let program = Int(try reader.int32())
            let volume = try reader.byte()
            try reader.skip(7)
            channels.append((max(0, program), volume))
        }
        try reader.skip(19 * 2)                       // directions
        _ = try reader.int32()                        // master reverb

        let measureCount = Int(try reader.int32())
        let trackCount = Int(try reader.int32())
        guard measureCount >= 0, trackCount >= 0, measureCount < 100_000, trackCount < 256 else { throw ReadError.truncated }

        for index in 0..<measureCount {
            if index > 0 { try reader.skip(1) }
            score.measureHeaders.append(try readMeasureHeader(&reader, previous: score.measureHeaders.last))
        }

        for index in 0..<trackCount {
            if index == 0 || !isV510 { try reader.skip(1) }
            score.tracks.append(try readTrack(&reader, channels: channels, isV510: isV510))
        }
        try reader.skip(isV510 ? 1 : 2)

        for _ in 0..<measureCount {
            for trackIndex in 0..<trackCount {
                var measure = TabMeasure()
                let stringCount = score.tracks[trackIndex].stringCount
                for voice in 0..<2 {
                    measure.voices[voice] = try readVoice(&reader, stringCount: stringCount, isV510: isV510)
                }
                // Line break marker; Guitar Pro leaves it off at the very end of the file.
                if reader.remaining > 0 { try reader.skip(1) }
                score.tracks[trackIndex].measures.append(measure)
            }
        }
        // The first beat's tempo change in a measure is the measure's tempo (for the timeline).
        for (index, _) in score.measureHeaders.enumerated() {
            let tempo = score.tracks.lazy.compactMap { $0.measures[index].voices[0].first?.tempo }.first
            score.measureHeaders[index].tempo = tempo
        }
        return score
    }

    // MARK: Sections

    private static func readMeasureHeader(_ reader: inout ByteReader, previous: TabMeasureHeader?) throws -> TabMeasureHeader {
        let flags = try reader.byte()
        var header = TabMeasureHeader()
        header.numerator = previous?.numerator ?? 4
        header.denominator = previous?.denominator ?? 4
        if flags & 0x01 != 0 { header.numerator = Int(try reader.signedByte()) }
        if flags & 0x02 != 0 { header.denominator = Int(try reader.signedByte()) }
        header.isRepeatOpen = flags & 0x04 != 0
        if flags & 0x08 != 0 { header.repeatClose = Int(try reader.signedByte()) }
        if flags & 0x20 != 0 {
            header.marker = try reader.intByteSizeString()
            try reader.skip(4)                        // colour
        }
        if flags & 0x10 != 0 { header.repeatAlternative = Int(try reader.byte()) }
        if flags & 0x40 != 0 { try reader.skip(2) }   // key signature + type
        if flags & 0x03 != 0 { try reader.skip(4) }   // beam groups
        if flags & 0x10 == 0 { try reader.skip(1) }
        try reader.skip(1)                            // triplet feel
        if header.numerator <= 0 { header.numerator = 4 }
        if header.denominator <= 0 { header.denominator = 4 }
        return header
    }

    private static func readTrack(_ reader: inout ByteReader, channels: [(program: Int, volume: UInt8)], isV510: Bool) throws -> TabTrack {
        var track = TabTrack()
        let flags = try reader.byte()
        track.isPercussion = flags & 0x01 != 0
        track.name = try reader.byteSizeString(block: 40)
        let stringCount = Int(try reader.int32())
        for index in 0..<7 {
            let pitch = try reader.int32()
            if index < stringCount { track.tunings.append(UInt8(clamping: pitch)) }
        }
        _ = try reader.int32()                        // port
        let channelIndex = Int(try reader.int32()) - 1
        _ = try reader.int32()                        // effect channel
        if channels.indices.contains(channelIndex) {
            track.program = channels[channelIndex].program
            track.volume = channels[channelIndex].volume
            track.channel = channelIndex % 16
            if track.channel == 9 { track.isPercussion = true }
        }
        _ = try reader.int32()                        // fret count
        track.capo = Int(try reader.int32())
        try reader.skip(4)                            // colour
        try reader.skip(2)                            // flags2
        try reader.skip(3)                            // auto accentuation, MIDI bank, humanize
        try reader.skip(4 * 3 + 12)
        try readRSEInstrument(&reader, isV510: isV510)
        if isV510 {
            try reader.skip(4)                        // equalizer
            _ = try reader.intByteSizeString()        // effect name
            _ = try reader.intByteSizeString()        // effect category
        }
        return track
    }

    private static func readRSEInstrument(_ reader: inout ByteReader, isV510: Bool) throws {
        try reader.skip(4 * 3)                        // instrument, unknown, sound bank
        if isV510 { try reader.skip(4) } else { try reader.skip(3) }   // effect number
    }

    private static func readVoice(_ reader: inout ByteReader, stringCount: Int, isV510: Bool) throws -> [TabBeat] {
        let count = Int(try reader.int32())
        guard count >= 0, count < 10_000 else { throw ReadError.truncated }
        var beats: [TabBeat] = []
        var start = 0
        for _ in 0..<count {
            var beat = try readBeat(&reader, stringCount: stringCount, isV510: isV510)
            beat.start = start
            start += beat.duration
            beats.append(beat)
        }
        return beats
    }

    private static func readBeat(_ reader: inout ByteReader, stringCount: Int, isV510: Bool) throws -> TabBeat {
        var beat = TabBeat()
        let flags = try reader.byte()
        var isEmpty = false
        if flags & 0x40 != 0 {
            let status = try reader.byte()
            beat.isRest = status == 0x02
            isEmpty = status == 0x00
        }
        beat.duration = try readDuration(&reader, flags: flags)
        if flags & 0x02 != 0 { beat.chordName = try readChord(&reader) }
        if flags & 0x04 != 0 { beat.text = try reader.intByteSizeString() }
        if flags & 0x08 != 0 { try readBeatEffects(&reader) }
        if flags & 0x10 != 0 { beat.tempo = try readMixTableChange(&reader, isV510: isV510) }
        let stringFlags = try reader.byte()
        for string in 1...max(stringCount, 1) where stringFlags & (1 << (7 - string)) != 0 {
            beat.notes.append(try readNote(&reader, string: string))
        }
        // GP5 extras: display flags, with an extra byte when bit 11 is set.
        let flags2 = try reader.int16()
        if flags2 & 0x0800 != 0 { try reader.skip(1) }
        if isEmpty { beat.notes = []; beat.isRest = true }
        return beat
    }

    /// Ticks for a beat: whole = −2 … 64th = 4, dotted ×1.5, tuplets scaled.
    private static func readDuration(_ reader: inout ByteReader, flags: UInt8) throws -> Int {
        let value = Int(try reader.signedByte())
        let shift = value + 2
        var ticks = shift >= 0 && shift < 7 ? TabScore.ticksPerQuarter * 4 / (1 << shift) : TabScore.ticksPerQuarter
        if flags & 0x01 != 0 { ticks = ticks * 3 / 2 }
        if flags & 0x20 != 0 {
            let enters = Int(try reader.int32())
            let times: Int
            switch enters {
            case 3: times = 2
            case 5, 6, 7: times = 4
            case 9, 10, 11, 12, 13: times = 8
            default: times = enters
            }
            if enters > 0 { ticks = ticks * times / enters }
        }
        return ticks
    }

    private static func readChord(_ reader: inout ByteReader) throws -> String {
        try reader.skip(17)
        let name = try reader.byteSizeString(block: 21)
        try reader.skip(4 + 4 + 7 * 4 + 32)
        return name
    }

    private static func readBeatEffects(_ reader: inout ByteReader) throws {
        let flags1 = try reader.byte()
        let flags2 = try reader.byte()
        if flags1 & 0x20 != 0 { try reader.skip(1) }          // slap/pop/tap
        if flags2 & 0x04 != 0 { try readBend(&reader) }        // tremolo bar
        if flags1 & 0x40 != 0 { try reader.skip(2) }          // stroke up/down
        if flags2 & 0x02 != 0 { try reader.skip(1) }          // pick stroke
    }

    private static func readBend(_ reader: inout ByteReader) throws {
        try reader.skip(1 + 4)
        let points = Int(try reader.int32())
        guard points >= 0, points < 1000 else { throw ReadError.truncated }
        try reader.skip(points * 9)
    }

    /// Returns the tempo change, if any.
    private static func readMixTableChange(_ reader: inout ByteReader, isV510: Bool) throws -> Int? {
        _ = try reader.signedByte()                   // instrument
        // Four Int32s in both 5.00 and 5.10 files (unlike the track's RSE block, 15 bytes in 5.00).
        try reader.skip(4 * 4)
        let values = try (0..<6).map { _ in try reader.signedByte() }   // volume, balance, chorus, reverb, phaser, tremolo
        _ = try reader.intByteSizeString()            // tempo name
        let tempo = Int(try reader.int32())
        for value in values where value >= 0 { try reader.skip(1) }    // durations
        if tempo >= 0 {
            try reader.skip(1)
            if isV510 { try reader.skip(1) }          // hide tempo
        }
        try reader.skip(1)                            // apply-to-all-tracks flags
        try reader.skip(1)                            // wah
        // Guitar Pro 5.10 documents an RSE effect name and category here, but files in the wild (including
        // GP5's own) often leave them out, so they're read only when they look like strings.
        for _ in 0..<2 where reader.looksLikeIntByteSizeString() { _ = try reader.intByteSizeString() }
        return tempo >= 0 ? tempo : nil
    }

    private static func readNote(_ reader: inout ByteReader, string: Int) throws -> TabNote {
        var note = TabNote(string: string, fret: 0)
        let flags = try reader.byte()
        if flags & 0x02 != 0 { note.effects.insert(.accent) }
        if flags & 0x04 != 0 { note.effects.insert(.ghost) }
        if flags & 0x40 != 0 { note.effects.insert(.accent) }
        if flags & 0x20 != 0 {
            let type = try reader.byte()
            note.isTie = type == 2
            note.isDead = type == 3
        }
        if flags & 0x10 != 0 {
            let dynamic = Int(try reader.signedByte())   // 1 (ppp) … 9 (fff)
            note.velocity = UInt8(clamping: 15 + 16 * max(1, min(dynamic, 9)) - 16)
        }
        if flags & 0x20 != 0 { note.fret = Int(try reader.signedByte()) }
        if flags & 0x80 != 0 { try reader.skip(2) }   // fingering
        if flags & 0x01 != 0 { try reader.skip(8) }   // duration percent
        try reader.skip(1)                            // flags2 (swap accidentals)
        if flags & 0x08 != 0 { try readNoteEffects(&reader, into: &note) }
        return note
    }

    private static func readNoteEffects(_ reader: inout ByteReader, into note: inout TabNote) throws {
        let flags1 = try reader.byte()
        let flags2 = try reader.byte()
        if flags1 & 0x01 != 0 { try readBend(&reader); note.effects.insert(.bend) }
        if flags1 & 0x02 != 0 { note.effects.insert(.hammerOn) }
        if flags1 & 0x08 != 0 { note.effects.insert(.letRing) }
        if flags1 & 0x10 != 0 { try reader.skip(5) }     // grace note
        if flags2 & 0x01 != 0 { note.effects.insert(.staccato) }
        if flags2 & 0x02 != 0 { note.effects.insert(.palmMute) }
        if flags2 & 0x04 != 0 { try reader.skip(1); note.effects.insert(.tremolo) }
        if flags2 & 0x08 != 0 { try reader.skip(1); note.effects.insert(.slide) }
        if flags2 & 0x10 != 0 {
            let type = try reader.signedByte()
            if type == 2 { try reader.skip(3) } else if type == 3 { try reader.skip(1) }
            note.effects.insert(.harmonic)
        }
        if flags2 & 0x20 != 0 { try reader.skip(2) }     // trill
        if flags2 & 0x40 != 0 { note.effects.insert(.vibrato) }
    }
}

/// Little-endian cursor over the file's bytes with Guitar Pro's string encodings.
nonisolated struct ByteReader {
    let data: Data
    private(set) var offset = 0

    init(data: Data) { self.data = data }

    var remaining: Int { data.count - offset }

    /// Whether the next bytes could be an `intByteSizeString` (a small Int32 total, then its byte length).
    func looksLikeIntByteSizeString() -> Bool {
        guard remaining >= 5 else { return false }
        let start = data.startIndex + offset
        let total = Int(data[start]) | Int(data[start + 1]) << 8 | Int(data[start + 2]) << 16 | Int(data[start + 3]) << 24
        return total >= 1 && total <= 256 && Int(data[start + 4]) == total - 1 && remaining >= 4 + total
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, remaining >= count else { throw GP5Reader.ReadError.truncated }
        offset += count
    }

    mutating func byte() throws -> UInt8 {
        guard remaining >= 1 else { throw GP5Reader.ReadError.truncated }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func signedByte() throws -> Int8 { Int8(bitPattern: try byte()) }

    mutating func int16() throws -> Int16 {
        let low = UInt16(try byte()), high = UInt16(try byte())
        return Int16(bitPattern: low | (high << 8))
    }

    mutating func int32() throws -> Int32 {
        var value: UInt32 = 0
        for shift in stride(from: 0, to: 32, by: 8) { value |= UInt32(try byte()) << UInt32(shift) }
        return Int32(bitPattern: value)
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw GP5Reader.ReadError.truncated }
        defer { offset += count }
        return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + count))
    }

    /// A byte length, then `block` bytes of which the first `length` are the text.
    mutating func byteSizeString(block: Int) throws -> String {
        let length = Int(try byte())
        let raw = try bytes(block)
        return Self.decode(raw.prefix(min(length, block)))
    }

    /// Int32 (length + 1), a byte length, then the text.
    mutating func intByteSizeString() throws -> String {
        let total = Int(try int32())
        let length = Int(try byte())
        guard total >= 1, length == total - 1 || length <= total - 1 else { throw GP5Reader.ReadError.badString }
        let raw = try bytes(total - 1)
        return Self.decode(raw.prefix(length))
    }

    /// Int32 length, then the text.
    mutating func intSizeString() throws -> String {
        let length = Int(try int32())
        guard length >= 0 else { throw GP5Reader.ReadError.badString }
        return Self.decode(try bytes(length))
    }

    /// Guitar Pro text is Windows-1252; UTF-8 is tried first for files written by newer tools.
    static func decode(_ raw: Data) -> String {
        String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .windowsCP1252) ?? String(decoding: raw, as: UTF8.self)
    }
}
