import SwiftUI
import SwCharts

/// Two chord grids, a one-minute timer, and one giant tap target to count changes. With auto-count (beta)
/// the mic counts and the grid of the chord being reached lights the strings that didn't ring.
struct ChordChangePanel: View {
    @Bindable var model: ChordChangeViewModel
    var leftHanded: Bool
    @Bindable var metronome: MetronomeViewModel
    @AppStorage(SettingsKey.chordChartPeriod) private var period: ChartPeriod = .week
    @Environment(\.openURL) private var openURL
    @State private var useClick = false
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 16) {
            chords
            switch model.phase {
            case .ready: ready
            case .running: running
            case .done(let result, let isNewBest): done(result, isNewBest: isNewBest)
            }
        }
        .padding()
        .onDisappear { model.stop(); metronome.stop() }
        .sheet(isPresented: $showPicker) { ChordPairPicker(first: $model.first, second: $model.second) }
    }

    private var chords: some View {
        HStack(spacing: 24) {
            chord(model.first, isCurrent: model.phase == .running && model.showingFirst, highlight: model.showingFirst ? [] : model.highlightStrings)
            Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
            chord(model.second, isCurrent: model.phase == .running && !model.showingFirst, highlight: model.showingFirst ? model.highlightStrings : [])
        }
        .frame(maxHeight: 190)
        .contentShape(Rectangle())
        .onTapGesture { if model.phase == .ready { showPicker = true } }
    }

    private func chord(_ voicing: ChordVoicing, isCurrent: Bool, highlight: Set<Int> = []) -> some View {
        VStack {
            Text(voicing.name).font(.title2.bold())
            ChordGridView(voicing: voicing, leftHanded: leftHanded, highlightStrings: highlight)
        }
        .padding(8)
        .background(isCurrent ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
    }

    private var ready: some View {
        VStack(spacing: 12) {
            if let best = model.best { Text("Best: \(Int(best.rounded())) changes/min").foregroundStyle(.secondary) }
            Toggle("Metronome \(Int(metronome.bpm)) BPM", isOn: $useClick).toggleStyle(.switch).frame(maxWidth: 260)
            Button {
                if useClick { metronome.start() }
                model.start()
            } label: {
                Label("Start 1:00", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Change chords…") { showPicker = true }.font(.footnote)
            if model.isAuto {
                Text("Auto-count (beta): the mic counts each clean change. Tap +1 to correct it.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            trend
        }
    }

    @ViewBuilder
    private var running: some View {
        if model.isAuto, let audio = model.audio {
            autoRunning(audio)
        } else {
            tapRunning
        }
    }

    /// The mic counts: the number, what the last strum sounded like, a correction button.
    private func autoRunning(_ audio: AudioHub) -> some View {
        VStack(spacing: 8) {
            Text(Duration.seconds(model.remaining).formatted(.time(pattern: .minuteSecond))).font(.title.monospacedDigit()).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(model.changes)").font(.system(size: 96, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            feedbackLine
            Spacer(minLength: 0)
            LevelMeter(level: audio.level).padding(.horizontal, 40)
            micStatus(audio)
            HStack(spacing: 16) {
                Button { model.countChange() } label: { Text("+1").frame(minWidth: 80, minHeight: 44) }.buttonStyle(.bordered)
                Button("Stop") { model.stop(); metronome.stop() }.frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var feedbackLine: some View {
        if let feedback = model.feedback {
            if feedback.counted {
                Label(feedback.heard ?? "", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.title3.bold())
            } else if let heard = feedback.heard {
                Text("\(heard) is clean — change now").foregroundStyle(.secondary).font(.title3)
            } else if feedback.verdict.outcome == .partial {
                Text("Missing: \(ChordChangePanel.stringNames(feedback.verdict.missing))").foregroundStyle(.orange).font(.title3)
            } else {
                Text("Didn't hear \(model.showingFirst ? model.second.name : model.first.name)").foregroundStyle(.orange).font(.title3)
            }
        } else {
            Text("strum each chord").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func micStatus(_ audio: AudioHub) -> some View {
        switch audio.status {
        case .denied:
            VStack(spacing: 4) {
                Text("Microphone access is off. Tap +1 to count by hand.").font(.footnote).foregroundStyle(.secondary)
                if let url = audio.privacySettingsURL { Button("Open Settings") { openURL(url) }.font(.footnote) }
            }
        case .unavailable(let reason):
            Text(reason).font(.footnote).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    /// "B and G strings" from string numbers (1 = high E).
    static func stringNames(_ strings: [Int]) -> String {
        let names = [1: "high E", 2: "B", 3: "G", 4: "D", 5: "A", 6: "low E"]
        let listed = strings.sorted().compactMap { names[$0] }
        return listed.formatted(.list(type: .and)) + (listed.count == 1 ? " string" : " strings")
    }

    private var tapRunning: some View {
        VStack(spacing: 8) {
            Text(Duration.seconds(model.remaining).formatted(.time(pattern: .minuteSecond))).font(.title.monospacedDigit()).foregroundStyle(.secondary)
            Button {
                model.countChange()
            } label: {
                VStack {
                    Text("\(model.changes)").font(.system(size: 80, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("tap on each change").font(.footnote)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            Button("Stop") { model.stop(); metronome.stop() }.font(.footnote)
        }
    }

    private func done(_ result: ChordChangeDrill.Result, isNewBest: Bool) -> some View {
        VStack(spacing: 12) {
            Text("\(Int(result.changesPerMinute.rounded())) changes/min").font(.title.bold())
            if isNewBest { Label("New best", systemImage: "star.fill").foregroundStyle(.orange).font(.headline) }
            else if let best = model.best { Text("Best \(Int(best.rounded()))").foregroundStyle(.secondary) }
            Button("Again") { metronome.stop(); model.reset() }.buttonStyle(.borderedProminent).controlSize(.large)
            trend
        }
        .onAppear { metronome.stop() }
    }

    /// Changes/min for this pair over time: an `.average` metric, read as a slope.
    private var trend: some View {
        let samples = model.history().map { DatedSample(date: $0.date, value: $0.changesPerMinute) }
        return Group {
            if samples.count >= 2 {
                PeriodChartView(title: "\(model.title) changes/min", samples: samples, period: period, aggregation: .average, style: .line,
                                valueLabel: { "\(Int($0))" }, height: 120)
            }
        }
    }
}

/// Pick the two chords of a change from the library, grouped by family.
struct ChordPairPicker: View {
    @Binding var first: ChordVoicing
    @Binding var second: ChordVoicing
    @Environment(\.dismiss) private var dismiss
    @State private var picking = 0

    var body: some View {
        NavigationStack {
            List {
                Picker("Which", selection: $picking) { Text(first.name).tag(0); Text(second.name).tag(1) }.pickerStyle(.segmented)
                ForEach(ChordVoicing.Family.allCases, id: \.self) { family in
                    Section(family.title) {
                        ForEach(ChordLibrary.voicings.filter { $0.family == family }) { voicing in
                            Button {
                                if picking == 0 { first = voicing } else { second = voicing }
                            } label: {
                                HStack {
                                    Text(voicing.name)
                                    Spacer()
                                    if voicing == (picking == 0 ? first : second) { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chords")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 320, minHeight: 420)
    }
}
