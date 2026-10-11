import Foundation
import Testing
import PitchKit
@testable import guitar

struct ChordVerifierTests {
    let c = ChordLibrary.voicing(named: "C")!     // C3 E3 G3 C4 E4
    let g = ChordLibrary.voicing(named: "G")!     // G2 B2 D3 G3 B3 G4
    let e5 = ChordLibrary.voicing(named: "E5")!   // E2 B2 E3

    @Test func everyStringHeardIsClean() {
        let verdict = ChordVerifier.verdict(heard: [48, 52, 55, 60, 64], expected: c)
        #expect(verdict.outcome == .clean && verdict.missing.isEmpty && verdict.unexpected.isEmpty)
    }

    @Test func doubledNotesCountOnceButTheBassIsStrict() {
        // C4 and E4 missing, but C and E are heard an octave down: still clean.
        #expect(ChordVerifier.verdict(heard: [48, 52, 55], expected: c).outcome == .clean)
        // Only the upper octave of the bass note: the A string (5) is missing.
        let noBass = ChordVerifier.verdict(heard: [52, 55, 60, 64], expected: c)
        #expect(noBass.outcome == .partial && noBass.missing == [5])
    }

    @Test func aMutedStringIsPartialAndNamed() {
        let verdict = ChordVerifier.verdict(heard: [48, 52, 55, 64], expected: c)   // no C4 → B string
        #expect(verdict.outcome == .clean, "C4 doubles C3, so it's lenient")
        let verdictG = ChordVerifier.verdict(heard: [43, 47, 50, 55, 67], expected: g)   // no B3 (string 2)
        #expect(verdictG.outcome == .clean, "B3 doubles B2")
        let verdictE5 = ChordVerifier.verdict(heard: [40, 52], expected: e5)   // no B2 → string 5
        #expect(verdictE5.outcome == .partial && verdictE5.missing == [5])
    }

    @Test func aWrongFretIsUnexpectedAndOvertonesAreNot() {
        let verdict = ChordVerifier.verdict(heard: [48, 52, 55, 61, 64], expected: c)   // C♯4 instead of C4
        #expect(verdict.unexpected == [61])
        #expect(verdict.outcome == .clean, "C4 is doubled by C3, so the chord still counts; the wrong note is reported")
        // G4 is the octave of G3 (expected) and an overtone: not a wrong note. B5 is nowhere near a string: ignored.
        #expect(ChordVerifier.verdict(heard: [48, 52, 55, 60, 64, 67, 83], expected: c).unexpected.isEmpty)
    }

    @Test func aDifferentChordIsWrong() {
        let verdict = ChordVerifier.verdict(heard: [43, 47, 50, 55, 59, 67], expected: c)   // G strummed
        #expect(verdict.outcome == .wrong)
        #expect(ChordVerifier.verdict(heard: [], expected: c).outcome == .wrong)
    }

    @Test func counterCountsCleanChangesAndIgnoresRepeats() {
        var counter = ChordChangeCounter(first: c, second: g)
        let cPitches: Set<UInt8> = [48, 52, 55, 60, 64]
        let gPitches: Set<UInt8> = [43, 47, 50, 55, 59, 67]
        let held = counter.strum(cPitches, at: 0)
        #expect(!held.counted && held.heard == "C" && counter.changes == 0)
        #expect(counter.strum(gPitches, at: 1).counted && counter.changes == 1)
        let again = counter.strum(gPitches, at: 1.5)
        #expect(!again.counted && again.heard == "G" && counter.changes == 1)
        let flubbed = counter.strum([48, 52], at: 2)   // moving back to C, the G string didn't ring
        #expect(!flubbed.counted && flubbed.heard == nil && flubbed.verdict.outcome == .partial && flubbed.verdict.missing == [3])
        #expect(counter.strum(cPitches, at: 2.5).counted && counter.changes == 2)
        #expect(counter.strums == 5)
    }
}

/// Strums from the Karplus–Strong synth through the analyzer, as the drill hears them.
struct StrumAnalyzerTests {
    let c = ChordLibrary.voicing(named: "C")!
    let g = ChordLibrary.voicing(named: "G")!
    let profile = InputProfile.unpluggedElectric.detectorProfile(referenceA: 440)

    /// Feeds a rendering through the analyzer in microphone-sized chunks and counts the changes.
    private func listen(_ samples: [Float], synth: GuitarToneSynth, counter: inout ChordChangeCounter, chunk: Int = 512) -> [ChordChangeCounter.Feedback] {
        let analyzer = StrumAnalyzer(sampleRate: synth.sampleRate, profile: profile, sensitivity: InputProfile.unpluggedElectric.defaultSensitivity)
        analyzer.candidates = Set(counter.first.pitches() + counter.second.pitches())
        var feedback: [ChordChangeCounter.Feedback] = []
        var start = 0
        while start < samples.count {
            let end = min(start + chunk, samples.count)
            let strums = samples[start..<end].withUnsafeBufferPointer { analyzer.process($0, startTime: Double(start) / synth.sampleRate) }
            for strum in strums { feedback.append(counter.strum(strum.present, at: strum.time)) }
            start = end
        }
        return feedback
    }

    @Test func aCleanOpenCIsHeardClean() {
        let synth = GuitarToneSynth()
        let samples = synth.render(GuitarToneSynth.strum(c, at: 0.2), duration: 1.2)
        var counter = ChordChangeCounter(first: g, second: c)
        let feedback = listen(samples, synth: synth, counter: &counter)
        #expect(feedback.count == 1, "\(feedback)")
        #expect(feedback.first?.verdict.outcome == .clean, "\(String(describing: feedback.first))")
        #expect(counter.changes == 1)
        #expect(abs((feedback.first?.verdict.time ?? 0) - 0.2) < 0.05, "\(feedback.first?.verdict.time ?? 0)")
    }

    @Test func aMutedStringShowsUpAsMissing() {
        let synth = GuitarToneSynth()
        let e5 = ChordLibrary.voicing(named: "E5")!   // E2 B2 E3: B2 is the only note of its class
        let samples = synth.render(GuitarToneSynth.strum(e5, at: 0.2, muted: [5]), duration: 1.2)
        var counter = ChordChangeCounter(first: c, second: e5)
        let feedback = listen(samples, synth: synth, counter: &counter)
        #expect(feedback.count == 1, "\(feedback)")
        #expect(feedback.first?.verdict.missing == [5], "\(String(describing: feedback.first))")
        #expect(counter.changes == 0)
    }

    @Test func aWrongFretIsReported() {
        let synth = GuitarToneSynth()
        // D with the high E string at fret 3 (G4) instead of fret 2 (F♯4).
        var wrong = ChordLibrary.voicing(named: "D")!
        wrong.frets[5] = 3
        let samples = synth.render(GuitarToneSynth.strum(wrong, at: 0.2), duration: 1.2)
        var counter = ChordChangeCounter(first: c, second: ChordLibrary.voicing(named: "D")!)
        let feedback = listen(samples, synth: synth, counter: &counter)
        #expect(feedback.count == 1, "\(feedback)")
        #expect(feedback.first?.verdict.missing.contains(1) == true, "\(String(describing: feedback.first))")
        #expect(feedback.first?.verdict.unexpected == [67], "\(String(describing: feedback.first))")
    }

    @Test func alternatingStrumsCountChangesAndRepeatsDoNot() {
        var synth = GuitarToneSynth()
        synth.inharmonicity = 0.1
        // Hold C, change to G (strummed twice), back to C. Each chord is damped when the hand moves.
        let plucks = GuitarToneSynth.strum(c, at: 0.2, release: 1.1)
            + GuitarToneSynth.strum(g, at: 1.2, release: 2.1)
            + GuitarToneSynth.strum(g, at: 2.2, release: 3.1)
            + GuitarToneSynth.strum(c, at: 3.2)
        let samples = synth.render(plucks, duration: 4.4)
        var counter = ChordChangeCounter(first: c, second: g)
        let feedback = listen(samples, synth: synth, counter: &counter, chunk: 4800)
        #expect(feedback.count == 4, "\(feedback.map(\.verdict))")
        #expect(feedback.map(\.counted) == [false, true, false, true], "\(feedback)")
        #expect(feedback.map(\.heard) == ["C", "G", "G", "C"])
        #expect(counter.changes == 2)
    }

    @Test func aQuietUnpluggedStrumIsStillHeard() {
        var synth = GuitarToneSynth()
        synth.noise = 0.00005
        let plucks = GuitarToneSynth.strum(g, at: 0.2).map { var p = $0; p.amplitude = 0.006; return p }   // ~ −45 dBFS
        let samples = synth.render(plucks, duration: 1.2)
        var counter = ChordChangeCounter(first: c, second: g)
        let feedback = listen(samples, synth: synth, counter: &counter)
        #expect(feedback.first?.verdict.outcome == .clean, "\(feedback)")
    }

    @Test func stiffStringsStillReadInTune() {
        var synth = GuitarToneSynth()
        synth.inharmonicity = 0.1
        let target = PitchMath.frequency(of: 45)
        let samples = synth.render([.init(frequency: target, start: 0.1)], duration: 0.8)
        let detector = NoteDetector(sampleRate: synth.sampleRate, profile: .guitar())
        var cents: [Double] = []
        var start = 0
        while start < samples.count {
            let end = min(start + 1024, samples.count)
            _ = detector.process(Array(samples[start..<end]))
            if let pitch = detector.latestPitch, Double(end) / synth.sampleRate > 0.25 { cents.append(PitchMath.cents(from: target, to: pitch.frequency)) }
            start = end
        }
        #expect(cents.count > 10)
        #expect(abs(cents.sorted()[cents.count / 2]) < 5, "\(cents.sorted()[cents.count / 2]) cents")
    }

    @Test func aReleasedStringDies() {
        let synth = GuitarToneSynth()
        let samples = synth.render([.init(frequency: 110, start: 0.1, release: 0.5)], duration: 1.0)
        func rms(_ range: Range<Int>) -> Float { (samples[range].reduce(0) { $0 + $1 * $1 } / Float(range.count)).squareRoot() }
        let ringing = rms(Int(0.4 * synth.sampleRate)..<Int(0.5 * synth.sampleRate))
        let damped = rms(Int(0.6 * synth.sampleRate)..<Int(0.7 * synth.sampleRate))
        #expect(damped < ringing * 0.05, "ringing \(ringing), damped \(damped)")
    }
}
