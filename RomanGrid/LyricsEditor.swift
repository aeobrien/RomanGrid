import SwiftUI
import SwiftData

struct LyricsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var instance: SectionInstance
    let blueprint: SectionBlueprint
    let song: Song
    
    @State private var lyricsLines: [LyricsLineEditor] = []
    @State private var selectedSectionType = "Verse"
    @State private var selectedBarForNewLine = 0
    @State private var selectedBeatForNewLine = 0.0
    
    let sectionTypes = ["Verse", "Chorus", "Bridge", "Pre-Chorus", "Outro", "Intro", "Custom"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Section Type") {
                    Picker("Type", selection: $selectedSectionType) {
                        ForEach(sectionTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedSectionType) { _, newValue in
                        updateDisplayName(with: newValue)
                    }
                }
                
                Section("Lyrics by Bar") {
                    ForEach(0..<blueprint.bars, id: \.self) { barIndex in
                        BarLyricsEditor(
                            barIndex: barIndex,
                            blueprint: blueprint,
                            song: song,
                            lyricsLines: bindingForBarLines(barIndex)
                        )
                    }
                }
                
                Section {
                    Button("Clear All Lyrics", role: .destructive) {
                        clearAllLyrics()
                    }
                }
            }
            .navigationTitle("Edit Lyrics: \(instance.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLyrics()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadLyrics()
        }
    }
    
    private func bindingForBarLines(_ barIndex: Int) -> Binding<[LyricsLineEditor]> {
        Binding(
            get: {
                lyricsLines.filter { $0.barIndex == barIndex }
            },
            set: { newLines in
                // Remove old lines for this bar
                lyricsLines.removeAll { $0.barIndex == barIndex }
                // Add new lines
                lyricsLines.append(contentsOf: newLines)
            }
        )
    }
    
    private func loadLyrics() {
        lyricsLines = []
        
        if let lyricsData = instance.lyricsData {
            for line in lyricsData.lines {
                lyricsLines.append(LyricsLineEditor(
                    barIndex: line.barIndex,
                    text: line.text,
                    startBeat: line.startBeat,
                    endBeat: line.endBeat,
                    isEmpty: line.isEmpty
                ))
            }
        }
        
        // Determine section type from display name
        for type in sectionTypes {
            if instance.displayName.contains(type) {
                selectedSectionType = type
                break
            }
        }
    }
    
    private func saveLyrics() {
        // Create or update lyrics data
        if instance.lyricsData == nil {
            instance.lyricsData = LyricsSection()
        }
        
        guard let lyricsData = instance.lyricsData else { return }
        
        // Clear existing lines
        for line in lyricsData.lines {
            context.delete(line)
        }
        lyricsData.lines.removeAll()
        
        // Add new lines
        for editorLine in lyricsLines {
            let line = LyricsLine(
                text: editorLine.text,
                barIndex: editorLine.barIndex,
                startBeat: editorLine.startBeat,
                endBeat: editorLine.endBeat,
                isEmpty: editorLine.isEmpty
            )
            lyricsData.lines.append(line)
        }
    }
    
    private func clearAllLyrics() {
        lyricsLines.removeAll()
    }
    
    private func updateDisplayName(with type: String) {
        // Keep any existing numbering
        let components = instance.displayName.components(separatedBy: " ")
        if let lastComponent = components.last, let _ = Int(lastComponent) {
            instance.displayName = "\(type) \(lastComponent)"
        } else {
            instance.displayName = type
        }
    }
}

// Helper struct for editing
struct LyricsLineEditor: Identifiable {
    let id = UUID()
    var barIndex: Int
    var text: String
    var startBeat: Double
    var endBeat: Double?
    var isEmpty: Bool
}

struct BarLyricsEditor: View {
    let barIndex: Int
    let blueprint: SectionBlueprint
    let song: Song
    @Binding var lyricsLines: [LyricsLineEditor]
    @State private var selectedBeat: Double = 0.0
    @State private var newLineText = ""
    
    var beatsPerBar: Int { song.timeSig.beatsPerBar }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Bar header with beat markers
            HStack {
                Text("Bar \(barIndex + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if lyricsLines.isEmpty {
                    Text("(empty)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Beat grid for positioning
            BeatGrid(
                beatsPerBar: beatsPerBar,
                selectedBeat: $selectedBeat,
                lyricsLines: lyricsLines
            )
            
            // Existing lyrics for this bar
            ForEach(lyricsLines) { line in
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Beat \(String(format: "%.1f", line.startBeat))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(line.text)
                        .font(.body)
                    Spacer()
                    Button(action: {
                        removeLine(line)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .imageScale(.small)
                    }
                }
                .padding(4)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(4)
            }
            
            // Add new line
            HStack {
                TextField("Add lyrics at beat \(String(format: "%.1f", selectedBeat))", text: $newLineText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addNewLine()
                    }
                Button("Add") {
                    addNewLine()
                }
                .disabled(newLineText.isEmpty)
            }
        }
        .padding(8)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func addNewLine() {
        guard !newLineText.isEmpty else { return }
        let newLine = LyricsLineEditor(
            barIndex: barIndex,
            text: newLineText,
            startBeat: selectedBeat,
            endBeat: nil,
            isEmpty: false
        )
        lyricsLines.append(newLine)
        newLineText = ""
    }
    
    private func removeLine(_ line: LyricsLineEditor) {
        lyricsLines.removeAll { $0.id == line.id }
    }
}

struct BeatGrid: View {
    let beatsPerBar: Int
    @Binding var selectedBeat: Double
    let lyricsLines: [LyricsLineEditor]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<(beatsPerBar * 2), id: \.self) { halfBeat in
                let beat = Double(halfBeat) / 2.0
                Button(action: {
                    selectedBeat = beat
                }) {
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(hasLyricsAt(beat: beat) ? Color.blue : Color.clear)
                            .frame(height: 3)
                        Text(halfBeat % 2 == 0 ? "\(halfBeat/2 + 1)" : "&")
                            .font(.caption2)
                            .foregroundColor(selectedBeat == beat ? .white : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        selectedBeat == beat ? Color.accentColor : Color(UIColor.tertiarySystemBackground)
                    )
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func hasLyricsAt(beat: Double) -> Bool {
        lyricsLines.contains { abs($0.startBeat - beat) < 0.01 }
    }
}