import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import DiagnosticsKit

/// Songs section: the imported Guitar Pro tabs, an Import button, and the song screen.
struct SongsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Song.importedAt, order: .reverse) private var songs: [Song]
    @State private var showImporter = false
    @State private var importError: String?

    private static let gp5 = UTType(exportedAs: "com.sphericalwave.music.guitar.gp5", conformingTo: .data)

    var body: some View {
        List {
            if songs.isEmpty {
                ContentUnavailableView {
                    Label("No songs yet", systemImage: "music.quarternote.3")
                } description: {
                    Text("Import a Guitar Pro 5 (.gp5) tab. The band plays, you play your track.")
                } actions: {
                    Button("Import a tab…") { showImporter = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(songs) { song in
                NavigationLink {
                    SongPlayAlongView(song: song)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.headline)
                            Text(song.artist.isEmpty ? "Guitar Pro" : song.artist).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let best = song.bestAccuracy { Text("\(Int((best * 100).rounded()))%").foregroundStyle(.secondary) }
                    }
                }
                .contextMenu { Button("Delete", role: .destructive) { context.delete(song) } }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Songs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImporter = true } label: { Label("Import…", systemImage: "square.and.arrow.down") }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [Self.gp5, .data]) { result in
            switch result {
            case .success(let url): importSong(at: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importSong(at url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            context.insert(try SongLibrary.makeSong(from: data, fileName: url.lastPathComponent))
            try context.save()
        } catch {
            ErrorLog.shared.error("Songs", "Import failed", error: error)
            importError = error.localizedDescription
        }
    }
}

/// One song in the detail pane.
struct SongPlayAlongView: View {
    @Environment(AudioHub.self) private var audio
    @Environment(\.modelContext) private var context
    let song: Song
    @State private var model: SongPlayAlongViewModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                SongPanel(model: model)
            } else if let loadError {
                ContentUnavailableView("Can't open this tab", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: 720)
        .navigationTitle(song.title)
        .task {
            guard model == nil else { return }
            do { model = SongPlayAlongViewModel(song: song, score: try SongLibrary.score(of: song), audio: audio, context: context) }
            catch { loadError = error.localizedDescription }
        }
    }
}
