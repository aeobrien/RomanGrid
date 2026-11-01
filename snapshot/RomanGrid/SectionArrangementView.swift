import SwiftUI
import SwiftData

struct SectionArrangementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var song: Song
    @State private var draggedSection: SectionInstance? = nil
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(song.arrangement, id: \.id) { section in
                    SectionRow(section: section, song: song)
                        .onDrag {
                            draggedSection = section
                            return NSItemProvider(object: section.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: SectionDropDelegate(
                            destinationSection: section,
                            song: song,
                            draggedSection: $draggedSection
                        ))
                }
                .onMove { source, destination in
                    song.arrangement.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { indexSet in
                    song.arrangement.remove(atOffsets: indexSet)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Arrange Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SectionRow: View {
    let section: SectionInstance
    let song: Song
    
    var blueprint: SectionBlueprint? {
        if !section.isLinked, let ownBlueprint = section.ownBlueprint {
            return ownBlueprint
        }
        return song.blueprints.first { $0.id == section.blueprintID }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(section.displayName)
                        .font(.headline)
                    
                    if let bp = blueprint, bp.name.contains("(Custom)") {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                if let bp = blueprint {
                    HStack(spacing: 8) {
                        Label("\(bp.bars) bars", systemImage: "music.note")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• \(bp.resolution.label)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let lyricsData = section.lyricsData, !lyricsData.lines.isEmpty {
                    Label("\(lyricsData.lines.count) lyric lines", systemImage: "text.alignleft")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .imageScale(.large)
        }
        .padding(.vertical, 4)
    }
}

struct SectionDropDelegate: DropDelegate {
    let destinationSection: SectionInstance
    let song: Song
    @Binding var draggedSection: SectionInstance?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedSection = draggedSection else { return false }
        
        guard let sourceIndex = song.arrangement.firstIndex(where: { $0.id == draggedSection.id }),
              let destinationIndex = song.arrangement.firstIndex(where: { $0.id == destinationSection.id }) else {
            return false
        }
        
        withAnimation {
            song.arrangement.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
        
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Optional: Add visual feedback when hovering
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}