import AVFoundation
import Foundation

/// A short labelled recording of a strum, made in the app, for tuning chord detection against real guitars.
/// The audio is exactly what the detector heard; the label says what was played and how it reached the mic.
nonisolated struct TestClip: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Voicing name from the library, e.g. "C" or "G (barre)".
    var chord: String
    /// Free text: "Strat", "Taylor acoustic".
    var guitar: String
    /// `InputProfile` raw value: how the guitar reached the mic.
    var input: String
    var recordedAt: Date
    var duration: TimeInterval
    var sampleRate: Double
    var referenceA: Double
    /// `Tuning.description`.
    var tuning: String

    var audioFileName: String { "\(id.uuidString).caf" }
    var metadataFileName: String { "\(id.uuidString).json" }
}

/// Keeps clips as a CAF next to a JSON label in Application Support. Nothing syncs: these are hand-overs.
nonisolated struct TestClipStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "TestClips", directoryHint: .isDirectory)
    }

    func audioURL(for clip: TestClip) -> URL { directory.appending(path: clip.audioFileName) }
    func metadataURL(for clip: TestClip) -> URL { directory.appending(path: clip.metadataFileName) }

    /// Newest first.
    func clips() -> [TestClip] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { name in (try? Data(contentsOf: directory.appending(path: name))).flatMap { try? decoder.decode(TestClip.self, from: $0) } }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func save(_ clip: TestClip) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(clip).write(to: metadataURL(for: clip), options: .atomic)
    }

    func delete(_ clip: TestClip) throws {
        for url in [audioURL(for: clip), metadataURL(for: clip)] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Opens the clip's audio file for writing in the input's format. The directory is created if needed.
    func makeAudioFile(for clip: TestClip, format: AVAudioFormat) throws -> AVAudioFile {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try AVAudioFile(forWriting: audioURL(for: clip), settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }
}

/// Writes the hub's input buffers to a file until told to stop, off the main thread.
nonisolated final class ClipRecorder: @unchecked Sendable {
    private let store: TestClipStore
    private let clip: TestClip
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0
    private var isStopped = false
    private(set) var error: Error?

    init(store: TestClipStore, clip: TestClip) {
        self.store = store
        self.clip = clip
    }

    /// Seconds written so far.
    var duration: TimeInterval {
        lock.withLock { file.map { Double(framesWritten) / $0.processingFormat.sampleRate } ?? 0 }
    }

    func handle(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        lock.withLock {
            guard !isStopped, error == nil else { return }
            do {
                if file == nil { file = try store.makeAudioFile(for: clip, format: buffer.format) }
                try file?.write(from: buffer)
                framesWritten += AVAudioFramePosition(buffer.frameLength)
            } catch {
                self.error = error
            }
        }
    }

    /// Closes the file; returns how long the clip is.
    func stop() -> TimeInterval {
        lock.withLock {
            isStopped = true
            let seconds = file.map { Double(framesWritten) / $0.processingFormat.sampleRate } ?? 0
            file = nil
            return seconds
        }
    }
}
