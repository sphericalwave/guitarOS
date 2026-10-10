import SwiftUI

/// The tuner's readout and controls. Platform views decide how it's presented (sheet, window, tab).
struct TunerPanel: View {
    @Bindable var model: TunerViewModel
    @AppStorage(SettingsKey.tuning) private var tuningText = Tuning.standard.description
    @AppStorage(SettingsKey.referenceA) private var referenceA = ReferencePitch.standard
    @AppStorage(SettingsKey.referenceChoice) private var referenceChoice = TunerViewModel.Reference.standard.rawValue
    @AppStorage(SettingsKey.lastCustomA) private var lastCustomA = 442.0
    @AppStorage(SettingsKey.inputProfile) private var inputProfileRaw = InputProfile.unpluggedElectric.rawValue
    @AppStorage(SettingsKey.inputMonitoring) private var inputMonitoring = false
    @State private var customText = ""
    @State private var showCustom = false
    @FocusState private var customFocused: Bool

    private var tuning: Tuning { Tuning.named(description: tuningText) ?? .standard }
    private var reference: TunerViewModel.Reference { TunerViewModel.Reference(rawValue: referenceChoice) ?? .standard }

    var body: some View {
        VStack(spacing: 20) {
            readout
            PitchNeedle(cents: model.reading?.cents, isInTune: model.reading?.isInTune ?? false)
                .padding(.horizontal)
            strings
            status
            Divider()
            referenceControls
            inputControls
        }
        .padding()
        .onAppear {
            model.tuning = tuning
            model.audio.referenceA = referenceA
            model.audio.inputProfile = InputProfile(rawValue: inputProfileRaw) ?? .unpluggedElectric
            model.audio.monitorInput = inputMonitoring
            model.start()
        }
        .onDisappear { model.stop() }
        .onChange(of: tuningText) { model.tuning = tuning }
        .onChange(of: referenceA) { model.audio.referenceA = referenceA }
        .onChange(of: inputProfileRaw) { model.audio.inputProfile = InputProfile(rawValue: inputProfileRaw) ?? .unpluggedElectric }
        .onChange(of: inputMonitoring) { model.audio.monitorInput = inputMonitoring }
    }

    private var readout: some View {
        VStack(spacing: 4) {
            Text(model.reading?.noteName ?? "—")
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.reading?.isInTune == true ? Color.green : Color.primary)
                .contentTransition(.numericText())
                .frame(height: 100)
            Text(model.reading.map { "\($0.cents >= 0 ? "+" : "")\(Int($0.cents.rounded())) cents" } ?? "Play a string")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("A = \(referenceA.formatted(.number.precision(.fractionLength(0...1)))) Hz · \(tuning.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Which open string the reading is nearest.
    private var strings: some View {
        HStack(spacing: 14) {
            ForEach((1...tuning.stringCount).reversed(), id: \.self) { string in
                let isCurrent = model.reading?.string == string
                Text(Tuning.standard.stringCount == tuning.stringCount ? tuning.openPitches[tuning.stringCount - string].noteLetterName : "\(string)")
                    .font(.headline.monospaced())
                    .frame(width: 40, height: 40)
                    .background(isCurrent ? (model.reading?.isInTune == true ? Color.green : Color.accentColor) : Color.secondary.opacity(0.15), in: Circle())
                    .foregroundStyle(isCurrent ? .white : .primary)
            }
        }
        .accessibilityLabel("Strings")
    }

    @ViewBuilder
    private var status: some View {
        VStack(spacing: 8) {
            LevelMeter(level: model.audio.level).padding(.horizontal, 40)
            switch model.audio.status {
            case .denied:
                Label("Microphone access is off.", systemImage: "mic.slash")
                if let url = model.audio.privacySettingsURL {
                    Link("Open Settings", destination: url).buttonStyle(.borderedProminent)
                }
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                Button("Try again") { model.audio.retry() }.buttonStyle(.bordered)
            case .starting:
                ProgressView()
            case .off:
                EmptyView()
            case .listening:
                if model.cannotHear {
                    VStack(spacing: 4) {
                        Label("Can't hear the guitar", systemImage: "ear.trianglebadge.exclamationmark")
                        Text((InputProfile(rawValue: inputProfileRaw) ?? .unpluggedElectric).hint)
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
        }
        .font(.callout)
    }

    private var referenceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Reference", selection: Binding(
                get: { reference },
                set: { choice in
                    referenceChoice = choice.rawValue
                    switch choice {
                    case .standard: referenceA = ReferencePitch.standard
                    case .alternate: referenceA = ReferencePitch.alternate
                    case .custom: referenceA = lastCustomA; showCustom = true
                    }
                }
            )) {
                ForEach(TunerViewModel.Reference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if reference == .custom || showCustom {
                HStack {
                    Text("Custom A")
                    TextField(lastCustomA.formatted(.number.precision(.fractionLength(0...1))), text: $customText)
                        .focused($customFocused)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(commitCustom)
                        .onChange(of: customFocused) { if !customFocused { commitCustom() } }
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("Hz").foregroundStyle(.secondary)
                }
            }

            Picker("Tuning", selection: $tuningText) {
                ForEach(Tuning.presets, id: \.description) { Text($0.name).tag($0.description) }
            }
        }
    }

    /// Empty field means "keep the last custom A", so the placeholder is the value in force.
    private func commitCustom() {
        let trimmed = customText.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            lastCustomA = ReferencePitch.clamped(value)
        }
        customText = ""
        referenceChoice = TunerViewModel.Reference.custom.rawValue
        referenceA = lastCustomA
    }

    @ViewBuilder
    private var inputControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Input", selection: $inputProfileRaw) {
                ForEach(InputProfile.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            if model.audio.canSelectInputs, model.audio.inputs.count > 1 {
                Picker("Device", selection: Binding(
                    get: { model.audio.currentInput?.id ?? "" },
                    set: { id in if let input = model.audio.inputs.first(where: { $0.id == id }) { model.audio.select(input) } }
                )) {
                    ForEach(model.audio.inputs) { Text($0.name).tag($0.id) }
                }
            } else if let input = model.audio.currentInput {
                Text(input.name).font(.footnote).foregroundStyle(.secondary)
            }
            if model.audio.canMonitorInput {
                Toggle("Hear my guitar (monitoring)", isOn: $inputMonitoring)
            }
        }
    }
}

private extension UInt8 {
    /// "E", "A", ... for the string buttons.
    var noteLetterName: String {
        ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][Int(self) % 12]
    }
}
