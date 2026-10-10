# guitar

Guitar practice app: tuner (440/432 Hz), fretboard note trainer, metronome, chord changes, practice
log with streaks and D/W/M charts. iOS 26 + macOS 26, SwiftData synced via CloudKit
(`iCloud.com.sphericalwave.music.guitar`). Plan: `docs/PLAN.md`.

Project is generated: edit `project.yml`, then `xcodegen generate`.

Layout: `Sources/Shared` (models, engine, view models, shared components), `Sources/iOS` and
`Sources/macOS` (navigation + platform screens, filtered per destination), `Tests/guitarTests`
(Swift Testing).

Packages (all remote, github.com/sphericalwave, branch main): DiagnosticsKit, ScrollKit, SwCharts, MusicTheoryKit, PitchKit. Push a package change before building guitar against it.

The 2022 prototype is tagged `prototype-2022`; its uncommitted WIP is the stash
`guitar-prototype-2022-wip` (see `docs/PLAN.md` M0).
