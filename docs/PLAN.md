# guitar — practice app plan

Status: planning only. No app code yet. Written 2026-10-08 after reading this repo, the sibling
piano app (`../piano`, incl. `feat/mic-note-detection`), `~/Documents/apps/Frameworks`, and the
strike/shodan flashcard apps.

---

## 0. What exists today

- Xcode 14-era project (`GuitarOS.xcodeproj`, 2022), iOS-only, iOS 16.1, Swift 5, portrait locked
  (good — keep that).
- `GridView` (a `Path` grid with a row of tappable dots), `Note` (a circle view), `Coordinate`.
  Prototype-grade; nothing worth carrying forward except the idea of a vertical fretboard grid.
- App icon (PRS headstock), launch storyboard, `assets/guitarOS.sketch`, `icon/prsHeadstock.svg`.
- **Uncommitted WIP in the main checkout** (`GridView`, `Note`, `Coordinate`, `project.pbxproj`,
  untracked `icon/`). This plan doesn't touch it. Commit or discard it before M0, since M0 replaces
  the project.

**Decision:** start over on a modern project (M0) and keep the icon and splash assets.
Don't try to upgrade the 2022 project.

---

## 1. Target user and core practice loop

**User:** the owner, an intermediate guitarist who already plays well but wants fluency: knowing
every note on the neck, scales/modes/CAGED without thinking, cleaner and faster chord changes,
better time, and a better ear. The user doesn't read standard notation (see piano CLAUDE.md), so
tab, fretboard diagrams and chord grids are the notation. Practice happens with the phone on a
music stand or the Mac on a desk, guitar in hand. **Hands are busy**, which drives most UX choices.

**Core loop (one session ≈ 15–30 min):**

1. Open the app → **Today** shows one button: *Start today's practice (20 min)*.
2. The app builds the routine from what's due: a tuning check → due fretboard cards → the weakest
   chord change → one scale/CAGED position at a target BPM → (later) ear and song blocks.
3. Each block listens through the mic and grades itself. No tapping "correct/incorrect" with a
   pick in your hand.
4. End screen: what improved (best change speed, new cards mastered, BPM gained), streak, and
   what's due tomorrow.
5. Progress tab: calendar heatmap, minutes per week, per-skill trends.

The differentiator: **auto-graded spaced repetition for motor skills.** Each fret position, chord
change, scale shape and interval is a card. The mic measures correctness plus response time, and
that becomes the SM-2 quality grade. You practise what you're slow at, not what you like.

---

## 2. Feature set, ranked

| Rank | Feature | Input | Notes |
|---|---|---|---|
| **MVP** | Tuner | mic (mono) | Needle + cents, auto string detect, alternate tunings, **reference pitch 440 / 432 Hz** (+ custom A). Also the mic health check. |
| **MVP** | Fretboard note trainer | mic + tap | "Play F♯ on the G string" (mic) / "Name this dot" (tap, silent mode). SR per position. |
| **MVP** | Practice log, Today, streaks, charts | — | Sessions → blocks; SwCharts heatmap + period bars. |
| **MVP** | Metronome | output | Sample-accurate click engine. The same clock later judges rhythm. |
| **MVP** | Chord library (small) + one-minute changes, self-counted | tap | ~40 voicings (open, E/A-shape barres, power). User counts changes; best-per-pair tracked. |
| 2 | Chord-change trainer, auto-detected | mic (score-informed) | Strum onset + verify the expected voicing → clean changes/min. |
| 3 | Scales / modes / CAGED | mic (mono sequence) | Generated positions; play-along at BPM with auto speed-up after clean passes. |
| 4 | Rhythm trainer | mic onsets | Strum/pick on the click; early/late histogram (SwCharts `NormalDistributionChart`). |
| 5 | Ear training | tap + mic | Intervals, chord quality, scale degree in key, **play-back-what-you-hear** (mic). |
| 6 | Tab / song play-along | mic (mono + score-informed) | **Guitar Pro** import: `.gp5` first (the user's existing files), then `.gp` (GP7/8). Wait mode + play-along. MIDI import optional, later. |
| 7 | Theory flashcards | tap | Generated from the theory engine ("3rd of D major?", "notes of A Dorian?"). |
| 8 | MIDI guitar input | CoreMIDI | Per-string channels (Fishman TriplePlay, Jamstik) give the string; optional. |
| parked | Lesson scrolls | — | strike/ScrollKit pattern for guitar course videos. Parked 2026-10-09: no source material yet. |

Explicitly **not** planned: lessons/curriculum content, social, a backing-track library, AI chord
transcription of arbitrary recordings, landscape.

---

## 3. Input approach

### 3.1 Signal path
- One shared `AVAudioEngine` for mic in + click/reference tones out, so only one audio session
  ever exists.
- iOS session: `.playAndRecord`, mode `.measurement` (no AGC/voice processing), `.defaultToSpeaker`,
  `.allowBluetoothA2DP`, 5 ms IO buffer. Copy piano's `AudioRecordingSession` adapter as-is.
- **Two supported inputs, both first-class** (the user's main guitar is an electric, usually
  unplugged, with a small USB interface on hand):
  1. **Built-in mic, unplugged electric (default).** An unplugged electric is quiet: ~20–30 dB
     below an acoustic. The `unpluggedElectric` input profile defaults to higher sensitivity and a
     lower silence gate (piano's −65 dBFS gate is too high). First-run tip: "Put the phone/Mac within
     an arm's length of the strings." The tuner's level meter is the check.
  2. **USB interface (DI).** Picked automatically when plugged in (route-change notification via
     DiagnosticsKit's `AudioSessionMonitor`), switchable in the input picker. Clean signal, no
     speaker bleed, so it's the best mode for song play-along with backing. **Input monitoring**
     toggle (on by default with a DI input and headphones): with no amp, you hear nothing unless the
     app passes the guitar through. Off when the route is the built-in speaker, to avoid feedback.
- Show the active input and its level everywhere listening happens.
- Bluetooth output adds 150–250 ms. Compensate using `outputLatency` and warn on BT routes. Offer a
  tap-along latency calibration once (Settings).

### 3.2 Single notes (tuner, fretboard, scales, ear play-back): YIN
- Piano's `YINPitchDetector` + `OnsetDetector` + `NoteTracker` carry over directly.
- Guitar range: fundamentals ~55 Hz (drop tunings, 7-string B1 = 61.7 Hz) to ~1.4 kHz (24th fret
  E6). That allows a **much shorter window than piano** (piano must reach A0 = 27.5 Hz): ~2048
  samples at 48 kHz, so ~30–45 ms detection latency vs piano's ~64 ms. The guitar profile sets
  `minFrequency: 55, maxFrequency: 1500`.
- The tuner uses a longer window and median smoothing for cent stability. Latency matters less there.
- **Limit (stated in UI copy):** pitch doesn't identify the string. E4 is open high E, B-string
  fret 5 and G-string fret 9. The trainer prompts for an exact pitch and trusts that it was played on
  the asked string. String identification from timbre is research-grade. MIDI guitar solves it.

### 3.3 Chords: score-informed verification, not transcription
Blind polyphonic transcription of a strummed guitar is unreliable. **The app always knows which
voicing it asked for**, so it verifies instead of transcribing:

- After a strum onset, take frames ~60–180 ms post-onset (past the pick noise, before decay).
- For each expected string note, compute harmonic salience (the template approach from piano's
  `PolyphonicNoteEstimator`, retuned: guitar inharmonicity is low, 12 partials is enough, range
  E2–E6).
- Per-string verdict: **present / weak (muted, buzzing) / missing**, plus "strong unexpected note"
  for a wrong fret. Octave-doubled notes (C3 + C4 in open C) are inherently ambiguous, so verify
  pitch classes plus the bass note strictly and treat octave doublings leniently.
- Output: a `ChordVerdict` (clean / partial with string list / wrong / no strum). The UI lights the
  failing string on the chord grid. That's useful feedback, not just pass/fail.
- New type `ChordVerifier`. It uses piano's `Prior.expected` idea but scores only the template set,
  which is cheaper and more robust than a full search.
- The app's own sound (click, reference tones, backing) goes into `Prior.suppressed`, as piano
  already does.

### 3.4 Rhythm
Strum and pick timing come from `OnsetDetector` alone, no pitch needed. Mic timestamps map to host
time, then to beat time on the click clock, with detector latency subtracted (piano's
`MicrophoneCapture.latency`).

### 3.5 MIDI guitar (later, optional)
Reuse piano's `MIDIInputClient`. Its `MIDIWordDecoder` currently drops channel and pitch bend.
Guitar needs both: channel = string in per-string mode, bend = bends. Extend the decoder rather than
fork it.

### 3.6 Test fixtures
Mirror piano's `PianoToneSynth` with a **Karplus–Strong `GuitarToneSynth`** (single notes, strums
with per-string delays, muted strings) so detection is unit-tested without audio files. Add ~20 short
real recordings later for regression. None for now (2026-10-09): MVP relies on synth fixtures plus
the user's own on-device testing. Real clips become a gate before M6 (see M6).

---

## 4. Data model (SwiftData, CloudKit-safe)

Rules (same as piano): every stored property optional or defaulted, no `@Attribute(.unique)`, every
relationship optional with an inverse, blobs `@Attribute(.externalStorage)`. **No "wipe the store on
load failure" recovery, ever** (see global CLAUDE.md §7). On load failure, show an error and keep
the file.

Static content (scales, modes, CAGED shapes, chord voicings, tunings) is **code/bundled JSON, not
SwiftData**. Only user state syncs.

```swift
@Model final class PracticeSession {          // one sitting
    var startedAt: Date = Date.now
    var duration: TimeInterval = 0
    var goalMinutes: Int = 20                 // snapshot, so old days chart correctly
    @Relationship(deleteRule: .cascade, inverse: \PracticeBlock.session)
    var blocks: [PracticeBlock]? = []
}

@Model final class PracticeBlock {            // one drill within a sitting
    var kind: String = ""                     // DrillKind raw: tuner, fretboard, chordChange, scale, rhythm, ear, song
    var title: String = ""                    // "C → G", "A minor pent, pos 1"
    var duration: TimeInterval = 0
    var attempts: Int = 0
    var correct: Int = 0
    var bpm: Int?                             // when a click was running
    var score: Double?                        // kind-specific: changes/min, timing σ ms, accuracy
    var session: PracticeSession?
    var song: Song?
}

@Model final class SkillCard: SpacedRepetitionCard {   // ScrollKit SM-2
    var kind: String = ""                     // fretPosition, chordShape, chordChange, scaleShape, interval, theory
    var key: String = ""                      // stable id: "fret:std:s3f7", "change:C-open>G-open"
    var attempts: Int = 0
    var correct: Int = 0
    var meanResponse: Double = 0              // seconds, rolling
    var best: Double?                         // e.g. best changes/min, best BPM
    var lastPracticed: Date?
    var srInterval: Int = 1
    var srEasinessFactor: Double = 2.5
    var srRepetitions: Int = 0
    var srDueDate: Date = Date.now
}

@Model final class Song {                     // M9
    var title: String = ""
    var artist: String = ""
    @Attribute(.externalStorage) var sourceData: Data?
    var sourceFormat: String = ""             // gp5, gp, (gpx, midi later)
    var tuning: String = "E2 A2 D3 G3 B3 E4"  // string, not Codable struct — sync-safe
    var capo: Int = 0
    var lastPosition: TimeInterval = 0
    var bestAccuracy: Double?
    @Relationship(deleteRule: .nullify, inverse: \PracticeBlock.song)
    var blocks: [PracticeBlock]? = []
}
```

- **Streaks and daily totals are computed from sessions, never stored.** Stored counters conflict
  across devices.
- **Cards are created lazily** the first time a key is practised, not seeded 78 at a time. That cuts
  CloudKit duplicates when two devices start fresh. A launch-time dedupe pass merges same-`key` cards
  (keep max repetitions, sum attempts, earliest due).
- Auto-grade → SM-2 quality: wrong = 1; right in > 5 s = 3; < 5 s = 4; < 2 s = 5 (thresholds per
  kind, tuned in M3).
- The guitar's settings (tuning, reference A) are mirrored to `NSUbiquitousKeyValueStore`, so the
  Mac and phone agree about the guitar. Everything else is per-device.
- Settings live in `@AppStorage`: tuning, reference A (440 default; 432 preset; custom 415–466), left-handed flip, sharps/flats,
  daily goal minutes, fret range, input sensitivity, last BPM.
- **Data survival:** every model is new, so nothing migrates in v1. Each later addition must be an
  optional/defaulted property → lightweight migration. State this in each schema-changing PR.

---

## 5. Architecture

Follow global CLAUDE.md and copy **strike's XcodeGen layout** (it already does the
Shared/iOS/macOS split with `destinationFilters`).

```
guitar/
  project.yml                      # XcodeGen; iOS 26 + macOS 26, Swift 6, MainActor default isolation
  Sources/
    Shared/
      App/GuitarApp.swift          # composition roots call into platform wiring
      Models/                      # SwiftData models above
      Engine/                      # pure, nonisolated, unit-tested — no SwiftUI
        Fretboard/                 # Tuning, FretPosition, Fretboard (pitch↔positions), FretboardLayout
        Chords/                    # ChordVoicing, ChordLibrary (bundled), ChordVerifier
        Scales/                    # ScaleShape, CAGED, positions generator
        Practice/                  # DrillPrompt generators, AutoGrade, RoutineBuilder, RhythmJudge
        Audio/                     # ClickTrack, GuitarToneSynth (Karplus–Strong), GuitarPitchProfile
      ViewModels/                  # TodayViewModel, TunerViewModel, FretboardDrillViewModel, ...
      Services/                    # AudioHub (one engine), InputMonitor, CardStore (lazy create + dedupe)
      PlatformAdapters/            # AudioRecordingSession, KeepAwake, Haptics?, FileImporting
      Views/Components/            # FretboardView, ChordGridView, PitchNeedle, LevelMeter (identical on both)
    iOS/
      App/RootView.swift           # TabView, @AppStorage("guitarSelectedTab")
      Views/<Feature>/<Feature>View.swift
      PlatformAdapters/            # AudioRecordingSession+iOS (copy from piano), KeepAwake+iOS (idleTimer)
    macOS/
      App/RootView.swift           # NavigationSplitView sidebar
      Views/<Feature>/<Feature>View.swift
      PlatformAdapters/
  Tests/                           # Swift Testing
```

- **Concurrency:** like piano, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Audio and DSP types are
  `nonisolated`. Analysis runs on the capture thread (piano's `MicrophoneCapture` sink-node + ring
  buffer design) and publishes `AsyncStream<PitchUpdate>`.
- **ViewModels** take adapters by init injection (`AudioRecordingSession`, `KeepAwake`). Each
  platform's `App` file wires the concrete ones. No UIKit/AppKit in `Shared/`.
- `Haptics` exists only on iOS → `Haptics?` optional, nil on macOS.
- Each feature is scaffolded as three files: `Shared/ViewModels/XViewModel.swift`,
  `iOS/Views/X/XView.swift`, `macOS/Views/X/XView.swift`.
- Rendering: `Canvas` + `TimelineView`, with a pure `…Layout` struct that is unit-tested. That's
  piano's `KeyboardLayout`/`StaffStripLayout` pattern.
- Bundle id `com.sphericalwave.music.guitar`. Packages: DiagnosticsKit (remote), ScrollKit,
  SwCharts, plus the new ones below (local path during development, like strike).

---

## 6. Reuse: extract vs copy vs use

### Use as-is
| Package | For |
|---|---|
| **DiagnosticsKit** | Error log + `AudioSessionMonitor` (route changes when an interface is plugged in). Suite standard. |
| **ScrollKit** | `SM2` + `SpacedRepetitionCard` for `SkillCard`. Later `ScrollManifest`/`Cloze` if lesson scrolls happen. |
| **SwCharts** (was ChartKit) | Follow the house **D/W/M standard** (`period-charts` skill): `PeriodChartView` + `PeriodPicker` in the principal toolbar, per-screen `@AppStorage("<screen>ChartPeriod")`. Metrics: practice minutes (`.sum`), changes/min and BPM (`.average`). Plus `CalendarHeatmap` (streak) and `NormalDistributionChart` (timing offsets). The daily practice goal uses `PeriodGoal` (goal scaled per period for `.sum`, hit/miss tint), alongside the Today ring. |
| **SwDesignSystem** | Selectively: `SwTheme`, toasts/`Popup`, `CircularProgressView` (goal ring). Several files are UIKit-only behind `canImport`; check each component on macOS before using it. |

### Extract into new shared packages (piano and guitar both depend on them)
| New package | Contents (from piano) | When |
|---|---|---|
| `Frameworks/Music/MusicTheoryKit` | `PitchName`, `SpelledPitch`, `NoteLetter`/`Accidental`, `PitchSpelling`, `KeyDescription`, `Chord` (its doc comment already says "as a guitarist reads it"), `ChordAnalysis`, `RomanNumeral`. Add `Interval`, `Scale`, `Mode` here (new, written for guitar, useful for piano). | **M1.** Stable, pure, on piano `main`. |
| `Frameworks/Audio/PitchKit` | `SpectrumAnalyzer`, `YINPitchDetector`, `OnsetDetector`, `NoteTracker`, `PolyphonicNoteEstimator` (parameterised by an `InstrumentProfile`: range, inharmonicity, partial count; piano and guitar profiles), `MicrophoneCapture`, `Prior`, `AudioRecordingSession` protocol + iOS/macOS impls. | **M2, after piano merges `feat/mic-note-detection`.** Switch piano to the package in the same change. `PreciseTempermentKit` also has its own YIN + SpectrumAnalyzer copy, so dedupe it onto PitchKit later. Guitar uses only plain 12-TET at a chosen A (440/432), so it doesn't depend on PreciseTempermentKit. |
| `Frameworks/Music/PlayAlongKit` | `PlayAlongJudge`, `WaitGate`, `WaitRunner`, `InputMerger`, `NoteEvent` (was `KeyboardEvent`), `ListeningPrior`. Generalise from `Score` + `Hand` to `[ExpectedEvent]` (id, time, pitches, part), so guitar strings/parts and piano hands both fit. | **M7** (first guitar use: scale play-along). Not earlier, because the right generalisation shows up with the second user. |
| MIDI file + CoreMIDI (`MIDIFile`, `TempoMap`, `Score+MIDI`, `MIDIInputClient`, `MIDIWordDecoder`) | Optional MIDI song import + MIDI guitar input. | **M10/M11, only if MIDI import is wanted.** Defer. Name it `ScoreKit` (avoid clashing with the open-source "MIDIKit"). |

### Copy the pattern, not the code
- **`AutoFingering`** is piano-specific (finger spans). Guitar Pro files already carry string and
  fret, so **no tab assigner is needed for songs**. Only if MIDI import is added later: a
  `GuitarTabAssigner` using the same DP/Viterbi approach (costs for fret distance, position shifts,
  open strings, chord span ≤ 4–5 frets), tested against known tabs the way piano tests fingerings.
- **`FallingNotesView` / `StaffStripView`** are piano-keyboard and grand-staff specific. Write
  `TabStripView`: 6 lines, fret numbers, playhead, same `TimelineView`+`Canvas`+tested layout
  struct design. Chord names above it via `ChordAnalysis` spans, as the staff strip does.
- **`PracticeLog`/`Song`** model shapes → adapted above.
- **`PlaybackEngine` metronome/count-in** → piano schedules clicks through an
  `AVAudioUnitSampler` sequence. Guitar has no song for M5, so write a standalone `ClickTrack`
  (`AVAudioSourceNode`, sample-accurate against a host-time anchor). It's simple and exposes
  beat↔host-time for judging. Piano can adopt it later.
- **strike's `ReviewQueueViewModel`** (fixed queue, grades, forecast) → template for
  `FretboardDrillViewModel`'s queue. Grading comes from audio, not buttons.

---

## 7. UX flows (per the UX laws in global CLAUDE.md)

**Navigation (iOS):** 4 tabs, `@AppStorage("guitarSelectedTab")`, portrait only.
**Today · Practice · Progress · Tools.** Songs is added as a tab only at M10 (Hick's law: no empty
tabs). macOS uses a sidebar with the same sections; tuner and metronome open in a utility window.

**Tuner is one tap from anywhere** (toolbar tuning-fork button). Guitarists retune mid-session
(Jakob, Fitts).

### Today (primary flow)
- One dominant button, *Start today's practice*, with the routine preview below it (4–5 rows with
  minutes) and a goal ring (Von Restorff, Hick, sensible default 20 min).
- Each row can be swapped or skipped from a context menu (defaults are easy to change).
- In-session: a progress bar across blocks ("Block 2 of 4 · 6 min left"). Every block saves when it
  finishes, so a phone call doesn't lose the session, and Today offers *Resume* (Zeigarnik,
  goal-gradient, errors recoverable).
- **End screen:** highlight + totals + streak + "Tomorrow: 12 cards, C→G change" (peak-end). Never
  end on a blank list.

### Fretboard trainer
- Vertical fretboard (headstock up) fills the lower half in portrait. The existing GridView's
  instinct was right. Prompt in huge type above: **"F♯ — G string"**.
- Live detected note + level meter appear within ~50 ms of playing (Doherty). Green flash +
  haptic on correct; on wrong, show what was heard and where it lives on the asked string. Then
  move on: no extra tap needed (Parkinson).
- Silent mode (tap the 12 note names, big buttons in a 4×3 grid) for when you can't play aloud.
  Mode toggle in the toolbar; it remembers the last mode.
- Scope picker (strings, fret range, naturals only) sits behind a "Customize" disclosure. The
  default is "due cards" (Tesler, progressive disclosure).

### Chord changes
- Two chord grids side by side, a big **Start 1:00** button, metronome optional.
- v1: one giant tap target fills the screen to count changes (tap with the strumming hand's knuckle
  between strums). v2 (M6): auto-count, and the failing string flashes on the grid.
- Result: "34 changes/min · best 31 → **new best**".

### Tuner
- Needle + cents + note, auto string detection, big "in tune" state. Tuning picker shows the
  standard default first.
- **Reference pitch control on the tuner screen itself:** a segmented `440 | 432` (440 default,
  remembers your last choice) and a "Custom A…" field behind disclosure, using the last-value
  placeholder rule. The current reference is always shown in small type under the note
  ("A = 432 Hz"), so it's never a hidden mode.
- **The reference is app-wide, not tuner-only.** A guitar tuned to A432 sits ~32 cents flat of
  A440. That's close to the detector's ±35-cent tolerance, so every drill would judge it wrong. The
  chosen A goes into `InstrumentProfile.guitar` (PitchKit's `a4` parameter, which piano's
  `PolyphonicNoteEstimator` already takes), into note naming/cents everywhere, and into reference
  tones. Changing it mid-session asks "Retune now?" and opens the tuner.
- Doubles as the **mic check**: if level stays near silence for 3 s, show "Can't hear the guitar →
  pick input / check permission" with the fix button inline (errors explained, recoverable).

### Metronome
- BPM field follows the last-entered-value placeholder rule (empty field, grey last BPM, empty means
  reuse it). Tap tempo, ± buttons, accent pattern behind disclosure.

### Permissions
- Ask for the mic on first use of a mic drill, never at launch, after one sentence on why. If denied,
  every mic drill offers its tap-mode equivalent plus a Settings link (`privacySettingsURL`, as piano
  does).

### Left-handed
- One setting mirrors every fretboard and chord grid. Default comes from the first-run question
  "Which hand frets?" (one question, prefilled right).

---

## 8. Milestones

Each milestone builds on iOS **and** macOS with tests passing before the next starts (piano's rule).
The user builds and runs. Agents run tests only when asked.

### MVP (M0–M5)

**M0: Project reset** — done 2026-10-09 (PR #1 `m0-project-reset`)
- [x] WIP stashed (user chose stash over commit): `git stash` entry `guitar-prototype-2022-wip`,
      SHA `1d2397d6078bebfb41a3da8c02577959389b9fd5`, includes `icon/prsHeadstock.svg`. Restore with
      `git stash apply 1d2397d` (never pop). Tag `prototype-2022` = e9fb801.
- [x] Name is **guitar** (suite lowercase): `guitar.xcodeproj`, target/scheme `guitar`, display
      name "guitar", `GuitarApp` entry point. `GuitarOS.xcodeproj` + `GuitarOS/` deleted; the icon and
      launch assets moved to `Resources/Assets.xcassets`. The GitHub repo stays `guitarOS`.
- [x] XcodeGen `project.yml` (strike pattern): iOS 26 + macOS 26, Swift 6, MainActor default
      isolation, portrait-only (iOS), bundle id `com.sphericalwave.music.guitar`, CloudKit
      container + iCloud entitlements on both iOS and macOS, remote-notification + audio background
      modes, mic usage string, macOS sandbox + audio-input entitlement (two entitlements files, per SDK).
- [x] AppIcon carried over (1024 iOS + mac ladder via `sips`), LaunchLogo from `assets/prs.png`,
      white `LaunchBackground`, `UILaunchScreen` dict (no storyboard).
- [x] `Shared/iOS/macOS` skeleton, `AppSection`, RootView per platform (`@AppStorage("guitarSelectedTab")`
      / `guitarSidebarPane`), DiagnosticsKit `DiagnosticsView` under Tools.
- [x] Swift Testing smoke test (`AppSectionTests`).
- Gate used: `xcodebuild -scheme guitar -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test` and a
  `generic/platform=iOS` compile. No simulator or device. Signing + the iCloud container get provisioned
  the first time the user builds in Xcode.
- Worktree note: local packages are `../../Frameworks/...`; inside `.claude/worktrees/<x>` that resolves
  to `.claude/Frameworks`, which is a symlink to `~/Documents/apps/Frameworks` (untracked).

**M1: Theory + fretboard core (pure)** — done 2026-10-09 (PR #2 `m1-theory-fretboard`)
- [x] `MusicTheoryKit` extracted (`Frameworks/Music/MusicTheoryKit`, github.com/sphericalwave/MusicTheoryKit,
      private); piano switched in piano PR #7. **Note:** piano's `Chord`/`ChordAnalysis`/`RomanNumeral` were
      uncommitted staff-strip WIP in the main checkout, not on main, so the package carries *copies* and piano
      keeps its own until that work lands (then delete piano's and import).
- [x] `Interval`, `Scale`, `Mode` (+ tests) in MusicTheoryKit. `PitchName` gained flat spelling.
- [x] `Tuning` (standard, drop D, half-step down, DADGAD, open G/D; custom via "E2 A2 D3 G3 B3 E4" text),
      `FretPosition` (key "s3f7"), `Fretboard.positions(of:)`, `pitch(at:)`, `allPositions` with scope.
- [x] `FretboardLayout` (blended real/even fret spacing, left-handed mirror, hit testing) + tests;
      `FretboardView` (Canvas) shared component; reference fretboard in the Practice tab for now.

**M2: Listening + tuner** — done 2026-10-09 (PR #3 `m2-listening-tuner`)
- [x] `PitchKit` extracted from piano@efbc1d8 (`Frameworks/Audio/PitchKit`, github.com/sphericalwave/PitchKit,
      private): `InstrumentProfile` (`.piano()`, `.guitar(a4:gateDecibels:)`), `NoteDetector` (was
      `PianoNoteDetector`, emits `NoteEvent`, exposes `latestPitch` every hop), `MicrophoneCapture` (+ optional
      input monitoring), `AudioRecordingSession`. piano #6 (finer hop, vDSP, expected-note confirm, strike
      timestamps) ported in PitchKit PR #1 (2026-10-09). **piano is NOT switched yet**; do it as a separate piano PR.
- [x] **All guitar packages are remote** (github.com/sphericalwave/*.git, branch main) per the user, 2026-10-09.
      SwCharts is `SwCharts.git` (repo renamed from ChartKit). Push a package before building guitar against a change.
- [x] `AudioHub` (one engine, acquire/release, permission flow, level, pitch, note events, rebuilds on
      settings change or route change), `AudioInputSelecting` adapter (iOS: session inputs + speaker check;
      macOS: system input only, no monitoring), level meter.
- [x] `InputProfile` `.unpluggedElectric` (gate −75 dBFS, sensitivity 0.7) / `.di` (−60, 0.5); untested on
      the real guitar — **the user must try the tuner unplugged and tune the gate/sensitivity**.
- [x] `GuitarToneSynth` (Karplus–Strong) test fixture; YIN reads E2–E6 plucks within 3 cents; A432 string
      reads −31.8 cents at 440 and in tune at 432 (PitchKit + guitar tests).
- [x] Tuner on both platforms (iOS sheet from the toolbar tuning fork on every tab + Tools; macOS utility
      window ⌘T + Tools): note, cents, needle, string dots, 440 | 432 | Custom (last-value placeholder,
      415–466), tuning picker, input picker, monitoring toggle (only off-speaker), "Can't hear the guitar"
      after 3 s, permission/Settings link, retry. Reference A applies app-wide via `AudioHub.referenceA`.
- [x] `CloudSettings` mirrors tuning + reference A through `NSUbiquitousKeyValueStore`.
- Known: on the Karplus–Strong attack the polyphonic path can emit an overtone note-on before the real
  note (noise burst looks like harmonics). Drills grade on the YIN pitch (`AudioHub.pitch`) until the chord
  verifier (M6) tunes the template path for guitar. "Retune now?" prompt on A change not built yet.

**M3: Fretboard note trainer** — done 2026-10-09 (PR #4 `m3-fretboard-trainer`)
- [x] `SkillCard` (SwiftData, CloudKit-safe, no relationships) + `ModelContainer` in `GuitarApp` (CloudKit
      automatic, local fallback, **never wipes the store**); `CardStore` (lazy create, `dedupe()` at launch via
      `CardMerge`, `record` → SM-2 via ScrollKit); `AutoGrade` (wrong 1; right <2 s 5, <5 s 4, else 3; per-kind
      thresholds). Data survival: new model, nothing to migrate.
- [x] Drills: **Play it** (mic: "F♯ / G string", judged on the YIN pitch held for 3 readings, exact pitch, string
      trusted, reference A honoured) and **Name it** (tap, 4×3 note grid, pitch class). Due cards first, then
      unseen positions; mode remembered; scope (naturals, frets, strings) behind Customize; wrong answers show
      the heard note on the asked string; auto-advance. Mic denied → Settings link + switch to Name it.
- [x] Mastery heatmap on the Practice home fretboard (`MasteryMap`: accuracy × schedule; orange = due).
- [x] Fix: `com.apple.developer.ubiquity-kvstore-identifier` entitlement (KVS logged "BUG IN CLIENT" without it).
- [x] PitchKit: piano #6 ported (PitchKit PR #1); `AudioHub.onEvent` now carries strike times.
- Not yet: first-run "Which hand frets?" question (left-handed is a toggle in the Practice reference view's menu
  → move to Settings in M4); the plan's per-kind SM-2 thresholds still need tuning on the real guitar.

**M4: Log, Today, Progress**
- [ ] `PracticeSession`/`PracticeBlock`; block-level autosave + resume.
- [ ] `RoutineBuilder` (due cards first, goal minutes); Today screen; end-of-session screen.
- [ ] Progress: SwCharts heatmap + D/W/M practice-minutes `PeriodChartView`, streak (computed).
- [ ] CloudKit check: a session logged on iPhone shows up on the Mac (and back); dedupe test.

**M5: Metronome + self-counted chord changes**
- [ ] `ClickTrack` (sample-accurate, tap tempo, accents) + Metronome tool.
- [ ] `ChordLibrary` (~40 bundled voicings) + `ChordGridView`.
- [ ] One-minute changes with tap counter; `chordChange` cards with `best`; trend chart.

**MVP done:** a daily routine of tuner check → fretboard cards → chord change, logged with a streak,
on iPhone and Mac.

### After MVP
- **M6: Auto chord-change detection.** `ChordVerifier` (score-informed), strum onsets, per-string
  feedback; synthetic strum tests. **Gate:** needs ~20 real clips (unplugged + USB) before it
  replaces self-counting. The user doesn't have them yet; ask again when M5 ships.
- **M7: Scales/modes/CAGED.** Shape generator, `PlayAlongKit` extraction, wait mode + timed mode,
  speed trainer (+N BPM per clean pass), `scaleShape` cards.
- **M8: Rhythm trainer.** Onset vs click, timing histogram, subdivision drills.
- **M9: Ear training.** Intervals, chord quality, functional scale degrees, mic play-back
  (Karplus–Strong reference tones; sampler later).
- **M10: Songs (Guitar Pro).** Moved up to right after M7: songs are a stronger motivator than
  rhythm/ear drills, and the scale play-along engine (M7) is most of the work. Order becomes
  M6 → M7 → **M10** → M8 → M9.
  - **`.gp5` parser first.** There are 7 `.gp5` files on this Mac and no `.gp`/`.gpx`. It's a
    documented little-endian binary format. Read PyGuitarPro / TuxGuitar (LGPL) and alphaTab
    (MPL-2.0) for the format only, and don't copy code (piano's rule for reference apps). Pure Swift
    in `Shared/Engine/GuitarPro/` until a second app needs it.
  - v1 scope: tracks + string tunings + capo, measures, time/key signatures, tempo changes,
    repeats, beats/rests/durations/dots/tuplets/ties, notes (string, fret). Effects (bends, slides,
    hammer-ons, palm mute) are parsed and shown as markers but not judged.
  - `TabScore` model → `[ExpectedEvent]` for `PlayAlongKit` (wait mode + play-along); track picker
    (which track is "you"); `TabStripView`; loop A–B + slow-down; count-in from `ClickTrack`.
  - **Backing playback is in scope (user wants it).** Your track muted by default (toggle "play my
    part"); every other track plays through `AVAudioUnitSampler` loaded with a bundled General MIDI
    SF2 bank, GM programs per track from the GP file, drums on channel 10. Candidate banks:
    **GeneralUser GS** (~30 MB SF2, permissive licence) or FluidR3_GM (MIT, ~140 MB, too big).
    Confirm the licence and record it in README like piano's CC0 piano. `AVAudioUnitSampler` takes
    SF2/DLS, not SF3. Per-track mute/solo/volume, tempo scale without pitch change, same clock as
    the judge (piano's single-clock rule).
  - Tests: build `.gp5` byte fixtures in test code (piano's MIDI fixture pattern). The 7 real files
    are copyrighted tabs, so they're used for a manual local smoke test only, never committed.
  - Then `.gp` (GP7/8: zip + `score.gpif` XML). `.gpx` (GP6) and MIDI import only if needed.
- **M11: Extras.** MIDI guitar, theory flashcards. (Lesson scrolls parked.)

---

## 9. Risks

- **Mic accuracy with an unplugged electric** (quiet strings, fan noise). Mitigations: the
  `unpluggedElectric` profile, keeping the device close, the USB interface, and a tap-mode fallback
  in every drill. M2 must be tested against the user's actual guitar unplugged, not just synth
  fixtures.
- **Backing tracks vs the built-in mic.** Speaker backing will drown an unplugged electric even with
  `Prior.suppressed`. With mic input + speaker, song play-along defaults to wait mode (backing pauses
  while it listens) and suggests headphones or the USB interface. With DI input there's no bleed, so
  everything is allowed.
- **CloudKit sync iPhone ↔ Mac** is a must-have: verify sessions, cards and song files appear on the
  other device in M4 (and M10 for songs), on real devices with the same iCloud account.
- **Chord verification false negatives** frustrate fast. Ship M5 self-counted first, and only
  replace it when M6 beats the user's own count on recorded tests.
- **Extraction coupling with piano:** PitchKit extraction waits for the piano branch to merge. If it
  stalls, guitar copies the files with a `// copied from piano@<sha>` header and extracts later.
- **CloudKit duplicate cards** → lazy creation + dedupe pass (M3), with a test.

---

## 10. Open questions

Answered 2026-10-08:
- **Songs come from Guitar Pro** → M10, `.gp5` first.
- **The tuner gets a 432 Hz option** → M2, applied app-wide. Plain 12-TET at A = 432, not Precise
  Temperament.
- **Main guitar is an electric, mostly unplugged; a small USB interface is available** → built-in
  mic is the default input, and the USB interface is fully supported with input monitoring (§3.1).
- **macOS is a real v1 target** → every MVP milestone ships on iPhone and Mac.
- **CloudKit sync is required** → entitlements in M0, cross-device check in M4/M10.
- **Backing playback for Guitar Pro songs: yes** → GM SF2 sampler in M10.
- 2026-10-09: **no real test clips and no course videos for now** → synth fixtures for MVP, real
  clips gate M6; lesson scrolls parked.
- 2026-10-09: **name is "guitar"** for now (M0).

1. Deployment target iOS/macOS 26 (matches piano; PitchKit's `Synchronization` needs 18+) OK?
