import SwiftUI
import SwiftData

struct SongEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var song: Song
    
    @State private var presentTapTempo = false
    
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
                    
                    // Global transposition control
                    HStack {
                        Text("Transpose:")
                        Picker("Transposition", selection: $song.transposition) {
                            ForEach(-11...11, id: \.self) { semitones in
                                if semitones == 0 {
                                    Text("Original").tag(semitones)
                                } else {
                                    let sign = semitones > 0 ? "+" : ""
                                    Text("\(sign)\(semitones) semitones").tag(semitones)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        
                        if song.transposition != 0 {
                            Button(action: { song.transposition = 0 }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    
                    // Show effective key when transposed
                    if song.transposition != 0 {
                        HStack {
                            Text("Playing in:")
                                .foregroundColor(.secondary)
                            let effectiveKey = song.keySig.transposed(semitones: song.transposition)
                            Text("\(effectiveKey.tonic.name(preferSharps: effectiveKey.preferSharps)) \(effectiveKey.mode.rawValue)")
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                    }
                    
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
                
                Section("Track Editor") {
                    NavigationLink("Edit Track") {
                        TrackEditor(song: song)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if !song.arrangement.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Track Overview")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(song.arrangement) { section in
                                if let blueprint = song.blueprints.first(where: { $0.id == section.blueprintID }) {
                                    HStack {
                                        Text(section.displayName)
                                            .font(.caption)
                                        Spacer()
                                        Text("\(blueprint.bars) bars")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section("Section Library") {
                    ForEach(song.blueprints) { bp in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bp.name)
                                Text("\(bp.bars) bars, \(bp.resolution.label)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(song.arrangement.filter { $0.blueprintID == bp.id }.count) uses")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }.onDelete { idx in
                        // Check if blueprint is used in arrangement
                        let toDelete = idx.map { song.blueprints[$0] }
                        for bp in toDelete {
                            // Remove from arrangement first
                            song.arrangement.removeAll { $0.blueprintID == bp.id }
                        }
                        idx.map { song.blueprints[$0] }.forEach(context.delete)
                    }
                }
            }
        }
        .navigationTitle(song.title)
        .sheet(isPresented: $presentTapTempo) {
            TapTempoView(bpm: $song.tempoBPM)
        }
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
