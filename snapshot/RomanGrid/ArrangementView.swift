import SwiftUI
import SwiftData

struct ArrangementView: View {
    @Environment(\.modelContext) private var context
    @Bindable var song: Song
    @State private var newDisplayName = "Verse 1"
    @State private var selectedBlueprint: SectionBlueprint?
    @State private var repeats = 1
    @State private var lyrics = ""
    
    var body: some View {
        VStack {
            List {
                Section("Add to arrangement") {
                    Picker("From blueprint", selection: $selectedBlueprint) {
                        Text("Choose…").tag(Optional<SectionBlueprint>.none)
                        ForEach(song.blueprints) { bp in
                            Text(bp.name).tag(Optional(bp))
                        }
                    }
                    TextField("Display name", text: $newDisplayName)
                    Stepper("Repeats: \(repeats)", value: $repeats, in: 1...16)
                    TextField("Lyrics (optional)", text: $lyrics, axis: .vertical)
                    Button("Insert") { insertInstance() }.disabled(selectedBlueprint == nil)
                }
                
                Section("Order") {
                    ForEach(song.arrangement) { inst in
                        HStack {
                            Text(inst.displayName)
                            Spacer()
                            Text("x\(inst.repeats)").foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button("Push blueprint changes to all copies") { pushChanges(from: inst) }
                            Button("Set modulation…") { setModulation(inst) }
                            Button("Edit lyrics") { editLyrics(inst) }
                            Button(role: .destructive) { context.delete(inst) } label: { Text("Delete") }
                        }
                    }
                    .onMove { from, to in
                        song.arrangement.move(fromOffsets: from, toOffset: to)
                    }
                }
                
                Section("Length") {
                    Text("Total bars (before repeats): \(totalBarsRaw())")
                    Text("Total bars (with repeats): \(totalBarsWithRepeats())")
                }
            }
            .toolbar { EditButton() }
        }
        .navigationTitle("Arrangement")
    }
    
    private func insertInstance() {
        guard let bp = selectedBlueprint else { return }
        let idx = song.arrangement.filter { $0.blueprintID == bp.id }.count + 1
        let inst = SectionInstance(displayName: newDisplayName.isEmpty ? "\(bp.name) \(idx)" : newDisplayName,
                                   repeats: repeats,
                                   keyOverride: nil,
                                   lyrics: lyrics,
                                   blueprintID: bp.id)
        song.arrangement.append(inst)
        newDisplayName = "\(bp.name) \(idx+1)"
        repeats = 1
        lyrics = ""
    }
    
    private func blueprintFor(_ inst: SectionInstance) -> SectionBlueprint? {
        song.blueprints.first { $0.id == inst.blueprintID }
    }
    private func totalBarsRaw() -> Int {
        song.arrangement.compactMap { blueprintFor($0)?.bars }.reduce(0, +)
    }
    private func totalBarsWithRepeats() -> Int {
        song.arrangement.reduce(0) { acc, inst in
            acc + (blueprintFor(inst)?.bars ?? 0) * inst.repeats
        }
    }
    private func pushChanges(from inst: SectionInstance) {
        // Stub for v2 (blueprints already centralise events).
    }
    private func setModulation(_ inst: SectionInstance) {
        if inst.keyOverride == nil {
            let newKey = KeySignature(tonic: song.keySig.tonic.transposed(semitones: 7), mode: song.keySig.mode)
            inst.keyOverride = newKey
        } else {
            inst.keyOverride = nil
        }
    }
    private func editLyrics(_ inst: SectionInstance) {
        // Add a sheet with TextEditor bound to inst.lyrics in v1.1 if you like.
    }
}
