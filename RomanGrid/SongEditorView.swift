import SwiftUI
import SwiftData

struct SongEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var song: Song
    
    @State private var presentTapTempo = false
    @State private var newBPName = "Verse"
    @State private var newBars = 4
    @State private var newResolution: GridResolution = .beat
    
    var body: some View {
        VStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $song.title)
                    TextField("Artist", text: $song.artist)
                    TextField("Tags (comma-separated)", text: Binding(
                        get: { song.tags.joined(separator: ", ") },
                        set: { song.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                    TextField("Notes", text: $song.notes, axis: .vertical)
                }
                
                Section("Key & Tempo") {
                    KeyPicker(keySig: $song.keySig)
                    HStack {
                        Stepper(value: $song.tempoBPM, in: 20...300, step: 0.1) {
                            Text("Tempo: \(String(format: "%.1f", song.tempoBPM)) BPM")
                        }
                        Spacer()
                        Button("Tap") { presentTapTempo = true }
                    }
                    TimeSignaturePicker(timeSig: $song.timeSig)
                    Stepper("Capo: \(song.capo)", value: $song.capo, in: 0...12)
                    Picker("View Mode", selection: $song.viewMode) {
                        ForEach(ChordDisplayMode.allCases) { m in
                            Text(m.rawValue.capitalized).tag(m)
                        }
                    }
                }
                
                Section("Blueprints") {
                    ForEach(song.blueprints) { bp in
                        NavigationLink("\(bp.name) (\(bp.bars) bars, \(bp.resolution.label))") {
                            SectionGridEditor(song: song, blueprint: bp)
                        }
                    }.onDelete { idx in
                        idx.map { song.blueprints[$0] }.forEach(context.delete)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("New section name", text: $newBPName)
                            HStack {
                                Button(action: { if newBars > 1 { newBars -= 1 } }) {
                                    Image(systemName: "minus.circle")
                                }
                                Text("\(newBars) bars")
                                    .frame(minWidth: 60)
                                Button(action: { if newBars < 128 { newBars += 1 } }) {
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                        HStack {
                            Picker("Grid", selection: $newResolution) {
                                ForEach(GridResolution.allCases) { r in
                                    Text(r.label).tag(r)
                                }
                            }.pickerStyle(.segmented)
                            Button("Add Section") { addBlueprint() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                Section("Arrangement") {
                    NavigationLink("Open Arrangement") {
                        ArrangementView(song: song)
                    }
                }
            }
        }
        .navigationTitle(song.title)
        .sheet(isPresented: $presentTapTempo) {
            TapTempoView(bpm: $song.tempoBPM)
        }
    }
    
    private func addBlueprint() {
        let bp = SectionBlueprint(name: newBPName, bars: newBars, resolution: newResolution)
        song.blueprints.append(bp)
    }
}

struct KeyPicker: View {
    @Binding var keySig: KeySignature
    var body: some View {
        HStack {
            Picker("Tonic", selection: Binding(
                get: { keySig.tonic },
                set: { keySig.tonic = $0 }
            )) {
                ForEach(PitchClass.allCases) { pc in
                    Text(pc.name(preferSharps: keySig.preferSharps)).tag(pc)
                }
            }
            Picker("Mode", selection: Binding(
                get: { keySig.mode },
                set: { keySig.mode = $0 }
            )) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
        }
    }
}

struct TimeSignaturePicker: View {
    @Binding var timeSig: TimeSignature
    var body: some View {
        HStack {
            Stepper("Beats/bar: \(timeSig.beatsPerBar)", value: $timeSig.beatsPerBar, in: 1...12)
            Stepper("Beat unit: \(timeSig.beatUnit)", value: $timeSig.beatUnit, in: 1...8)
        }
    }
}
