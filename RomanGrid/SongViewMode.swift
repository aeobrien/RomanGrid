import SwiftUI
import SwiftData

struct SongViewMode: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var song: Song
    @State private var cellDisplayMode: CellDisplayMode = .chord
    @AppStorage("colourByFunction") var colourByFunction: Bool = true
    @State private var localTransposition: Int = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Song header info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(song.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if !song.artist.isEmpty {
                            Text(song.artist)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 16) {
                            let effectiveKey = song.keySig.transposed(semitones: song.transposition)
                            Label("\(effectiveKey.tonic.name(preferSharps: effectiveKey.preferSharps)) \(effectiveKey.mode.rawValue)", 
                                  systemImage: "music.note")
                                .font(.caption)
                            
                            if song.transposition != 0 {
                                let sign = song.transposition > 0 ? "+" : ""
                                Label("\(sign)\(song.transposition)", systemImage: "arrow.up.arrow.down")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            Label("\(Int(song.tempoBPM)) BPM", systemImage: "metronome")
                                .font(.caption)
                            
                            if song.capo > 0 {
                                Label("Capo \(song.capo)", systemImage: "guitars")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Sections in arrangement order
                    ForEach(song.arrangement.indices, id: \.self) { index in
                        let section = song.arrangement[index]
                        let blueprint = getBlueprint(for: section)
                        
                        if let blueprint = blueprint {
                            SectionViewCard(
                                section: section,
                                blueprint: blueprint,
                                song: song,
                                cellDisplayMode: cellDisplayMode,
                                colourByFunction: colourByFunction
                            )
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("View Mode")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // Transposition control bar
                HStack {
                    Button(action: {
                        if localTransposition > -11 {
                            localTransposition -= 1
                            song.transposition = localTransposition
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                    }
                    .disabled(localTransposition <= -11)
                    
                    Text(localTransposition == 0 ? "Original Key" : "\(localTransposition > 0 ? "+" : "")\(localTransposition) semitones")
                        .frame(minWidth: 120)
                        .font(.callout)
                    
                    Button(action: {
                        if localTransposition < 11 {
                            localTransposition += 1
                            song.transposition = localTransposition
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .disabled(localTransposition >= 11)
                    
                    Spacer()
                    
                    if localTransposition != 0 {
                        Button("Reset") {
                            localTransposition = 0
                            song.transposition = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
            .onAppear {
                localTransposition = song.transposition
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Display", selection: $cellDisplayMode) {
                            ForEach(CellDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private func getBlueprint(for section: SectionInstance) -> SectionBlueprint? {
        if !section.isLinked, let ownBlueprint = section.ownBlueprint {
            return ownBlueprint
        }
        return song.blueprints.first { $0.id == section.blueprintID }
    }
}

struct SectionViewCard: View {
    let section: SectionInstance
    let blueprint: SectionBlueprint
    let song: Song
    let cellDisplayMode: CellDisplayMode
    let colourByFunction: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(section.displayName)
                    .font(.headline)
                
                if blueprint.name.contains("(Custom)") {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                // Show section key if different from song key
                if section.keyOverride != nil {
                    let effectiveKey = section.effectiveKey(songKey: song.keySig, songTransposition: song.transposition)
                    HStack(spacing: 2) {
                        Image(systemName: "key")
                            .font(.caption2)
                        Text("\(effectiveKey.tonic.name(preferSharps: effectiveKey.preferSharps)) \(effectiveKey.mode == .ionian ? "Major" : effectiveKey.mode == .aeolian ? "Minor" : effectiveKey.mode.rawValue)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
                }
                
                Spacer()
                
                Text("\(blueprint.bars) bars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Chord grid with integrated lyrics
            ChordGridWithLyricsView(
                section: section,
                blueprint: blueprint,
                song: song,
                cellDisplayMode: cellDisplayMode,
                colourByFunction: colourByFunction
            )
        }
        .padding(.vertical, 8)
    }
}

struct LyricsBarDisplay: View {
    let lyrics: [LyricsLine]
    let beatsPerBar: Int
    let cellsPerBar: Int
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background
                Color(UIColor.secondarySystemBackground).opacity(0.3)
                
                // Position each lyric line at its beat position
                ForEach(lyrics, id: \.id) { line in
                    if !line.isEmpty {
                        let xOffset = calculateXOffset(for: line.startBeat, width: geometry.size.width)
                        Text(line.text)
                            .font(.body)
                            .foregroundColor(.primary)
                            .offset(x: xOffset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(minHeight: 24)
        .cornerRadius(4)
    }
    
    private func calculateXOffset(for beat: Double, width: CGFloat) -> CGFloat {
        // Convert beat position to pixel offset
        let beatWidth = width / CGFloat(beatsPerBar)
        return beatWidth * CGFloat(beat)
    }
}

struct ChordGridWithLyricsView: View {
    let section: SectionInstance
    let blueprint: SectionBlueprint
    let song: Song
    let cellDisplayMode: CellDisplayMode
    let colourByFunction: Bool
    
    var effectiveKey: KeySignature {
        section.effectiveKey(songKey: song.keySig, songTransposition: song.transposition)
    }
    
    var cellsPerBar: Int {
        song.timeSig.beatsPerBar * blueprint.resolution.rawValue
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<blueprint.bars, id: \.self) { barIndex in
                VStack(spacing: 4) {
                    // Chord bar
                    HStack(spacing: 1) {
                        ForEach(0..<cellsPerBar, id: \.self) { cellIndex in
                            let tick = barIndex * cellsPerBar + cellIndex
                            ChordCellView(
                                tick: tick,
                                blueprint: blueprint,
                                song: song,
                                section: section,
                                cellDisplayMode: cellDisplayMode,
                                colourByFunction: colourByFunction,
                                isFirstInBar: cellIndex == 0
                            )
                        }
                    }
                    
                    // Lyrics for this bar (if present)
                    if let lyricsData = section.lyricsData {
                        let barLyrics = lyricsData.lines.filter { $0.barIndex == barIndex }
                        if !barLyrics.isEmpty {
                            LyricsBarDisplay(
                                lyrics: barLyrics,
                                beatsPerBar: song.timeSig.beatsPerBar,
                                cellsPerBar: cellsPerBar
                            )
                        } else {
                            // Show empty space for blank bars to maintain structure
                            Color.clear
                                .frame(height: 20)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct ChordGridView: View {
    let blueprint: SectionBlueprint
    let song: Song
    let cellDisplayMode: CellDisplayMode
    let colourByFunction: Bool
    
    var cellsPerBar: Int {
        song.timeSig.beatsPerBar * blueprint.resolution.rawValue
    }
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<blueprint.bars, id: \.self) { barIndex in
                HStack(spacing: 1) {
                    ForEach(0..<cellsPerBar, id: \.self) { cellIndex in
                        let tick = barIndex * cellsPerBar + cellIndex
                        ChordCellView(
                            tick: tick,
                            blueprint: blueprint,
                            song: song,
                            section: nil,  // ChordGridView doesn't have section context
                            cellDisplayMode: cellDisplayMode,
                            colourByFunction: colourByFunction,
                            isFirstInBar: cellIndex == 0
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct ChordCellView: View {
    let tick: Int
    let blueprint: SectionBlueprint
    let song: Song
    let section: SectionInstance?
    let cellDisplayMode: CellDisplayMode
    let colourByFunction: Bool
    let isFirstInBar: Bool
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .strokeBorder(
                    isFirstInBar ? Color.primary.opacity(0.3) : Color.secondary.opacity(0.1),
                    lineWidth: isFirstInBar ? 1 : 0.5
                )
                .background(
                    isFirstInBar ? Color.secondary.opacity(0.05) : Color.clear
                )
            
            // Content
            if let event = eventCovering(tick) {
                Rectangle()
                    .fill(cellColour(for: event))
                    .opacity(0.15)
                
                Text(chordLabel(event))
                    .font(.system(size: cellDisplayMode == .both ? 9 : 11))
                    .minimumScaleFactor(0.5)
                    .lineLimit(cellDisplayMode == .both ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .padding(2)
            }
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
    }
    
    private func eventCovering(_ tick: Int) -> ChordEvent? {
        blueprint.events.first { ev in
            tick >= ev.startTick && tick < ev.startTick + ev.lengthTicks
        }
    }
    
    private func chordLabel(_ ev: ChordEvent) -> String {
        if ev.isRest { return "" }
        // Use effective key for the section if available
        let effectiveKey = section?.effectiveKey(songKey: song.keySig, songTransposition: song.transposition) ?? song.keySig.transposed(semitones: song.transposition)
        // Transpose the chord for display
        let transposedChord = Chord(
            root: ev.chord.root.transposed(semitones: song.transposition),
            quality: ev.chord.quality,
            flags: ev.chord.flags,
            alterations: ev.chord.alterations,
            bass: ev.chord.bass?.transposed(semitones: song.transposition)
        )
        let name = transposedChord.displayName(preferSharps: effectiveKey.preferSharps, capo: song.capo, showShapesWithCapo: false)
        let roman = Roman.roman(for: ev.chord, in: effectiveKey)
        switch cellDisplayMode {
        case .chord: return name
        case .roman: return roman
        case .both: return "\(roman)\n\(name)"
        }
    }
    
    private func cellColour(for ev: ChordEvent) -> Color {
        guard colourByFunction, !ev.isRest else { return .accentColor }
        // Use effective key for the section if available
        let effectiveKey = section?.effectiveKey(songKey: song.keySig, songTransposition: song.transposition) ?? song.keySig.transposed(semitones: song.transposition)
        let offset = (ev.chord.root.rawValue - effectiveKey.tonic.rawValue + 12) % 12
        let (idx, _) = Roman.degree(for: offset, mode: effectiveKey.mode)
        let palette: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink]
        return palette[idx % palette.count]
    }
}