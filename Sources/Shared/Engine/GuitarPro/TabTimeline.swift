import Foundation
import PlayAlongKit

/// A tab laid out in time: repeats unrolled, tempo changes applied, every sounding note with its start
/// and length in seconds. What playback schedules and what the judge expects.
nonisolated struct TabTimeline: Equatable, Sendable {
    struct Note: Equatable, Sendable, Identifiable {
        var id: Int
        var track: Int
        var start: TimeInterval
        var duration: TimeInterval
        var pitch: UInt8
        var velocity: UInt8
        var string: Int
        var fret: Int
        /// Index into `measures` (the unrolled pass, not the file's measure number).
        var measure: Int
        var effects: TabNote.Effects
        var isTie: Bool
        var isDead: Bool
    }

    struct Measure: Equatable, Sendable {
        /// The file's measure (0-based).
        var source: Int
        var start: TimeInterval
        var duration: TimeInterval
        var tempo: Int
        var numerator: Int
        var denominator: Int
        var marker: String?
    }

    struct Beat: Equatable, Sendable {
        var start: TimeInterval
        var track: Int
        var measure: Int
        var chordName: String?
        var text: String?
    }

    var measures: [Measure] = []
    /// Every track's notes, by start.
    var notes: [Note] = []
    var beats: [Beat] = []
    var duration: TimeInterval { measures.last.map { $0.start + $0.duration } ?? 0 }

    init(score: TabScore) {
        var time: TimeInterval = 0
        var tempo = max(score.tempo, 1)
        var nextID = 0
        for source in Self.unrolledOrder(score.measureHeaders) {
            let header = score.measureHeaders[source]
            if let change = header.tempo { tempo = max(change, 1) }
            let measureIndex = measures.count
            let measureStart = time
            var measureTempo = tempo
            var measureEnd = measureStart + Self.seconds(ticks: header.ticks, tempo: tempo)
            for (trackIndex, track) in score.tracks.enumerated() where track.measures.indices.contains(source) {
                for voice in track.measures[source].voices {
                    var beatTime = measureStart
                    var beatTempo = measureTempo
                    for beat in voice {
                        if let change = beat.tempo {
                            beatTempo = max(change, 1)
                            if beat.start == 0 { measureTempo = beatTempo }
                        }
                        let seconds = Self.seconds(ticks: beat.duration, tempo: beatTempo)
                        if beat.chordName != nil || beat.text != nil {
                            beats.append(Beat(start: beatTime, track: trackIndex, measure: measureIndex, chordName: beat.chordName, text: beat.text))
                        }
                        for note in beat.notes where !beat.isRest && track.tunings.indices.contains(note.string - 1) {
                            let pitch = track.isPercussion ? UInt8(clamping: note.fret) : UInt8(clamping: Int(track.tunings[note.string - 1]) + note.fret + track.capo)
                            notes.append(Note(id: nextID, track: trackIndex, start: beatTime, duration: seconds, pitch: pitch, velocity: note.velocity,
                                              string: note.string, fret: note.fret, measure: measureIndex, effects: note.effects, isTie: note.isTie, isDead: note.isDead))
                            nextID += 1
                        }
                        beatTime += seconds
                    }
                    if trackIndex == 0, voice == track.measures[source].voices.first { measureEnd = max(measureEnd, beatTime) }
                    tempo = beatTempo
                }
            }
            measures.append(Measure(source: source, start: measureStart, duration: measureEnd - measureStart, tempo: measureTempo,
                                    numerator: header.numerator, denominator: header.denominator, marker: header.marker))
            time = measureEnd
        }
        notes.sort { $0.start != $1.start ? $0.start < $1.start : $0.pitch < $1.pitch }
    }

    static func seconds(ticks: Int, tempo: Int) -> TimeInterval {
        Double(ticks) / Double(TabScore.ticksPerQuarter) * 60 / Double(max(tempo, 1))
    }

    /// Measure indices in playing order: repeat sections play `repeatClose` times (a bare sign twice),
    /// alternate endings only on their pass.
    static func unrolledOrder(_ headers: [TabMeasureHeader]) -> [Int] {
        var order: [Int] = []
        var index = 0
        var repeatStart = 0
        var pass = 1
        var guardCount = 0
        while index < headers.count, guardCount < 100_000 {
            guardCount += 1
            let header = headers[index]
            if header.isRepeatOpen, pass == 1 { repeatStart = index }
            if header.repeatAlternative != 0, header.repeatAlternative & (1 << (pass - 1)) == 0 {
                // Not this pass's ending: skip to the next measure that isn't an ending, or past the repeat.
                index += 1
                while index < headers.count, headers[index].repeatAlternative != 0, headers[index].repeatAlternative & (1 << (pass - 1)) == 0 { index += 1 }
                continue
            }
            order.append(index)
            if header.repeatClose > 0 {
                let total = max(header.repeatClose, 2)
                if pass < total, repeatStart <= index {
                    pass += 1
                    index = repeatStart
                    continue
                }
                pass = 1
                repeatStart = index + 1
            } else if header.repeatAlternative != 0, index + 1 >= headers.count || headers[index + 1].repeatAlternative == 0 {
                // The last ending ran out without a repeat sign: the section is over.
                pass = 1
                repeatStart = index + 1
            }
            index += 1
        }
        return order
    }

    /// What the judge expects from one track: struck notes only (ties sound on, dead notes click).
    func expectedNotes(track: Int) -> [ExpectedNote] {
        notes.filter { $0.track == track && !$0.isTie && !$0.isDead }.map { ExpectedNote(id: $0.id, time: $0.start, pitch: $0.pitch, part: "string \($0.string)") }
    }

    /// Index of the measure playing at a time.
    func measureIndex(at time: TimeInterval) -> Int {
        max(0, measures.partitionPoint { $0.start > time } - 1)
    }
}

nonisolated extension RandomAccessCollection {
    /// First index where `predicate` holds, for a collection that's false then true (binary search).
    func partitionPoint(where predicate: (Element) -> Bool) -> Index {
        var low = startIndex
        var count = self.count
        while count > 0 {
            let half = count / 2
            let mid = index(low, offsetBy: half)
            if predicate(self[mid]) { count = half } else { low = index(after: mid); count -= half + 1 }
        }
        return low
    }
}
