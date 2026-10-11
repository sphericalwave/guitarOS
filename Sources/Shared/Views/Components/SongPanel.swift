import SwiftUI

/// The song screen's body: scrolling tab, transport, mode, track and loop controls, the pass result.
/// Identical on both platforms.
struct SongPanel: View {
    @Bindable var model: SongPlayAlongViewModel
    @State private var showSetup = false
    @State private var loopStart = 1
    @State private var loopEnd = 1

    var body: some View {
        VStack(spacing: 12) {
            header
            TabStripView(timeline: model.timeline, track: model.trackIndex, stringCount: model.track.stringCount,
                         position: model.position, results: model.results, required: model.requiredPitches)
                .frame(minHeight: 160, maxHeight: 220)
            if let error = model.loadError {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
            status
            transport
            if let result = model.result { finished(result) }
            Spacer(minLength: 0)
        }
        .padding()
        .onAppear { model.prepare() }
        .onDisappear { model.close() }
        .sheet(isPresented: $showSetup) { setup }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(model.title).font(.title2.bold()).lineLimit(1)
            Text("\(model.song.artist.isEmpty ? "" : model.song.artist + " · ")\(model.track.name)" + (model.song.capo > 0 ? " · capo \(model.song.capo)" : ""))
                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            LevelMeter(level: model.audio.level).frame(width: 80)
            if model.isHolding {
                Label("Play the note", systemImage: "hand.raised.fill").foregroundStyle(.orange)
            } else if model.position < 0 {
                Text("Count-in…").foregroundStyle(.orange)
            } else if model.mode == .playAlong, model.isPlaying {
                Text("\(model.summary.hits) hit · \(model.summary.missed) missed").foregroundStyle(.secondary)
            } else {
                Text("Bar \(model.timeline.measureIndex(at: max(0, model.position)) + 1) of \(model.timeline.measures.count)").foregroundStyle(.secondary)
            }
            Spacer()
            micStatus
        }
        .font(.callout.monospacedDigit())
    }

    @ViewBuilder
    private var micStatus: some View {
        switch model.audio.status {
        case .denied:
            if let url = model.audio.privacySettingsURL { Link("Mic is off", destination: url).font(.footnote) }
        case .unavailable(let reason):
            Text(reason).font(.footnote).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { max(0, min(model.position, model.duration)) }, set: { model.seek(to: $0) }), in: 0...max(model.duration, 1))
            HStack(spacing: 18) {
                Button { model.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }.frame(minWidth: 44, minHeight: 44)
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title).frame(minWidth: 64, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                Button { showSetup = true } label: { Image(systemName: "slider.horizontal.3") }.frame(minWidth: 44, minHeight: 44)
            }
            Picker("Mode", selection: $model.mode) {
                ForEach(SongPlayAlongViewModel.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isPlaying)
        }
    }

    private func finished(_ result: SongPlayAlongViewModel.Result) -> some View {
        VStack(spacing: 4) {
            if model.mode == .playAlong {
                Text("\(Int((result.accuracy * 100).rounded()))% · \(result.hits) of \(result.hits + result.missed) notes").font(.headline)
                if let best = model.song.bestAccuracy { Text("Best \(Int((best * 100).rounded()))%").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Text("Played through in \(Duration.seconds(result.seconds).formatted(.time(pattern: .minuteSecond)))").font(.headline)
            }
        }
        .padding(.top, 4)
    }

    /// Track, speed, backing, loop: the things you set once per song.
    private var setup: some View {
        NavigationStack {
            Form {
                Section("Your track") {
                    Picker("Track", selection: Binding(get: { model.trackIndex }, set: { model.choose(track: $0) })) {
                        ForEach(model.score.guitarTracks, id: \.self) { Text(model.score.tracks[$0].name.isEmpty ? "Track \($0 + 1)" : model.score.tracks[$0].name).tag($0) }
                    }
                    Toggle("Play my part too", isOn: $model.playsMyTrack)
                    Toggle("Count-in", isOn: $model.isCountInOn)
                }
                Section("Speed") {
                    Picker("Speed", selection: $model.rate) {
                        Text("50%").tag(0.5); Text("75%").tag(0.75); Text("90%").tag(0.9); Text("100%").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Stepper("From bar \(loopStart)", value: $loopStart, in: 1...max(model.timeline.measures.count, 1))
                    Stepper("To bar \(loopEnd)", value: $loopEnd, in: loopStart...max(model.timeline.measures.count, 1))
                    HStack {
                        Button("Loop these bars") { model.loopMeasures = (loopStart - 1)...(loopEnd - 1) }
                        Spacer()
                        Button("Clear loop") { model.loopMeasures = nil }.disabled(model.loopMeasures == nil)
                    }
                } header: {
                    Text("Loop")
                } footer: {
                    Text(model.loopMeasures.map { "Looping bars \($0.lowerBound + 1)–\($0.upperBound + 1)." } ?? "Repeat a hard section while the rest of the band waits.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Song setup")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSetup = false } } }
            .onAppear {
                if let loop = model.loopMeasures { loopStart = loop.lowerBound + 1; loopEnd = loop.upperBound + 1 }
                else { loopStart = model.timeline.measureIndex(at: max(0, model.position)) + 1; loopEnd = min(loopStart + 3, max(model.timeline.measures.count, 1)) }
            }
        }
        .frame(minWidth: 360, minHeight: 440)
    }
}
