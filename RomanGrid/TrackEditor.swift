import SwiftUI
import SwiftData

struct TrackEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var song: Song
    @AppStorage("colourByFunction") var colourByFunction: Bool = true
    
    // Track-wide state
    @State private var selectedSectionIndex: Int = 0
    @State private var selectedCell: Int = 0
    @State private var buildingChord: Chord? = nil
    @State private var debugMessage: String = ""
    @State private var cellDisplayMode: CellDisplayMode = .chord
    @State private var showAddSection = false
    @State private var isDragging = false
    @State private var dragStartCell: Int? = nil
    @State private var dragCurrentCell: Int? = nil
    @State private var draggedCells: Set<Int> = []
    @State private var selectionStart: Int? = nil
    @State private var selectionEnd: Int? = nil
    @State private var scrollDisabled = false
    @State private var dragChord: Chord? = nil  // Store chord from drag start cell
    
    var currentSection: SectionInstance? {
        guard selectedSectionIndex < song.arrangement.count else { return nil }
        return song.arrangement[selectedSectionIndex]
    }
    
    var currentBlueprint: SectionBlueprint? {
        guard let instance = currentSection else { return nil }
        // Return own blueprint if unlinked, otherwise return shared blueprint
        if !instance.isLinked, let ownBlueprint = instance.ownBlueprint {
            return ownBlueprint
        }
        return song.blueprints.first { $0.id == instance.blueprintID }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top section: Track overview and section selector
            trackHeader
            
            // Middle section: Grid for current section
            if let blueprint = currentBlueprint, let instance = currentSection {
                sectionGrid(blueprint: blueprint, instance: instance)
                    .frame(maxHeight: .infinity)
            } else {
                emptyTrackView
                    .frame(maxHeight: .infinity)
            }
            
            // Bottom section: Chord builder
            chordBuilder
        }
        .navigationTitle("Track Editor: \(song.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)  // Hide bottom toolbar in track editor
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add Section") { showAddSection = true }
                    Button("Duplicate Current Section") { duplicateCurrentSection() }
                    Divider()
                    Button("Add Bar to Section") { addBarToCurrentSection() }
                    Button("Remove Bar from Section") { removeBarFromCurrentSection() }
                    Divider()
                    Button("Clean Track") { cleanTrack() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSection) {
            AddSectionView(song: song) { newSection in
                song.arrangement.append(newSection)
                selectedSectionIndex = song.arrangement.count - 1
            }
        }
    }
    
    // MARK: - Track Header
    
    private var trackHeader: some View {
        VStack(spacing: 8) {
            // Section selector - horizontal scrolling list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(song.arrangement.indices, id: \.self) { index in
                        let section = song.arrangement[index]
                        let blueprint = !section.isLinked && section.ownBlueprint != nil ? 
                                      section.ownBlueprint : 
                                      song.blueprints.first { $0.id == section.blueprintID }
                        
                        Button(action: { 
                            selectedSectionIndex = index 
                            selectedCell = 0
                        }) {
                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    if !section.isLinked {
                                        Image(systemName: "link.badge.minus")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                    }
                                    Text(section.displayName)
                                        .font(.caption)
                                        .fontWeight(selectedSectionIndex == index ? .bold : .regular)
                                }
                                if let bp = blueprint {
                                    Text("\(bp.bars) bars")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSectionIndex == index ? 
                                          Color.accentColor.opacity(0.2) : 
                                          Color(UIColor.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedSectionIndex == index ? 
                                           Color.accentColor : 
                                           Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if section.isLinked {
                                Button(action: { unlinkSection(at: index) }) {
                                    Label("Unlink from Original", systemImage: "link.badge.minus")
                                }
                            } else {
                                Button(action: { relinkSection(at: index) }) {
                                    Label("Re-link to Original", systemImage: "link")
                                }
                            }
                            Divider()
                            Button("Rename") {
                                // TODO: Add rename functionality
                            }
                            Button("Delete", role: .destructive) {
                                deleteSection(at: index)
                            }
                        }
                    }
                    
                    // Add section button
                    Button(action: { showAddSection = true }) {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 50)
            
            // Section info bar
            if let blueprint = currentBlueprint, let instance = currentSection {
                HStack {
                    // Show link status
                    if !instance.isLinked {
                        Label("Unlinked", systemImage: "link.badge.minus")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Text("\(blueprint.resolution.label) • \(song.timeSig.beatsPerBar)/\(song.timeSig.beatUnit)")
                        .font(.caption)
                    Spacer()
                    
                    // Bar count controls
                    HStack(spacing: 4) {
                        Button(action: { removeBarFromCurrentSection() }) {
                            Image(systemName: "minus.circle")
                                .imageScale(.small)
                        }
                        .disabled(blueprint.bars <= 1)
                        
                        Text("\(blueprint.bars) bars")
                            .font(.caption)
                            .frame(minWidth: 50)
                        
                        Button(action: { addBarToCurrentSection() }) {
                            Image(systemName: "plus.circle")
                                .imageScale(.small)
                        }
                    }
                    
                    Spacer()
                    Text("\(song.keySig.tonic.name(preferSharps: song.keySig.preferSharps)) \(song.keySig.mode.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
            
            Divider()
        }
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - Section Grid
    
    private func sectionGrid(blueprint: SectionBlueprint, instance: SectionInstance) -> some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 40
            let cellsPerBar = song.timeSig.beatsPerBar * blueprint.resolution.rawValue
            let cellWidth = min(80, availableWidth / CGFloat(cellsPerBar))
            let cellHeight: CGFloat = 28
            let columns = Array(repeating: GridItem(.fixed(cellWidth), spacing: 1), count: cellsPerBar)
            
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    // Section label with fixed height
                    Text(instance.displayName)
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(height: 35, alignment: .leading)
                    
                    // Grid bars
                    ForEach(0..<blueprint.bars, id: \.self) { bar in
                        buildBarGrid(
                            bar: bar, 
                            blueprint: blueprint,
                            columns: columns, 
                            cellWidth: cellWidth, 
                            cellHeight: cellHeight
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
            .scrollDisabled(scrollDisabled)  // Disable scrolling while dragging
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        handleDragChanged(value, cellWidth: cellWidth, cellHeight: cellHeight, blueprint: blueprint)
                    }
                    .onEnded { _ in
                        handleDragEnded(blueprint: blueprint)
                    }
            )
        }
    }
    
    @ViewBuilder
    private func buildBarGrid(bar: Int, blueprint: SectionBlueprint, columns: [GridItem], cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let cellsPerBar = song.timeSig.beatsPerBar * blueprint.resolution.rawValue
        
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(0..<cellsPerBar, id: \.self) { c in
                buildCell(bar: bar, cellIndex: c, blueprint: blueprint)
            }
        }
        .overlay(alignment: .leading) {
            Text("B\(bar+1)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 25, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func buildCell(bar: Int, cellIndex: Int, blueprint: SectionBlueprint) -> some View {
        let cellsPerBar = song.timeSig.beatsPerBar * blueprint.resolution.rawValue
        let tick = bar * cellsPerBar + cellIndex
        let isFirstCell = (cellIndex == 0)
        
        ZStack {
            cellBackground(isFirstCell: isFirstCell)
            cellContent(tick: tick, blueprint: blueprint)
            cellSelection(tick: tick)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDragging {
                tapCell(tick, blueprint: blueprint)
            }
        }
        .contextMenu {
            cellContextMenu(tick: tick, blueprint: blueprint)
        }
    }
    
    @ViewBuilder
    private func cellBackground(isFirstCell: Bool) -> some View {
        Rectangle()
            .strokeBorder(
                isFirstCell ? Color.primary : Color.secondary.opacity(0.2),
                lineWidth: isFirstCell ? 1.5 : 0.5
            )
            .background(
                isFirstCell ? Color.secondary.opacity(0.05) : Color.clear
            )
    }
    
    @ViewBuilder
    private func cellContent(tick: Int, blueprint: SectionBlueprint) -> some View {
        if let ev = eventCovering(tick, in: blueprint) {
            let label = chordLabel(ev)
            Rectangle()
                .fill(cellColour(for: ev))
                .opacity(0.20)
            Text(label)
                .font(.system(size: cellDisplayMode == .both ? 10 : 12, weight: .medium))
                .minimumScaleFactor(0.5)
                .lineLimit(cellDisplayMode == .both ? 2 : 1)
                .multilineTextAlignment(.center)
                .padding(2)
        }
    }
    
    @ViewBuilder
    private func cellSelection(tick: Int) -> some View {
        if draggedCells.contains(tick) {
            Rectangle()
                .stroke(.purple, lineWidth: 2)
        } else if isSelected(tick) {
            Rectangle()
                .stroke(.blue, lineWidth: 2)
        } else if tick == selectedCell {
            Rectangle()
                .stroke(.orange, lineWidth: 2)
        }
    }
    
    @ViewBuilder
    private func cellContextMenu(tick: Int, blueprint: SectionBlueprint) -> some View {
        if let ev = eventCovering(tick, in: blueprint) {
            Button("Edit \(ev.chord.displayName(preferSharps: song.keySig.preferSharps))") {
                // Edit event
            }
            Button("Delete \(ev.chord.displayName(preferSharps: song.keySig.preferSharps))", role: .destructive) {
                deleteEvent(ev, from: blueprint)
            }
        } else {
            Button("Add chord here") {
                selectedCell = tick
            }
            Button("Add rest here") {
                addRest(at: tick, in: blueprint)
            }
        }
    }
    
    // MARK: - Quick Add Chord Bar
    
    private var quickAddChordBar: some View {
        let usedChords = getUsedChords()
        
        return VStack(spacing: 0) {
            if !usedChords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(usedChords, id: \.self) { chord in
                            Button(action: {
                                buildingChord = chord
                                if let blueprint = currentBlueprint {
                                    applyChordToCell(chord: chord, length: 1, autoAdvance: false, blueprint: blueprint)
                                }
                            }) {
                                Text(chord.displayName(preferSharps: song.keySig.preferSharps))
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(buildingChord == chord ? 
                                                  Color.accentColor.opacity(0.3) : 
                                                  Color(UIColor.secondarySystemFill))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15)
                                            .stroke(buildingChord == chord ? 
                                                   Color.accentColor : 
                                                   Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(height: 44)
                
                Divider()
            }
            
            // Debug info bar (if dragging or debug message)
            if isDragging || debugMessage != "" {
                HStack {
                    if isDragging {
                        Label("Dragging", systemImage: "hand.draw.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    
                    if debugMessage != "" {
                        Text(debugMessage)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }
    
    private func getUsedChords() -> [Chord] {
        var chordSet = Set<Chord>()
        
        // Collect all unique chords from all blueprints
        for blueprint in song.blueprints {
            for event in blueprint.events {
                if !event.isRest {
                    chordSet.insert(event.chord)
                }
            }
        }
        
        // Sort by root note and quality for consistent ordering
        return Array(chordSet).sorted { chord1, chord2 in
            if chord1.root.rawValue != chord2.root.rawValue {
                return chord1.root.rawValue < chord2.root.rawValue
            }
            return chord1.quality.rawValue < chord2.quality.rawValue
        }
    }
    
    // MARK: - Empty Track View
    
    private var emptyTrackView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No sections in track")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Add First Section") {
                showAddSection = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Chord Builder (at bottom)
    
    private var chordBuilder: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Quick-add chord pills
            quickAddChordBar
            
            // Chord builder bar
            if currentBlueprint != nil {
                ChordBuilderBar(
                    currentChord: $buildingChord,
                    currentCell: $selectedCell,
                    song: song,
                    onApply: { chord, shouldAdvance in
                        if let blueprint = currentBlueprint {
                            applyChordToCell(chord: chord, length: 1, autoAdvance: shouldAdvance, blueprint: blueprint)
                        }
                    },
                    onDelete: {
                        if let blueprint = currentBlueprint {
                            deleteCurrentCellChord(blueprint: blueprint)
                        }
                    },
                    onRest: {
                        if let blueprint = currentBlueprint {
                            quickAddRest(blueprint: blueprint)
                        }
                    },
                    displayMode: $cellDisplayMode
                )
            }
        }
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - Helper Functions
    
    private func eventCovering(_ tick: Int, in blueprint: SectionBlueprint) -> ChordEvent? {
        blueprint.events.first { ev in
            tick >= ev.startTick && tick < ev.startTick + ev.lengthTicks
        }
    }
    
    private func isSelected(_ tick: Int) -> Bool {
        guard let s = selectionStart else { return false }
        let e = selectionEnd ?? s
        return tick >= min(s,e) && tick <= max(s,e)
    }
    
    private func tapCell(_ tick: Int, blueprint: SectionBlueprint) {
        let cellsPerBar = song.timeSig.beatsPerBar * blueprint.resolution.rawValue
        let bar = tick / cellsPerBar
        let cellInBar = tick % cellsPerBar
        
        print("[TAP] Tapped cell at tick \(tick) (Bar \(bar + 1), Cell \(cellInBar + 1))")
        selectedCell = tick
        
        if let ev = eventCovering(tick, in: blueprint) {
            buildingChord = ev.chord
            debugMessage = "B\(bar + 1)C\(cellInBar + 1): \(ev.chord.displayName(preferSharps: true))"
        } else {
            buildingChord = nil
            debugMessage = "B\(bar + 1)C\(cellInBar + 1): empty"
        }
        
        selectionStart = tick
        selectionEnd = tick
    }
    
    private func getCellFromLocation(_ location: CGPoint, cellWidth: CGFloat, cellHeight: CGFloat) -> Int {
        // Account for ScrollView padding and section label
        let sectionLabelHeight: CGFloat = 35 // Approximate height of section label + padding
        let horizontalPadding: CGFloat = 4 // ScrollView horizontal padding
        let barLabelWidth: CGFloat = 25 // Width of "B1" labels
        let cellSpacing: CGFloat = 1 // Spacing between cells
        let barSpacing: CGFloat = 4 // Spacing between bars
        
        // Adjust coordinates
        let adjustedY = max(0, location.y - sectionLabelHeight)
        let adjustedX = max(0, location.x - horizontalPadding - barLabelWidth)
        
        // Calculate which bar we're in
        let barHeight = cellHeight + barSpacing
        let bar = Int(adjustedY / barHeight)
        
        // Calculate which cell within the bar
        let cellTotalWidth = cellWidth + cellSpacing
        let cellInBar = Int(adjustedX / cellTotalWidth)
        
        guard let blueprint = currentBlueprint else { return 0 }
        let cellsPerBar = song.timeSig.beatsPerBar * blueprint.resolution.rawValue
        
        // Clamp cellInBar to valid range
        let clampedCellInBar = min(max(0, cellInBar), cellsPerBar - 1)
        
        // Calculate final cell index
        let cellIndex = bar * cellsPerBar + clampedCellInBar
        let totalTicks = blueprint.totalTicks(beatsPerBar: song.timeSig.beatsPerBar)
        
        // Debug logging
        print("[CELL CALC] location: \(location), adjustedY: \(adjustedY), adjustedX: \(adjustedX)")
        print("[CELL CALC] bar: \(bar), cellInBar: \(cellInBar), cellIndex: \(cellIndex)")
        
        return min(max(0, cellIndex), totalTicks - 1)
    }
    
    private func handleDragChanged(_ value: DragGesture.Value, cellWidth: CGFloat, cellHeight: CGFloat, blueprint: SectionBlueprint) {
        let cellIndex = getCellFromLocation(value.location, cellWidth: cellWidth, cellHeight: cellHeight)
        let cellsPerBar = song.timeSig.beatsPerBar * blueprint.resolution.rawValue
        let bar = cellIndex / cellsPerBar
        let cellInBar = cellIndex % cellsPerBar
        
        if !isDragging {
            print("[DRAG] Started at cell \(cellIndex) (Bar \(bar + 1), Cell \(cellInBar + 1))")
            isDragging = true
            scrollDisabled = true  // Disable scrolling when drag starts
            dragStartCell = cellIndex
            dragCurrentCell = cellIndex
            draggedCells = [cellIndex]
            selectionStart = cellIndex
            selectionEnd = cellIndex
            
            // Store the chord from the starting cell for drag-to-extend
            if let event = eventCovering(cellIndex, in: blueprint) {
                dragChord = event.chord
                print("[DRAG] Using chord from starting cell: \(event.chord.displayName(preferSharps: true))")
                debugMessage = "Extending \(event.chord.displayName(preferSharps: true))"
            } else {
                dragChord = nil
                debugMessage = "Drag at B\(bar + 1)C\(cellInBar + 1)"
            }
        } else if cellIndex != dragCurrentCell {
            print("[DRAG] Moved to cell \(cellIndex) (Bar \(bar + 1), Cell \(cellInBar + 1))")
            dragCurrentCell = cellIndex
            
            if let start = dragStartCell {
                let minCell = min(start, cellIndex)
                let maxCell = max(start, cellIndex)
                draggedCells = Set(minCell...maxCell)
                selectionEnd = cellIndex
                let length = maxCell - minCell + 1
                
                let startBar = minCell / cellsPerBar
                let startCellInBar = minCell % cellsPerBar
                let endBar = maxCell / cellsPerBar
                let endCellInBar = maxCell % cellsPerBar
                
                debugMessage = "B\(startBar + 1)C\(startCellInBar + 1) to B\(endBar + 1)C\(endCellInBar + 1) (\(length) cells)"
            }
        }
    }
    
    private func handleDragEnded(blueprint: SectionBlueprint) {
        if let start = dragStartCell, let end = dragCurrentCell {
            let minTick = min(start, end)
            let maxTick = max(start, end)
            let length = maxTick - minTick + 1
            
            print("[DRAG] Ended. Start: \(start), End: \(end), Length: \(length)")
            
            if length > 1 {
                selectedCell = minTick
                selectionStart = minTick
                selectionEnd = maxTick
                
                // Use the chord from the starting cell if available, otherwise use buildingChord
                if let chord = dragChord {
                    applyChordToCell(chord: chord, length: length, autoAdvance: false, blueprint: blueprint)
                    debugMessage = "Extended \(chord.displayName(preferSharps: true)) across \(length) cells"
                } else if let chord = buildingChord {
                    applyChordToCell(chord: chord, length: length, autoAdvance: false, blueprint: blueprint)
                    debugMessage = "Applied \(chord.displayName(preferSharps: true)) across \(length) cells"
                } else {
                    debugMessage = "Selected \(length) cells - choose a chord to apply"
                }
            } else {
                selectedCell = start
                if let ev = eventCovering(start, in: blueprint) {
                    buildingChord = ev.chord
                }
            }
        }
        
        isDragging = false
        scrollDisabled = false  // Re-enable scrolling when drag ends
        dragStartCell = nil
        dragCurrentCell = nil
        draggedCells = []
        dragChord = nil  // Clear the stored drag chord
    }
    
    private func chordLabel(_ ev: ChordEvent) -> String {
        if ev.isRest { return "Rest" }
        let key = song.keySig
        let name = ev.chord.displayName(preferSharps: key.preferSharps, capo: song.capo, showShapesWithCapo: song.capo > 0 && cellDisplayMode != .roman)
        let roman = Roman.roman(for: ev.chord, in: key)
        switch cellDisplayMode {
        case .chord: return name
        case .roman: return roman
        case .both: return "\(roman)\n\(name)"
        }
    }
    
    private func cellColour(for ev: ChordEvent) -> Color {
        guard colourByFunction, !ev.isRest else { return .accentColor }
        let offset = (ev.chord.root.rawValue - song.keySig.tonic.rawValue + 12) % 12
        let (idx, _) = Roman.degree(for: offset, mode: song.keySig.mode)
        let palette: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink]
        return palette[idx % palette.count]
    }
    
    // MARK: - Track Management
    
    private func unlinkSection(at index: Int) {
        guard index < song.arrangement.count else { return }
        let section = song.arrangement[index]
        
        // Only unlink if currently linked
        guard section.isLinked else { return }
        
        // Find the original blueprint
        guard let originalBlueprint = song.blueprints.first(where: { $0.id == section.blueprintID }) else { return }
        
        // Create a deep copy of the blueprint
        let newBlueprint = SectionBlueprint(
            name: "\(originalBlueprint.name) (Unlinked)",
            bars: originalBlueprint.bars,
            resolution: originalBlueprint.resolution,
            defaultKeyOverride: originalBlueprint.defaultKeyOverride
        )
        
        // Copy all events
        for event in originalBlueprint.events {
            let newEvent = ChordEvent(
                startTick: event.startTick,
                lengthTicks: event.lengthTicks,
                isRest: event.isRest,
                chord: event.chord
            )
            newBlueprint.events.append(newEvent)
        }
        
        // Set the section's own blueprint and mark as unlinked
        section.ownBlueprint = newBlueprint
        section.isLinked = false
        
        debugMessage = "Unlinked \(section.displayName)"
    }
    
    private func relinkSection(at index: Int) {
        guard index < song.arrangement.count else { return }
        let section = song.arrangement[index]
        
        // Only relink if currently unlinked
        guard !section.isLinked else { return }
        
        // Delete the own blueprint and relink to original
        if let ownBlueprint = section.ownBlueprint {
            // Find the index and remove it
            if let bpIndex = song.blueprints.firstIndex(where: { $0.id == ownBlueprint.id }) {
                song.blueprints.remove(at: bpIndex)
            }
            context.delete(ownBlueprint)
        }
        
        section.ownBlueprint = nil
        section.isLinked = true
        
        debugMessage = "Re-linked \(section.displayName)"
    }
    
    private func deleteSection(at index: Int) {
        guard index < song.arrangement.count else { return }
        let section = song.arrangement[index]
        
        // If unlinked, delete its own blueprint
        if !section.isLinked, let ownBlueprint = section.ownBlueprint {
            context.delete(ownBlueprint)
        }
        
        song.arrangement.remove(at: index)
        
        // Adjust selected index if needed
        if selectedSectionIndex >= song.arrangement.count {
            selectedSectionIndex = max(0, song.arrangement.count - 1)
        }
    }
    
    private func duplicateCurrentSection() {
        guard let currentSection = currentSection else { return }
        
        let newSection = SectionInstance(
            displayName: "\(currentSection.displayName) (copy)",
            repeats: currentSection.repeats,
            keyOverride: currentSection.keyOverride,
            lyrics: currentSection.lyrics,
            blueprintID: currentSection.blueprintID
        )
        
        let insertIndex = selectedSectionIndex + 1
        song.arrangement.insert(newSection, at: insertIndex)
        selectedSectionIndex = insertIndex
    }
    
    private func addBarToCurrentSection() {
        guard let blueprint = currentBlueprint else { return }
        blueprint.bars += 1
        debugMessage = "Added bar - now \(blueprint.bars) bars"
    }
    
    private func removeBarFromCurrentSection() {
        guard let blueprint = currentBlueprint, blueprint.bars > 1 else { return }
        
        // Remove events in the last bar
        let cellsPerBar = song.timeSig.beatsPerBar * blueprint.resolution.rawValue
        let lastBarStart = (blueprint.bars - 1) * cellsPerBar
        
        let eventsToRemove = blueprint.events.filter { ev in
            ev.startTick >= lastBarStart
        }
        
        for ev in eventsToRemove {
            if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
                blueprint.events.remove(at: index)
                context.delete(ev)
            }
        }
        
        blueprint.bars -= 1
        debugMessage = "Removed bar - now \(blueprint.bars) bars"
    }
    
    private func cleanTrack() {
        for blueprint in song.blueprints {
            cleanDuplicateEvents(in: blueprint)
        }
    }
    
    private func cleanDuplicateEvents(in blueprint: SectionBlueprint) {
        var seen = Set<UUID>()
        var toRemove: [ChordEvent] = []
        
        for event in blueprint.events {
            if seen.contains(event.id) {
                toRemove.append(event)
            } else {
                seen.insert(event.id)
            }
        }
        
        for event in toRemove {
            if let index = blueprint.events.firstIndex(where: { $0.id == event.id }) {
                blueprint.events.remove(at: index)
                context.delete(event)
            }
        }
    }
    
    // MARK: - Chord Application
    
    private func applyChordToCell(chord: Chord, length: Int = 1, autoAdvance: Bool = false, blueprint: SectionBlueprint) {
        print("[APPLY] Applying chord \(chord.displayName(preferSharps: true)) to cell \(selectedCell) with length \(length)")
        
        removeOverlappingEvents(from: selectedCell, to: selectedCell + length - 1, in: blueprint)
        
        let newEvent = ChordEvent(startTick: selectedCell, lengthTicks: length, isRest: false, chord: chord)
        blueprint.events.append(newEvent)
        
        if autoAdvance {
            let totalTicks = blueprint.totalTicks(beatsPerBar: song.timeSig.beatsPerBar)
            selectedCell = min(selectedCell + 1, totalTicks - 1)
            buildingChord = nil
        }
    }
    
    private func removeOverlappingEvents(from startTick: Int, to endTick: Int, in blueprint: SectionBlueprint) {
        let overlapping = blueprint.events.filter { ev in
            let evEnd = ev.startTick + ev.lengthTicks - 1
            return (ev.startTick <= endTick && evEnd >= startTick)
        }
        
        for ev in overlapping {
            let evEnd = ev.startTick + ev.lengthTicks - 1
            
            if ev.startTick < startTick {
                ev.lengthTicks = startTick - ev.startTick
            } else if evEnd > endTick {
                let newEvent = ChordEvent(
                    startTick: endTick + 1,
                    lengthTicks: evEnd - endTick,
                    isRest: ev.isRest,
                    chord: ev.chord
                )
                blueprint.events.append(newEvent)
                
                if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
                    blueprint.events.remove(at: index)
                    context.delete(ev)
                }
            } else {
                if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
                    blueprint.events.remove(at: index)
                    context.delete(ev)
                }
            }
        }
    }
    
    private func deleteEvent(_ ev: ChordEvent, from blueprint: SectionBlueprint) {
        if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
            blueprint.events.remove(at: index)
            context.delete(ev)
        }
    }
    
    private func deleteCurrentCellChord(blueprint: SectionBlueprint) {
        if let event = eventCovering(selectedCell, in: blueprint) {
            deleteEvent(event, from: blueprint)
            debugMessage = "Deleted chord at cell \(selectedCell + 1)"
        }
    }
    
    private func quickAddRest(blueprint: SectionBlueprint) {
        removeOverlappingEvents(from: selectedCell, to: selectedCell, in: blueprint)
        let rest = ChordEvent(startTick: selectedCell, lengthTicks: 1, isRest: true, chord: .defaultMajC)
        blueprint.events.append(rest)
        
        let totalTicks = blueprint.totalTicks(beatsPerBar: song.timeSig.beatsPerBar)
        selectedCell = min(selectedCell + 1, totalTicks - 1)
    }
    
    private func addRest(at tick: Int, in blueprint: SectionBlueprint) {
        removeOverlappingEvents(from: tick, to: tick, in: blueprint)
        let ev = ChordEvent(startTick: tick, lengthTicks: 1, isRest: true, chord: .defaultMajC)
        blueprint.events.append(ev)
    }
}

// MARK: - Add Section View

struct AddSectionView: View {
    let song: Song
    let onAdd: (SectionInstance) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedBlueprint: SectionBlueprint? = nil
    @State private var displayName = ""
    @State private var createNew = false
    @State private var newBlueprintName = "New Section"
    @State private var newBars = 4
    @State private var newResolution: GridResolution = .beat
    
    var body: some View {
        NavigationStack {
            Form {
                if !createNew {
                    Section("Use Existing Section") {
                        ForEach(song.blueprints) { blueprint in
                            Button(action: {
                                selectedBlueprint = blueprint
                                displayName = blueprint.name
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(blueprint.name)
                                            .foregroundColor(.primary)
                                        Text("\(blueprint.bars) bars, \(blueprint.resolution.label)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedBlueprint?.id == blueprint.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                        
                        Button("Create New Section Type") {
                            createNew = true
                        }
                        .foregroundColor(.accentColor)
                    }
                } else {
                    Section("Create New Section Type") {
                        TextField("Section Name", text: $newBlueprintName)
                        
                        HStack {
                            Text("Bars:")
                            Stepper("\(newBars)", value: $newBars, in: 1...128)
                        }
                        
                        Picker("Resolution", selection: $newResolution) {
                            ForEach(GridResolution.allCases) { res in
                                Text(res.label).tag(res)
                            }
                        }
                        
                        Button("Use Existing Section Instead") {
                            createNew = false
                        }
                        .foregroundColor(.accentColor)
                    }
                }
                
                Section("Instance Details") {
                    TextField("Display Name", text: $displayName)
                        .placeholder(when: displayName.isEmpty) {
                            Text(createNew ? newBlueprintName : (selectedBlueprint?.name ?? "Section"))
                                .foregroundColor(.secondary)
                        }
                }
            }
            .navigationTitle("Add Section")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if createNew {
                            let blueprint = SectionBlueprint(
                                name: newBlueprintName,
                                bars: newBars,
                                resolution: newResolution
                            )
                            song.blueprints.append(blueprint)
                            
                            let instance = SectionInstance(
                                displayName: displayName.isEmpty ? newBlueprintName : displayName,
                                blueprintID: blueprint.id
                            )
                            onAdd(instance)
                        } else if let blueprint = selectedBlueprint {
                            let instance = SectionInstance(
                                displayName: displayName.isEmpty ? blueprint.name : displayName,
                                blueprintID: blueprint.id
                            )
                            onAdd(instance)
                        }
                        dismiss()
                    }
                    .disabled(!createNew && selectedBlueprint == nil)
                }
            }
        }
    }
}

// Helper for placeholder text
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}