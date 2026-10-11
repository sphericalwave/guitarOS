import AVFoundation
import Observation
import DiagnosticsKit

/// Plays a `TabTimeline` through General MIDI samplers (the bundled GeneralUser GS bank), one per track.
/// `AVAudioSequencer` schedules the notes sample-accurately on its own thread; its position is the one clock
/// the tab strip and the judge read, so sound and picture can't drift apart. Output only: the mic stays with
/// `AudioHub`.
@Observable
@MainActor
final class SongPlayer {
    private(set) var isPlaying = false
    /// Where playback sits while paused; observable so paused views redraw after a seek.
    private(set) var restingPosition: TimeInterval = 0
    /// Speed, 0.25...1. Pitch doesn't change.
    var rate: Double = 1 { didSet { sequencer.rate = Float(rate) } }
    /// Tracks that don't sound (the player plays them).
    var mutedTracks: Set<Int> = [] { didSet { applyMutes() } }
    var isCountInOn = true { didSet { applyMutes() } }
    /// Song-time section that repeats while playing.
    var loop: ClosedRange<TimeInterval>?
    /// Called about every 10 ms while playing, with the song position: the practice session's heartbeat.
    @ObservationIgnored var onTick: ((TimeInterval) -> Void)?
    /// Called each time the A–B loop starts over.
    @ObservationIgnored var onLoop: (() -> Void)?

    let duration: TimeInterval
    /// Seconds of count-in before song time 0 (one bar at the opening tempo).
    let leadIn: TimeInterval
    var startPosition: TimeInterval { -leadIn }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var samplers: [AVAudioUnitSampler] = []
    @ObservationIgnored private let click = AVAudioUnitSampler()
    @ObservationIgnored private let sequencer: AVAudioSequencer
    @ObservationIgnored private var tracks: [AVMusicTrack] = []
    @ObservationIgnored private var countInTrack: AVMusicTrack?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?

    /// The sequencer runs at 60 BPM, so a beat is a second and the timeline's seconds schedule directly.
    private static let secondsPerBeat = 1.0

    init(timeline: TabTimeline, score: TabScore) throws {
        duration = timeline.duration
        let first = timeline.measures.first
        leadIn = first.map { Double($0.numerator) * 60 / Double(max($0.tempo, 1)) * 4 / Double(max($0.denominator, 1)) } ?? 2

        // The graph has to be wired before the sequencer is made, or it has no output node to play into.
        for track in score.tracks {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            Self.load(sampler, program: track.program, isPercussion: track.isPercussion)
            sampler.masterGain = Self.gain(for: track.volume)
            samplers.append(sampler)
        }
        engine.attach(click)
        engine.connect(click, to: engine.mainMixerNode, format: nil)
        Self.load(click, program: 0, isPercussion: true)
        engine.prepare()
        sequencer = AVAudioSequencer(audioEngine: engine)
        try engine.start()

        buildSequence(timeline: timeline, score: score)
        seek(to: startPosition)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    /// Song time in seconds; negative during the count-in.
    func position() -> TimeInterval {
        isPlaying ? sequencer.currentPositionInSeconds - leadIn : restingPosition
    }

    /// Song time at an earlier host-clock moment (a note-on's strike time), from where playback is now.
    func position(atHostTime hostTime: TimeInterval) -> TimeInterval {
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        return position() - (now - hostTime) * rate
    }

    func play() throws {
        guard !isPlaying else { return }
        if position() >= duration { seek(to: startPosition) }
        if !engine.isRunning { try engine.start() }
        try sequencer.start()
        isPlaying = true
        startMonitor()
    }

    func pause() {
        guard isPlaying else { return }
        let current = position()
        sequencer.stop()
        silence()
        monitor?.cancel()
        isPlaying = false
        restingPosition = current
    }

    func seek(to time: TimeInterval) {
        sequencer.currentPositionInSeconds = max(0, time + leadIn)
        silence()
        restingPosition = time
    }

    /// Stops audio and releases the engine. Call when leaving the song screen.
    func shutdown() {
        pause()
        engine.stop()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
    }

    // MARK: Private

    private func buildSequence(timeline: TabTimeline, score: TabScore) {
        sequencer.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: 60), at: 0)
        for (index, sampler) in samplers.enumerated() {
            let track = sequencer.createAndAppendTrack()
            track.destinationAudioUnit = sampler
            tracks.append(track)
            for note in timeline.notes where note.track == index && !note.isDead && !note.isTie {
                let event = AVMIDINoteEvent(channel: 0, key: UInt32(note.pitch), velocity: UInt32(max(1, note.velocity)), duration: max(0.05, note.duration * 0.95))
                track.addEvent(event, at: note.start + leadIn)
            }
        }
        let countIn = sequencer.createAndAppendTrack()
        countIn.destinationAudioUnit = click
        if let first = timeline.measures.first {
            let beat = leadIn / Double(max(first.numerator, 1))
            for index in 0..<max(first.numerator, 1) {
                countIn.addEvent(AVMIDINoteEvent(channel: 0, key: index == 0 ? 76 : 77, velocity: index == 0 ? 110 : 80, duration: 0.1), at: Double(index) * beat)
            }
        }
        countInTrack = countIn
        sequencer.rate = Float(rate)
        applyMutes()
        sequencer.prepareToPlay()
    }

    private func applyMutes() {
        for (index, track) in tracks.enumerated() { track.isMuted = mutedTracks.contains(index) }
        countInTrack?.isMuted = !isCountInOn
        silence()
    }

    /// Releases every key so a seek, pause, or mute never leaves notes hanging.
    private func silence() {
        for sampler in samplers + [click] {
            for key: UInt8 in 0...127 { sampler.stopNote(key, onChannel: 0) }
        }
    }

    /// Loops the A–B section and stops shortly after the last note.
    private func startMonitor() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = position()
                if let loop, now >= loop.upperBound {
                    seek(to: loop.lowerBound)
                    onLoop?()
                } else if loop == nil, now >= duration + 1 {
                    pause()
                    return
                } else {
                    onTick?(now)
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// Output device changed (headphones, AirPlay): the engine stops, so pause cleanly and restart it.
    private func handleConfigurationChange() {
        pause()
        try? engine.start()
        sequencer.prepareToPlay()
    }

    /// The bundled GeneralUser GS bank (General MIDI); the sampler's default tone if it's missing.
    private static func load(_ sampler: AVAudioUnitSampler, program: Int, isPercussion: Bool) {
        guard let url = Bundle.main.url(forResource: "GeneralUser-GS", withExtension: "sf2") else {
            ErrorLog.shared.warning("SongPlayer", "GeneralUser-GS.sf2 is missing from the bundle")
            return
        }
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: UInt8(clamping: isPercussion ? 0 : program),
                bankMSB: UInt8(isPercussion ? kAUSampler_DefaultPercussionBankMSB : kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
            ErrorLog.shared.warning("SongPlayer", "Couldn't load program \(program)", error: error)
        }
    }

    /// MIDI channel volume (0–127) as sampler gain in dB.
    private static func gain(for volume: UInt8) -> Float {
        let share = max(Double(volume), 1) / 127
        return Float(20 * log10(share))
    }
}
