import SwiftUI

// MARK: - Enhanced Chord Builder for SectionGridEditor

struct ChordBuilderBar: View {
    @Binding var currentChord: Chord?
    @Binding var currentCell: Int
    let song: Song
    let onApply: (Chord, Bool) -> Void  // Bool indicates whether to advance
    let onDelete: () -> Void
    let onRest: () -> Void
    
    // Stage 1 state
    @State private var selectedRoot: PitchClass? = nil
    @State private var selectedTriad: Chord.Quality? = nil
    @State private var selectedSeventh: SeventhType? = nil
    @State private var selectedInversion: InversionType = .root
    @State private var selectedBass: PitchClass? = nil
    @State private var immediateUpdate = true
    @State private var showSecondRow = false
    
    // Advanced state
    @State private var showAdvanced = false
    @State private var selectedFlags: Chord.Flags = []
    @State private var selectedAlterations: [Chord.Alteration] = []
    
    // Helper types
    enum SeventhType: String, CaseIterable {
        case none = "None"
        case dom7 = "7"
        case maj7 = "M7"
        case min7 = "m7"  // This is contextual - only valid with minor triad
        
        var flags: Chord.Flags {
            switch self {
            case .none: return []
            case .dom7: return [.seven]
            case .maj7: return [.maj7]
            case .min7: return [.seven] // Combined with minor quality
            }
        }
    }
    
    enum InversionType: String, CaseIterable {
        case root = "Root"
        case first = "1st"
        case second = "2nd"
        case third = "3rd"
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // First row: Root and Quality (the most important) + expand button
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROOT")
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    rootSelector
                        .frame(height: 24)
                }
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("QUALITY")
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    triadSelector
                        .frame(height: 24)
                }
                .frame(maxWidth: .infinity)
                
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSecondRow.toggle()
                    }
                }) {
                    Image(systemName: showSecondRow ? "minus.circle" : "plus.circle")
                        .imageScale(.medium)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
            }
            
            // Second row: Extensions and modifications (collapsible)
            if showSecondRow {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("7TH")
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        seventhSelector
                            .frame(height: 24)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INVERSION")
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        inversionSelector
                            .frame(height: 24)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BASS")
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        bassSelector
                            .frame(height: 24)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button(action: { 
                        immediateUpdate = false
                        showAdvanced = true
                    }) {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.medium)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentChord == nil)
                    .frame(width: 24)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Divider()
            
            // Action buttons
            actionRow
        }
        .padding(6)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: selectedRoot) { _, _ in updateChord() }
        .onChange(of: selectedTriad) { _, _ in updateChord() }
        .onChange(of: selectedSeventh) { _, _ in updateChord() }
        .onChange(of: selectedInversion) { _, _ in updateChord() }
        .onChange(of: selectedBass) { _, _ in updateChord() }
        .onChange(of: currentChord) { _, newChord in
            if !immediateUpdate {
                return
            }
            loadChordIntoSelectors(newChord)
        }
        .onAppear {
            loadChordIntoSelectors(currentChord)
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedChordOptions(
                chord: $currentChord,
                flags: $selectedFlags,
                alterations: $selectedAlterations,
                song: song
            )
            .onDisappear {
                immediateUpdate = true
                if let chord = currentChord {
                    onApply(chord, false)
                }
            }
        }
    }
    
    // MARK: - UI Components
    
    private var rootSelector: some View {
        Picker("", selection: Binding(
            get: { selectedRoot },
            set: { newRoot in
                print("[CHORD BUILDER] Root changed from \(selectedRoot?.name(preferSharps: true) ?? "nil") to \(newRoot?.name(preferSharps: true) ?? "nil")")
                selectedRoot = newRoot
                if let root = newRoot {
                    // Auto-select quality based on scale degree
                    let autoQuality = getAutoTriad(for: root)
                    print("[CHORD BUILDER] Auto quality for \(root.name(preferSharps: true)) in \(song.keySig.tonic.name(preferSharps: true)) \(song.keySig.mode.rawValue): \(autoQuality)")
                    selectedTriad = autoQuality
                }
            }
        )) {
            Text("-").tag(nil as PitchClass?)
            ForEach(PitchClass.allCases) { pc in
                let romanInfo = getRomanNumeral(for: pc)
                Text("\(pc.name(preferSharps: song.keySig.preferSharps)) - \(romanInfo)")
                    .tag(pc as PitchClass?)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }
    
    private var triadSelector: some View {
        Picker("", selection: $selectedTriad) {
            Text("-").tag(nil as Chord.Quality?)
            Text("Maj").tag(Chord.Quality.maj as Chord.Quality?)
            Text("min").tag(Chord.Quality.min as Chord.Quality?)
            Text("dim").tag(Chord.Quality.dim as Chord.Quality?)
            Text("aug").tag(Chord.Quality.aug as Chord.Quality?)
            Text("sus2").tag(Chord.Quality.sus2 as Chord.Quality?)
            Text("sus4").tag(Chord.Quality.sus4 as Chord.Quality?)
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }
    
    private var seventhSelector: some View {
        Picker("", selection: Binding(
            get: { selectedSeventh },
            set: { selectedSeventh = $0 }
        )) {
            Text("-").tag(nil as SeventhType?)
            Text("7").tag(SeventhType.dom7 as SeventhType?)
            Text("M7").tag(SeventhType.maj7 as SeventhType?)
            if selectedTriad == .min {
                Text("m7").tag(SeventhType.min7 as SeventhType?)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }
    
    private var inversionSelector: some View {
        Picker("", selection: $selectedInversion) {
            Text("Root").tag(InversionType.root)
            Text("1st").tag(InversionType.first)
            Text("2nd").tag(InversionType.second)
            if let seventh = selectedSeventh, seventh != SeventhType.none {
                Text("3rd").tag(InversionType.third)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }
    
    private var bassSelector: some View {
        Picker("", selection: $selectedBass) {
            Text("Default").tag(nil as PitchClass?)
            ForEach(PitchClass.allCases) { pc in
                Text("/\(pc.name(preferSharps: song.keySig.preferSharps))")
                    .tag(pc as PitchClass?)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }
    
    
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Rest") {
                onRest()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadChordIntoSelectors(_ chord: Chord?) {
        immediateUpdate = false
        defer { immediateUpdate = true }
        
        if let chord = chord {
            selectedRoot = chord.root
            selectedTriad = chord.quality
            
            // Determine seventh type from flags
            if chord.flags.contains(.maj7) {
                selectedSeventh = .maj7
            } else if chord.flags.contains(.seven) {
                if chord.quality == .min {
                    selectedSeventh = .min7
                } else {
                    selectedSeventh = .dom7
                }
            } else {
                selectedSeventh = nil
            }
            
            // Determine inversion from bass note
            if let bass = chord.bass {
                if bass == getInversionBass(root: chord.root, quality: chord.quality, inversion: .first) {
                    selectedInversion = .first
                    selectedBass = nil
                } else if bass == getInversionBass(root: chord.root, quality: chord.quality, inversion: .second) {
                    selectedInversion = .second
                    selectedBass = nil
                } else if bass == getInversionBass(root: chord.root, quality: chord.quality, inversion: .third) {
                    selectedInversion = .third
                    selectedBass = nil
                } else {
                    selectedInversion = .root
                    selectedBass = bass
                }
            } else {
                selectedInversion = .root
                selectedBass = nil
            }
            
            selectedFlags = chord.flags.subtracting([.seven, .maj7])
            selectedAlterations = chord.alterations
        } else {
            // Reset to neutral
            selectedRoot = nil
            selectedTriad = nil
            selectedSeventh = nil
            selectedInversion = .root
            selectedBass = nil
            selectedFlags = []
            selectedAlterations = []
        }
    }
    
    private func updateChord() {
        guard let root = selectedRoot else {
            currentChord = nil
            return
        }
        
        var flags: Chord.Flags = []
        if let seventh = selectedSeventh {
            flags = seventh.flags
            if selectedTriad == .min && seventh == .min7 {
                // For m7, we need minor quality + seven flag
                flags = [.seven]
            }
        }
        
        // Merge with advanced flags
        flags = flags.union(selectedFlags)
        
        // Calculate bass note for inversions or slash
        var bassNote: PitchClass? = selectedBass
        if bassNote == nil && selectedInversion != .root {
            bassNote = getInversionBass(root: root, quality: selectedTriad ?? .maj, inversion: selectedInversion)
        }
        
        let newChord = Chord(
            root: root,
            quality: selectedTriad ?? .maj,
            flags: flags,
            alterations: selectedAlterations,
            bass: bassNote
        )
        
        currentChord = newChord
        
        // Immediately apply to cell without advancing
        if immediateUpdate {
            onApply(newChord, false)
        }
    }
    
    private func getAutoTriad(for root: PitchClass) -> Chord.Quality {
        let tonic = song.keySig.tonic
        let mode = song.keySig.mode
        let scale = Roman.scale(for: mode)
        let offset = (root.rawValue - tonic.rawValue + 12) % 12
        
        print("[CHORD BUILDER] Getting auto triad: root=\(root.name(preferSharps: true)), tonic=\(tonic.name(preferSharps: true)), mode=\(mode.rawValue), offset=\(offset)")
        print("[CHORD BUILDER] Scale degrees: \(scale)")
        
        if let idx = scale.firstIndex(of: offset) {
            print("[CHORD BUILDER] Found at scale degree \(idx + 1)")
            let quality: Chord.Quality
            switch mode {
            case .ionian: // Major - I, ii, iii, IV, V, vi, vii°
                quality = [0, 3, 4].contains(idx) ? .maj : (idx == 6 ? .dim : .min)
            case .aeolian: // Minor - i, ii°, III, iv, v, VI, VII
                quality = [2, 5, 6].contains(idx) ? .maj : (idx == 1 ? .dim : .min)
            case .dorian: // i, ii, III, IV, v, vi°, VII
                quality = [1, 2, 3].contains(idx) ? .maj : (idx == 5 ? .dim : .min)
            case .mixolydian: // I, ii, iii°, IV, v, vi, VII
                quality = [0, 3, 4, 6].contains(idx) ? .maj : (idx == 2 ? .dim : .min)
            case .lydian: // I, II, iii, #iv°, V, vi, vii
                quality = [0, 1, 4].contains(idx) ? .maj : (idx == 3 ? .dim : .min)
            case .phrygian: // i, II, III, iv, v°, VI, vii
                quality = [1, 2, 5, 6].contains(idx) ? .maj : (idx == 4 ? .dim : .min)
            case .locrian: // i°, II, iii, iv, V, VI, vii
                quality = [1, 3, 4, 5, 6].contains(idx) ? .maj : (idx == 0 ? .dim : .min)
            }
            print("[CHORD BUILDER] Selected quality: \(quality)")
            return quality
        }
        print("[CHORD BUILDER] Note not in scale, defaulting to major")
        return .maj
    }
    
    private func getInversionBass(root: PitchClass, quality: Chord.Quality, inversion: InversionType) -> PitchClass? {
        switch inversion {
        case .root:
            return nil
        case .first:
            // Third in bass
            let interval = (quality == .min || quality == .dim) ? 3 : 4
            return root.transposed(semitones: interval)
        case .second:
            // Fifth in bass
            let interval = quality == .dim ? 6 : (quality == .aug ? 8 : 7)
            return root.transposed(semitones: interval)
        case .third:
            // Seventh in bass (if present)
            if let seventh = selectedSeventh, seventh != SeventhType.none {
                let interval = seventh == .maj7 ? 11 : 10
                return root.transposed(semitones: interval)
            }
            return nil
        }
    }
    
    private func getRomanNumeral(for root: PitchClass) -> String {
        let tonic = song.keySig.tonic
        let mode = song.keySig.mode
        let scale = Roman.scale(for: mode)
        let offset = (root.rawValue - tonic.rawValue + 12) % 12
        
        // Base numerals for major scale
        let baseNumerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        
        if let idx = scale.firstIndex(of: offset) {
            let quality = getAutoTriad(for: root)
            var numeral = baseNumerals[idx]
            
            // Adjust case based on quality
            if quality == .min {
                numeral = numeral.lowercased()
            } else if quality == .dim {
                numeral = numeral.lowercased() + "°"
            } else if quality == .aug {
                numeral = numeral + "+"
            }
            return numeral
        }
        
        // For chromatic notes, show with accidentals
        let (idx, acc) = Roman.degree(for: offset, mode: mode)
        var numeral = baseNumerals[idx]
        if acc == -1 {
            numeral = "♭" + numeral
        } else if acc == 1 {
            numeral = "♯" + numeral
        }
        return numeral.lowercased() // Chromatic notes shown in lowercase
    }
    
}

// MARK: - Advanced Options Sheet

struct AdvancedChordOptions: View {
    @Binding var chord: Chord?
    @Binding var flags: Chord.Flags
    @Binding var alterations: [Chord.Alteration]
    let song: Song
    @Environment(\.dismiss) private var dismiss
    
    @State private var sus2Selected = false
    @State private var sus4Selected = false
    @State private var add9Selected = false
    @State private var nineSelected = false
    @State private var sixSelected = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Suspended") {
                    Toggle("sus2", isOn: Binding(
                        get: { chord?.quality == .sus2 },
                        set: { enabled in
                            if enabled {
                                chord?.quality = .sus2
                            } else if chord?.quality == .sus2 {
                                chord?.quality = .maj
                            }
                        }
                    ))
                    
                    Toggle("sus4", isOn: Binding(
                        get: { chord?.quality == .sus4 },
                        set: { enabled in
                            if enabled {
                                chord?.quality = .sus4
                            } else if chord?.quality == .sus4 {
                                chord?.quality = .maj
                            }
                        }
                    ))
                }
                
                Section("Extensions") {
                    Toggle("6", isOn: Binding(
                        get: { flags.contains(.six) },
                        set: { enabled in
                            if enabled {
                                flags.insert(.six)
                            } else {
                                flags.remove(.six)
                            }
                        }
                    ))
                    
                    Toggle("9", isOn: Binding(
                        get: { flags.contains(.nine) },
                        set: { enabled in
                            if enabled {
                                flags.insert(.nine)
                                flags.remove(.add9) // Mutually exclusive
                            } else {
                                flags.remove(.nine)
                            }
                        }
                    ))
                    
                    Toggle("add9", isOn: Binding(
                        get: { flags.contains(.add9) },
                        set: { enabled in
                            if enabled {
                                flags.insert(.add9)
                                flags.remove(.nine) // Mutually exclusive
                            } else {
                                flags.remove(.add9)
                            }
                        }
                    ))
                }
                
                Section("Alterations") {
                    Text("Alterations like ♭5, ♯5, ♭9, ♯9, ♯11, ♭13")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // These would need to be added to the Chord.Alteration enum
                }
                
                Section("Preview") {
                    if let chord = chord {
                        Text(chord.displayName(
                            preferSharps: song.keySig.preferSharps,
                            capo: song.capo,
                            showShapesWithCapo: false
                        ))
                        .font(.title2)
                        .bold()
                    }
                }
            }
            .navigationTitle("Advanced Options")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}