import Testing
import PitchKit
@testable import guitar

struct TunerModelTests {
    @Test func picksTheNearestStringAndMeasuresCents() {
        let reading = TunerModel.reading(frequency: 112, tuning: .standard, referenceA: 440)   // A2 is 110 Hz
        #expect(reading.string == 5)
        #expect(reading.noteName == "A2")
        #expect(abs(reading.cents - 31.2) < 0.5)
        #expect(!reading.isInTune)
        #expect(TunerModel.reading(frequency: 110.1, tuning: .standard, referenceA: 440).isInTune)
    }

    @Test func aStringTunedTo432ReadsFlatAt440AndInTuneAt432() {
        let a432 = 432.0 / 4   // A2 on a guitar tuned to A432
        let at440 = TunerModel.reading(frequency: a432, tuning: .standard, referenceA: 440)
        let at432 = TunerModel.reading(frequency: a432, tuning: .standard, referenceA: 432)
        #expect(at440.string == 5 && abs(at440.cents + 31.8) < 0.1)
        #expect(at432.string == 5 && abs(at432.cents) < 0.01 && at432.isInTune)
    }

    @Test func followsTheChosenTuning() {
        // Low D (73.4 Hz) is the 6th string in drop D, but closer to E2's string in standard.
        let d = PitchMath.frequency(of: 38)
        #expect(TunerModel.reading(frequency: d, tuning: .dropD, referenceA: 440).isInTune)
        #expect(TunerModel.reading(frequency: d, tuning: .standard, referenceA: 440).string == 6)
        #expect(!TunerModel.reading(frequency: d, tuning: .standard, referenceA: 440).isInTune)
    }

    @Test func medianSmoothingIgnoresOneBadHop() {
        #expect(TunerModel.smoothed([110, 110.2, 220, 109.9, 110.1]) == 110.1)
        #expect(TunerModel.smoothed([]) == nil)
    }

    @Test func customReferenceIsClamped() {
        #expect(ReferencePitch.clamped(400) == 415)
        #expect(ReferencePitch.clamped(480) == 466)
        #expect(ReferencePitch.clamped(442) == 442)
    }
}

/// The detector against Karplus–Strong strings, which sound more like a guitar than stacked sines.
struct GuitarDetectionTests {
    /// Open strings and the 24th fret, ±3 cents.
    @Test(arguments: [40, 45, 50, 55, 59, 64, 76, 88])
    func readsPluckedStringsWithinThreeCents(note: Int) {
        let synth = GuitarToneSynth()
        let target = PitchMath.frequency(of: note)
        let samples = synth.render([.init(frequency: target, start: 0.1)], duration: 0.8)
        let detector = NoteDetector(sampleRate: synth.sampleRate, profile: .guitar())
        var cents: [Double] = []
        var start = 0
        while start < samples.count {
            let end = min(start + 1024, samples.count)
            _ = detector.process(Array(samples[start..<end]))
            if let pitch = detector.latestPitch, Double(end) / synth.sampleRate > 0.25 {
                cents.append(PitchMath.cents(from: target, to: pitch.frequency))
            }
            start = end
        }
        #expect(cents.count > 10, "no readings for \(note)")
        let median = cents.sorted()[cents.count / 2]
        #expect(abs(median) < 3, "note \(note): \(Int(median)) cents")
    }

    @Test func hearsTheNoteOnFromAPluck() {
        let synth = GuitarToneSynth()
        let samples = synth.render([.init(frequency: PitchMath.frequency(of: 55), start: 0.2)], duration: 1.0)
        let detector = NoteDetector(sampleRate: synth.sampleRate, profile: .guitar(gateDecibels: -75))
        var onsets: [UInt8] = []
        var start = 0
        while start < samples.count {
            let end = min(start + 1024, samples.count)
            for event in detector.process(Array(samples[start..<end])) {
                if case let .noteOn(pitch, _) = event { onsets.append(pitch) }
            }
            start = end
        }
        // The pluck's noise burst can read as overtones for a frame or two; the string itself must follow.
        // (Drills grade on the YIN pitch, not note-ons, until the chord verifier lands in M6.)
        #expect(onsets.contains(55), "\(onsets)")
    }

    @Test func aQuietUnpluggedElectricPassesTheLowerGate() {
        var synth = GuitarToneSynth()
        synth.noise = 0.00005
        let quiet = synth.render([.init(frequency: PitchMath.frequency(of: 45), start: 0.1, amplitude: 0.004)], duration: 0.6)  // ~ −50 dBFS
        let detector = NoteDetector(sampleRate: synth.sampleRate, profile: InputProfile.unpluggedElectric.detectorProfile(referenceA: 440))
        var heard = false
        var start = 0
        while start < quiet.count {
            let end = min(start + 1024, quiet.count)
            _ = detector.process(Array(quiet[start..<end]))
            if detector.latestPitch != nil { heard = true }
            start = end
        }
        #expect(heard)
    }
}
