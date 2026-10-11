import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SongListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Song.title)]) private var songs: [Song]
    
    @State private var exporting: Song?
    @State private var exportDoc: ExportFile? = nil
    @State private var presentExporter = false
    @State private var presentImporter = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(songs) { song in
                    NavigationLink {
                        SongEditorView(song: song)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(song.title).font(.headline)
                            HStack {
                                Text(song.artist).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(song.keySig.tonic.name(preferSharps: song.keySig.preferSharps)) • \(song.keySig.mode.rawValue)")
                                    .foregroundStyle(.secondary)
                            }.font(.subheadline)
                        }
                    }
                    .contextMenu {
                        Button("Export JSON") { prepareExport(song) }
                        Button("Duplicate") { duplicate(song) }
                        Button(role: .destructive, action: { context.delete(song) }) { Text("Delete") }
                    }
                }
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Import") { presentImporter = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { addSong() }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileExporter(isPresented: $presentExporter, document: exportDoc, contentType: .json, defaultFilename: "Song.json") { _ in
                exportDoc = nil
            }
            .fileImporter(isPresented: $presentImporter, allowedContentTypes: [.json]) { res in
                if case .success(let url) = res, let data = try? Data(contentsOf: url) {
                    if let bundle = try? JSONDecoder().decode(ExportSong.self, from: data) {
                        _ = bundle.importInto(context)
                    }
                }
            }
        }
    }
    
    private func addSong() {
        let s = Song()
        context.insert(s)
    }
    private func duplicate(_ song: Song) {
        let data = try! JSONEncoder().encode(song.toExportBundle())
        let imported = try! JSONDecoder().decode(ExportSong.self, from: data)
        _ = imported.importInto(context)
    }
    private func prepareExport(_ song: Song) {
        let data = try! JSONEncoder().encode(song.toExportBundle())
        exportDoc = ExportFile(data: data)
        presentExporter = true
    }
}
