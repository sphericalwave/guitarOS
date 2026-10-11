import AVFoundation
import Foundation
import Testing
@testable import guitar

struct TestClipStoreTests {
    private func temporaryStore() -> TestClipStore {
        TestClipStore(directory: FileManager.default.temporaryDirectory.appending(path: "guitar-clips-\(UUID().uuidString)"))
    }

    @Test func savesListsAndDeletesLabelledClips() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.clips().isEmpty)

        let older = TestClip(id: UUID(), chord: "C", guitar: "Strat", input: InputProfile.unpluggedElectric.rawValue, recordedAt: .now.addingTimeInterval(-60),
                             duration: 2.5, sampleRate: 48_000, referenceA: 440, tuning: Tuning.standard.description)
        let newer = TestClip(id: UUID(), chord: "G", guitar: "Strat", input: InputProfile.di.rawValue, recordedAt: .now,
                             duration: 3, sampleRate: 48_000, referenceA: 432, tuning: Tuning.dropD.description)
        try store.save(older)
        try store.save(newer)

        let listed = store.clips()
        #expect(listed.map(\.chord) == ["G", "C"], "newest first")
        #expect(listed.first?.referenceA == 432 && listed.first?.tuning == "D2 A2 D3 G3 B3 E4")

        try store.delete(older)
        #expect(store.clips().map(\.id) == [newer.id])
        #expect(!FileManager.default.fileExists(atPath: store.metadataURL(for: older).path))
    }

    @Test func recorderWritesTheBuffersItIsGiven() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let clip = TestClip(id: UUID(), chord: "E", guitar: "", input: InputProfile.di.rawValue, recordedAt: .now,
                            duration: 0, sampleRate: 0, referenceA: 440, tuning: Tuning.standard.description)
        let recorder = ClipRecorder(store: store, clip: clip)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        for _ in 0..<5 { recorder.handle(buffer, AVAudioTime(hostTime: 0)) }

        #expect(abs(recorder.duration - 0.5) < 1e-6)
        #expect(abs(recorder.stop() - 0.5) < 1e-6)
        #expect(recorder.error == nil)
        let written = try AVAudioFile(forReading: store.audioURL(for: clip))
        #expect(written.length == 24_000)
    }
}
