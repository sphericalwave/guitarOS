import Testing
@testable import guitar

struct TuningTests {
    @Test func standardTuningPitches() {
        let t = Tuning.standard
        #expect(t.openPitch(string: 6) == 40)   // E2
        #expect(t.openPitch(string: 1) == 64)   // E4
        #expect(t.pitch(string: 3, fret: 9) == 64)  // G string fret 9 is E4
        #expect(t.description == "E2 A2 D3 G3 B3 E4")
    }

    @Test func descriptionRoundTrips() {
        for preset in Tuning.presets {
            #expect(Tuning(description: preset.description)?.openPitches == preset.openPitches, Comment(rawValue: preset.name))
            #expect(Tuning.named(description: preset.description)?.name == preset.name)
        }
    }

    @Test func parsesAsciiAndUnicodeAccidentals() {
        #expect(Tuning(description: "Eb2 Ab2 Db3 Gb3 Bb3 Eb4")?.openPitches == Tuning.halfStepDown.openPitches)
        #expect(Tuning(description: "D♯2 G♯2 C♯3 F♯3 A♯3 D♯4")?.openPitches == Tuning.halfStepDown.openPitches)
        #expect(Tuning(description: "E2 A2 nope") == nil)
        #expect(Tuning(description: "E2 A2") == nil)
    }
}
