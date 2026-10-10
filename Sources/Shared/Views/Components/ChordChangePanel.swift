import SwiftUI
import SwCharts

/// Two chord grids, a one-minute timer, and one giant tap target to count changes.
struct ChordChangePanel: View {
    @Bindable var model: ChordChangeViewModel
    var leftHanded: Bool
    @Bindable var metronome: MetronomeViewModel
    @AppStorage(SettingsKey.chordChartPeriod) private var period: ChartPeriod = .week
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
            chord(model.first, isCurrent: model.phase == .running && model.showingFirst)
            Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
            chord(model.second, isCurrent: model.phase == .running && !model.showingFirst)
        }
        .frame(maxHeight: 190)
        .contentShape(Rectangle())
        .onTapGesture { if model.phase == .ready { showPicker = true } }
    }

    private func chord(_ voicing: ChordVoicing, isCurrent: Bool) -> some View {
        VStack {
            Text(voicing.name).font(.title2.bold())
            ChordGridView(voicing: voicing, leftHanded: leftHanded)
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
            trend
        }
    }

    private var running: some View {
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
