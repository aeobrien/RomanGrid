import SwiftUI
import SwiftData

struct GlobalLyricsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let song: Song
    
    @State private var lyricsText = ""
    @State private var selectedRange: NSRange? = nil
    @State private var assignmentsByRange: [LyricsAssignment] = []
    @State private var showingSectionPicker = false
    @State private var currentAssignment: LyricsAssignment? = nil
    
    struct LyricsAssignment: Identifiable {
        let id = UUID()
        var range: NSRange
        var sectionIndex: Int
        var barIndex: Int
        var text: String
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main lyrics editor
                ScrollView {
                    TextEditor(text: $lyricsText)
                        .frame(minHeight: 300)
                        .padding()
                        .overlay(alignment: .topTrailing) {
                            if !assignmentsByRange.isEmpty {
                                VStack(alignment: .trailing, spacing: 4) {
                                    ForEach(assignmentsByRange) { assignment in
                                        let section = song.arrangement[assignment.sectionIndex]
                                        Label("\(section.displayName) - Bar \(assignment.barIndex + 1)", 
                                              systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .padding(4)
                                            .background(Color.green.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding()
                            }
                        }
                }
                
                Divider()
                
                // Assignment controls
                VStack(spacing: 12) {
                    Text("Select text above and assign it to a section")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showingSectionPicker = true
                    }) {
                        Label("Assign Selected Text", systemImage: "text.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lyricsText.isEmpty)
                    
                    // Show current assignments
                    if !assignmentsByRange.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Assignments:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            ForEach(assignmentsByRange) { assignment in
                                HStack {
                                    Text("\(song.arrangement[assignment.sectionIndex].displayName) Bar \(assignment.barIndex + 1)")
                                        .font(.caption)
                                    Spacer()
                                    Text("\"\(String(assignment.text.prefix(20)))...\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button(action: {
                                        removeAssignment(assignment)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .imageScale(.small)
                                    }
                                }
                                .padding(8)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Lyrics Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAllLyrics()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSectionPicker) {
                SectionBarPicker(song: song) { sectionIndex, barIndex in
                    assignSelectedText(to: sectionIndex, bar: barIndex)
                }
            }
        }
        .onAppear {
            loadExistingLyrics()
        }
    }
    
    private func loadExistingLyrics() {
        // Load any existing lyrics from sections
        var allLyrics = ""
        for section in song.arrangement {
            if let lyricsData = section.lyricsData {
                for line in lyricsData.lines.sorted(by: { $0.barIndex < $1.barIndex }) {
                    if !line.text.isEmpty {
                        allLyrics += line.text + "\n"
                    }
                }
            }
        }
        lyricsText = allLyrics
    }
    
    private func assignSelectedText(to sectionIndex: Int, bar barIndex: Int) {
        // For now, we'll take the current selection or the whole text
        let selectedText = getSelectedText()
        
        let assignment = LyricsAssignment(
            range: NSRange(location: 0, length: selectedText.count),
            sectionIndex: sectionIndex,
            barIndex: barIndex,
            text: selectedText
        )
        
        assignmentsByRange.append(assignment)
    }
    
    private func getSelectedText() -> String {
        // In a real implementation, we'd get the actual selection
        // For now, we'll use line-by-line assignment
        let lines = lyricsText.components(separatedBy: .newlines)
        return lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    }
    
    private func removeAssignment(_ assignment: LyricsAssignment) {
        assignmentsByRange.removeAll { $0.id == assignment.id }
    }
    
    private func saveAllLyrics() {
        // Clear existing lyrics
        for section in song.arrangement {
            if let lyricsData = section.lyricsData {
                for line in lyricsData.lines {
                    context.delete(line)
                }
                lyricsData.lines.removeAll()
            }
        }
        
        // Apply new assignments
        for assignment in assignmentsByRange {
            let section = song.arrangement[assignment.sectionIndex]
            
            if section.lyricsData == nil {
                section.lyricsData = LyricsSection()
            }
            
            if let lyricsData = section.lyricsData {
                let line = LyricsLine(text: assignment.text, barIndex: assignment.barIndex)
                lyricsData.lines.append(line)
            }
        }
    }
}

struct SectionBarPicker: View {
    let song: Song
    let onSelect: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSectionIndex = 0
    @State private var selectedBarIndex = 0
    
    var selectedSection: SectionInstance? {
        guard selectedSectionIndex < song.arrangement.count else { return nil }
        return song.arrangement[selectedSectionIndex]
    }
    
    var selectedBlueprint: SectionBlueprint? {
        guard let section = selectedSection else { return nil }
        if !section.isLinked, let ownBlueprint = section.ownBlueprint {
            return ownBlueprint
        }
        return song.blueprints.first { $0.id == section.blueprintID }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Select Section") {
                    Picker("Section", selection: $selectedSectionIndex) {
                        ForEach(song.arrangement.indices, id: \.self) { index in
                            Text(song.arrangement[index].displayName).tag(index)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                }
                
                if let blueprint = selectedBlueprint {
                    Section("Select Bar") {
                        Picker("Bar", selection: $selectedBarIndex) {
                            ForEach(0..<blueprint.bars, id: \.self) { barIndex in
                                Text("Bar \(barIndex + 1)").tag(barIndex)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }
                }
            }
            .navigationTitle("Assign Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") {
                        onSelect(selectedSectionIndex, selectedBarIndex)
                        dismiss()
                    }
                }
            }
        }
    }
}