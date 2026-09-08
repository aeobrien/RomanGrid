import SwiftUI
import SwiftData

struct SectionGridEditor: View {
    @Environment(\.modelContext) private var context
    var song: Song
    @Bindable var blueprint: SectionBlueprint
    @AppStorage("colourByFunction") var colourByFunction: Bool = true
    
    @State private var selectionStart: Int? = nil
    @State private var selectionEnd: Int? = nil
    @State private var editingEvent: ChordEvent? = nil
    @State private var showCoverageWarning: Bool = false
    @State private var currentCell: Int = 0
    @State private var debugMessage: String = ""
    @State private var buildingChord: Chord? = nil
    @State private var isDragging = false
    @State private var dragStartCell: Int? = nil
    @State private var dragCurrentCell: Int? = nil
    @State private var draggedCells: Set<Int> = []
    @State private var cellDisplayMode: CellDisplayMode = .chord
    
    var totalTicks: Int { blueprint.totalTicks(beatsPerBar: song.timeSig.beatsPerBar) }
    var cellsPerBar: Int { song.timeSig.beatsPerBar * blueprint.resolution.rawValue }
    
    var body: some View {
        VStack(spacing: 4) {
            header
            chordBuilderBar
            grid
            footer
        }
        .navigationTitle("\(blueprint.name) • \(blueprint.bars) bars")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Auto-extend") {
                    Button("To end of bar") { extendSelection(toBarsAhead: 0) }.disabled(selectionStart == nil)
                    Button("To end of next bar") { extendSelection(toBarsAhead: 1) }.disabled(selectionStart == nil)
                    
                    Spacer()
                    
                    Button(action: { fillGapsWithRests() }) {
                        Text("Fill gaps")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { cleanDuplicateEvents() }) {
                        Text("Clean")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                }
            }
        }
        .onAppear {
            cleanDuplicateEvents()
        }
    }
    
    private var header: some View {
        HStack {
            Text("\(blueprint.resolution.label) • \(song.timeSig.beatsPerBar)/\(song.timeSig.beatUnit)")
                .font(.caption)
            Spacer()
            Text("\(song.keySig.tonic.name(preferSharps: song.keySig.preferSharps)) \(song.keySig.mode.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }
    
    private var footer: some View {
        HStack {
            if debugMessage != "" {
                Text(debugMessage)
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            
            Spacer()
            
            // Display mode picker as dropdown
            Picker("Display", selection: $cellDisplayMode) {
                ForEach(CellDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private var chordBuilderBar: some View {
        ChordBuilderBar(
            currentChord: $buildingChord,
            currentCell: $currentCell,
            song: song,
            effectiveKey: song.keySig.transposed(semitones: song.transposition),
            onApply: { chord, shouldAdvance in
                // Check if this is just a dummy chord for advancing
                if chord.root == .C && chord.quality == .maj && chord.flags.isEmpty && buildingChord == nil {
                    // Just advance without applying
                    currentCell = min(currentCell + 1, totalTicks - 1)
                } else {
                    applyChordToCell(chord: chord, length: 1, autoAdvance: shouldAdvance)
                }
            },
            onDelete: {
                deleteCurrentCellChord()
            },
            onRest: {
                quickAddRest()
            },
            displayMode: $cellDisplayMode
        )
        .onAppear {
            // Load the chord from the first cell when view appears
            if let event = eventCovering(0) {
                buildingChord = event.chord
            }
        }
    }
    
    // Old chord bar removed - replaced with ChordBuilderBar
    
    private var grid: some View {
        // Use fixed size cells that fit on screen
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 40 // Account for padding and bar labels
            let cellWidth = min(80, availableWidth / CGFloat(cellsPerBar))
            let cellHeight: CGFloat = 28
            let columns = Array(repeating: GridItem(.fixed(cellWidth), spacing: 1), count: cellsPerBar)
            
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<blueprint.bars, id: \.self) { bar in
                        buildBarGrid(bar: bar, columns: columns, cellWidth: cellWidth, cellHeight: cellHeight)
                    }
                }
            }
            .padding(.horizontal, 4)
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        handleDragChanged(value, cellWidth: cellWidth, cellHeight: cellHeight)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
        }
    }
    
    private func getCellFromLocation(_ location: CGPoint, cellWidth: CGFloat, cellHeight: CGFloat) -> Int {
        let x = max(0, location.x - 4) // Account for horizontal padding
        let y = max(0, location.y)
        
        // Calculate which bar we're in (accounting for spacing between bars and bar grid height)
        let barHeight = cellHeight + 4 // cell height + vertical spacing between bars
        let bar = Int(y / barHeight)
        
        // Calculate which cell within the bar (account for label width)
        let adjustedX = x - 25 // Subtract bar label width
        let cellInBar = Int(max(0, adjustedX) / (cellWidth + 1)) // Add spacing between cells
        let cellIndex = bar * cellsPerBar + min(cellInBar, cellsPerBar - 1)
        
        return min(max(0, cellIndex), totalTicks - 1)
    }
    
    private func handleDragChanged(_ value: DragGesture.Value, cellWidth: CGFloat, cellHeight: CGFloat) {
        let cellIndex = getCellFromLocation(value.location, cellWidth: cellWidth, cellHeight: cellHeight)
        
        if !isDragging {
            print("[DRAG] Started at cell \(cellIndex)")
            isDragging = true
            dragStartCell = cellIndex
            dragCurrentCell = cellIndex
            draggedCells = [cellIndex]
            selectionStart = cellIndex
            selectionEnd = cellIndex
            debugMessage = "Drag started at cell \(cellIndex + 1)"
        } else if cellIndex != dragCurrentCell {
            print("[DRAG] Moved to cell \(cellIndex)")
            dragCurrentCell = cellIndex
            
            // Update dragged cells set
            if let start = dragStartCell {
                let minCell = min(start, cellIndex)
                let maxCell = max(start, cellIndex)
                draggedCells = Set(minCell...maxCell)
                selectionEnd = cellIndex
                let length = maxCell - minCell + 1
                debugMessage = "Selecting \(length) cells (\(minCell + 1) to \(maxCell + 1))"
            }
        }
    }
    
    private func handleDragEnded() {
        if let start = dragStartCell, let end = dragCurrentCell {
            let minTick = min(start, end)
            let maxTick = max(start, end)
            let length = maxTick - minTick + 1
            
            print("[DRAG] Ended. Start: \(start), End: \(end), Length: \(length)")
            
            if length > 1 {
                currentCell = minTick
                selectionStart = minTick
                selectionEnd = maxTick
                
                if let chord = buildingChord {
                    applyChordToCell(chord: chord, length: length, autoAdvance: false)
                    debugMessage = "Applied chord across \(length) cells"
                } else {
                    debugMessage = "Selected \(length) cells - choose a chord to apply"
                }
            } else {
                // Single cell - just select it
                currentCell = start
                if let ev = eventCovering(start) {
                    buildingChord = ev.chord
                }
            }
        }
        
        isDragging = false
        dragStartCell = nil
        dragCurrentCell = nil
        draggedCells = []
    }
    
    @ViewBuilder
    private func buildBarGrid(bar: Int, columns: [GridItem], cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(0..<cellsPerBar, id: \.self) { c in
                buildCell(bar: bar, cellIndex: c)
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
    private func buildCell(bar: Int, cellIndex: Int) -> some View {
        let tick = bar * cellsPerBar + cellIndex
        let isFirstCell = (cellIndex == 0)
        
        ZStack {
            cellBackground(isFirstCell: isFirstCell)
            cellContent(tick: tick)
            cellSelection(tick: tick)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDragging {
                tapCell(tick)
            }
        }
        .contextMenu {
            cellContextMenu(tick: tick)
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
    private func cellContent(tick: Int) -> some View {
        if let ev = eventCovering(tick) {
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
        } else if tick == currentCell {
            Rectangle()
                .stroke(.orange, lineWidth: 2)
        }
    }
    
    @ViewBuilder
    private func cellContextMenu(tick: Int) -> some View {
        if let ev = eventCovering(tick) {
            Button("Edit \(ev.chord.displayName(preferSharps: song.keySig.preferSharps))") {
                debugMessage = "Editing event at tick \(tick)"
                editingEvent = ev
            }
            Button("Delete \(ev.chord.displayName(preferSharps: song.keySig.preferSharps))", role: .destructive) {
                deleteEvent(ev)
            }
            if ev.startTick == tick {
                Button("Extend to end of bar") { extendEvent(ev, toBarsAhead: 0) }
                Button("Extend to end of next bar") { extendEvent(ev, toBarsAhead: 1) }
            }
        } else {
            // Check if we have a multi-cell selection
            if let s = selectionStart, let e = selectionEnd, s != e {
                Button("Create chord from selection (\(abs(e-s)+1) cells)") {
                    applyChordToSelection()
                }
                Divider()
            }
            Button("Add chord here") {
                debugMessage = "Adding chord at tick \(tick)"
                addChord(at: tick)
            }
            Button("Add rest here") {
                debugMessage = "Adding rest at tick \(tick)"
                addRest(at: tick)
            }
            if selectionStart != nil {
                Divider()
                Button("Clear selection") {
                    selectionStart = nil
                    selectionEnd = nil
                    debugMessage = "Selection cleared"
                }
            }
        }
    }
    
    private func deleteEvent(_ ev: ChordEvent) {
        debugMessage = "Deleting event: \(ev.chord.displayName(preferSharps: song.keySig.preferSharps))"
        print("[DELETE] Attempting to delete event: \(ev.id)")
        print("[DELETE] Events before: \(blueprint.events.count)")
        
        if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
            let removed = blueprint.events.remove(at: index)
            context.delete(removed)
            print("[DELETE] Removed event at index \(index)")
            print("[DELETE] Events after: \(blueprint.events.count)")
            debugMessage = "Deleted successfully"
        } else {
            debugMessage = "Failed to find event!"
            print("[DELETE] WARNING: Could not find event in array!")
        }
    }
    
    private func isSelected(_ tick: Int) -> Bool {
        guard let s = selectionStart else { return false }
        let e = selectionEnd ?? s
        return tick >= min(s,e) && tick <= max(s,e)
    }
    
    private func tapCell(_ tick: Int) {
        print("[TAP] Tapped cell at tick \(tick)")
        currentCell = tick
        
        if let ev = eventCovering(tick) {
            print("[TAP] Cell has event: \(ev.chord.displayName(preferSharps: true)), start: \(ev.startTick), length: \(ev.lengthTicks)")
            // Load the chord into the builder
            buildingChord = ev.chord
            debugMessage = "Selected: \(ev.chord.displayName(preferSharps: true))"
        } else {
            // Empty cell - reset to neutral
            buildingChord = nil
            debugMessage = "Cell \(tick + 1): empty"
        }
        
        // Start selection here for potential drag
        selectionStart = tick
        selectionEnd = tick
    }
    
    private func dragOver(_ tick: Int) {
        // Extend selection as we drag
        if selectionStart != nil {
            selectionEnd = tick
            let start = min(selectionStart!, tick)
            let end = max(selectionStart!, tick)
            let length = end - start + 1
            debugMessage = "Drag to extend: \(length) cells"
            
            // Update current cell to the start of selection
            currentCell = start
        }
    }
    
    private func applyChordToSelection() {
        guard let s = selectionStart, let e = selectionEnd else { return }
        let start = min(s, e)
        let length = max(1, abs(e - s) + 1)
        
        // Update current cell to the start of the selection
        currentCell = start
        
        // Only apply if we have a chord selected
        if let chord = buildingChord {
            // Apply the chord with the dragged length
            applyChordToCell(chord: chord, length: length, autoAdvance: false)
            debugMessage = "Applied \(chord.displayName(preferSharps: song.keySig.preferSharps)) for \(length) cells"
        }
        
        // Clear selection
        selectionStart = nil
        selectionEnd = nil
    }
    
    private func addChord(at tick: Int) {
        print("[ADD] Adding chord at tick \(tick)")
        removeOverlappingEvents(from: tick, to: tick)
        let ev = ChordEvent(startTick: tick, lengthTicks: 1, isRest: false, chord: .defaultMajC)
        blueprint.events.append(ev)
        print("[ADD] Created event ID: \(ev.id), total events: \(blueprint.events.count)")
        debugMessage = "Added chord at tick \(tick)"
        editingEvent = ev
    }
    
    private func addRest(at tick: Int) {
        removeOverlappingEvents(from: tick, to: tick)
        let ev = ChordEvent(startTick: tick, lengthTicks: 1, isRest: true, chord: .defaultMajC)
        blueprint.events.append(ev)
    }
    
    private func extendSelection(toBarsAhead: Int) {
        guard let s = selectionStart else { return }
        let currentBar = s / cellsPerBar
        let endBar = min(blueprint.bars-1, currentBar + toBarsAhead)
        let endTick = (endBar+1)*cellsPerBar - 1
        selectionEnd = endTick
        applyChordToSelection()
    }
    
    private func eventCovering(_ tick: Int) -> ChordEvent? {
        blueprint.events.first { ev in
            tick >= ev.startTick && tick < ev.startTick + ev.lengthTicks
        }
    }
    
    private func eventStarting(at tick: Int) -> ChordEvent? {
        blueprint.events.first { $0.startTick == tick }
    }
    
    private func extendEvent(_ ev: ChordEvent, toBarsAhead: Int) {
        let currentBar = ev.startTick / cellsPerBar
        let endBar = min(blueprint.bars-1, currentBar + toBarsAhead)
        let endTick = (endBar+1)*cellsPerBar - 1
        ev.lengthTicks = max(1, endTick - ev.startTick + 1)
    }
    
    private func hasGapsOrOverlaps() -> Bool {
        var cover = Array(repeating: 0, count: totalTicks)
        for ev in blueprint.events {
            let end = min(totalTicks, ev.startTick + ev.lengthTicks)
            if ev.startTick < 0 || end > totalTicks { return true }
            for i in ev.startTick..<end { cover[i] += 1 }
        }
        return cover.contains(0) || cover.contains(where: { $0 > 1 })
    }
    
    private func fillGapsWithRests() {
        var occupied = Array(repeating: false, count: totalTicks)
        for ev in blueprint.events {
            for i in ev.startTick..<min(totalTicks, ev.startTick + ev.lengthTicks) {
                if i >= 0 { occupied[i] = true }
            }
        }
        var i = 0
        while i < totalTicks {
            if !occupied[i] {
                var j = i+1
                while j < totalTicks && !occupied[j] { j += 1 }
                blueprint.events.append(ChordEvent(startTick: i, lengthTicks: j - i, isRest: true))
                i = j
            } else {
                i += 1
            }
        }
    }
    
    private func cleanDuplicateEvents() {
        print("[CLEAN] Starting duplicate cleanup")
        var seen = Set<UUID>()
        var toRemove: [ChordEvent] = []
        
        // Find duplicates
        for event in blueprint.events {
            if seen.contains(event.id) {
                toRemove.append(event)
            } else {
                seen.insert(event.id)
            }
        }
        
        // Find overlapping events at same position
        for i in 0..<blueprint.events.count {
            for j in (i+1)..<blueprint.events.count {
                let ev1 = blueprint.events[i]
                let ev2 = blueprint.events[j]
                if ev1.startTick == ev2.startTick && !toRemove.contains(where: { $0.id == ev1.id }) {
                    // Keep the later one
                    toRemove.append(ev1)
                }
            }
        }
        
        // Remove duplicates
        for event in toRemove {
            if let index = blueprint.events.firstIndex(where: { $0.id == event.id }) {
                blueprint.events.remove(at: index)
                context.delete(event)
                print("[CLEAN] Removed duplicate event at index \(index)")
            }
        }
        
        print("[CLEAN] Removed \(toRemove.count) duplicate events")
        debugMessage = "Cleaned \(toRemove.count) duplicates"
    }
    
    private func removeOverlappingEvents(from startTick: Int, to endTick: Int) {
        print("[REMOVE] Removing overlapping events from tick \(startTick) to \(endTick)")
        let overlapping = blueprint.events.filter { ev in
            let evEnd = ev.startTick + ev.lengthTicks - 1
            return (ev.startTick <= endTick && evEnd >= startTick)
        }
        
        for ev in overlapping {
            let evEnd = ev.startTick + ev.lengthTicks - 1
            print("[REMOVE] Found overlapping event: start=\(ev.startTick), end=\(evEnd), chord=\(ev.chord.displayName(preferSharps: true))")
            
            // If this event extends before our range, truncate it
            if ev.startTick < startTick {
                print("[REMOVE] Truncating event that starts before our range")
                ev.lengthTicks = startTick - ev.startTick
                print("[REMOVE] Event now ends at tick \(ev.startTick + ev.lengthTicks - 1)")
            }
            // If this event extends after our range, create a new event for the part after
            else if evEnd > endTick {
                print("[REMOVE] Splitting event that extends past our range")
                let newEvent = ChordEvent(
                    startTick: endTick + 1,
                    lengthTicks: evEnd - endTick,
                    isRest: ev.isRest,
                    chord: ev.chord
                )
                blueprint.events.append(newEvent)
                print("[REMOVE] Created new event from tick \(newEvent.startTick) to \(newEvent.startTick + newEvent.lengthTicks - 1)")
                
                // Remove the original event
                if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
                    blueprint.events.remove(at: index)
                    context.delete(ev)
                }
            }
            // Event is completely within our range, remove it
            else {
                print("[REMOVE] Removing event completely within our range")
                if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
                    blueprint.events.remove(at: index)
                    context.delete(ev)
                }
            }
        }
    }
    
    private func printAllEvents() {
        print("[DEBUG] === ALL EVENTS IN BLUEPRINT ===")
        print("[DEBUG] Total events: \(blueprint.events.count)")
        for (index, event) in blueprint.events.enumerated() {
            let chordName = event.isRest ? "REST" : event.chord.displayName(preferSharps: true)
            print("[DEBUG] Event \(index): ID=\(String(event.id.uuidString.prefix(8))), start=\(event.startTick), length=\(event.lengthTicks), chord=\(chordName)")
        }
        print("[DEBUG] === END OF EVENTS ===")
        debugMessage = "Printed \(blueprint.events.count) events to console"
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
    
    private func getAllNotes() -> [PitchClass] {
        // Return all 12 notes, starting from the tonic for convenience
        let tonic = song.keySig.tonic
        return (0..<12).map { tonic.transposed(semitones: $0) }
    }
    
    private func getDefaultQuality(for root: PitchClass) -> Chord.Quality {
        let tonic = song.keySig.tonic
        let scale = Roman.scale(for: song.keySig.mode)
        let offset = (root.rawValue - tonic.rawValue + 12) % 12
        
        // Find which scale degree this is
        if let idx = scale.firstIndex(of: offset) {
            switch song.keySig.mode {
            case .ionian: // Major
                return [0, 3, 5].contains(idx) ? .maj : (idx == 6 ? .dim : .min)
            case .aeolian: // Minor  
                return [2, 5, 6].contains(idx) ? .maj : (idx == 1 ? .dim : .min)
            case .dorian:
                return [1, 4, 6].contains(idx) ? .maj : (idx == 5 ? .dim : .min)
            case .mixolydian:
                return [0, 3, 6].contains(idx) ? .maj : (idx == 2 ? .dim : .min)
            case .lydian:
                return [0, 1, 4].contains(idx) ? .maj : (idx == 6 ? .dim : .min)
            case .phrygian:
                return [2, 4, 5].contains(idx) ? .maj : (idx == 0 ? .dim : .min)
            case .locrian:
                return [1, 3, 5].contains(idx) ? .maj : (idx == 0 ? .dim : .min)
            }
        }
        // Default to major for notes outside the scale
        return .maj
    }
    
    
    
    private func deleteCurrentCellChord() {
        if let event = eventCovering(currentCell) {
            deleteEvent(event)
            debugMessage = "Deleted chord at cell \(currentCell + 1)"
        } else {
            debugMessage = "No chord at cell \(currentCell + 1)"
        }
    }
    
    
    private func applyChordToCell(chord: Chord, length: Int = 1, autoAdvance: Bool = false) {
        
        print("[APPLY] Applying chord \(chord.displayName(preferSharps: true)) to cell \(currentCell) with length \(length)")
        
        // Special handling for single cell edits within a longer event
        if length == 1 {
            // Check if we're editing within a longer event
            if let existingEvent = eventCovering(currentCell) {
                let evEnd = existingEvent.startTick + existingEvent.lengthTicks - 1
                print("[APPLY] Editing within existing event (start=\(existingEvent.startTick), end=\(evEnd))")
                
                // If same chord, do nothing
                if existingEvent.chord == chord && !existingEvent.isRest {
                    print("[APPLY] Same chord, no change needed")
                    if autoAdvance {
                        currentCell = min(currentCell + 1, totalTicks - 1)
                        buildingChord = nil
                    }
                    return
                }
            }
        }
        
        // Remove any existing events that overlap with the new chord's range
        removeOverlappingEvents(from: currentCell, to: currentCell + length - 1)
        
        // Check if we can merge with previous cell
        var merged = false
        if currentCell > 0 && length == 1 {
            if let prevEvent = blueprint.events.first(where: { ev in
                ev.startTick + ev.lengthTicks == currentCell && !ev.isRest && ev.chord == chord
            }) {
                prevEvent.lengthTicks += 1
                merged = true
                print("[APPLY] Extended previous event")
            }
        }
        
        // Check if we can merge with next cell
        if !merged && length == 1 {
            if let nextEvent = blueprint.events.first(where: { ev in
                ev.startTick == currentCell + 1 && !ev.isRest && ev.chord == chord
            }) {
                nextEvent.startTick = currentCell
                nextEvent.lengthTicks += 1
                merged = true
                print("[APPLY] Extended next event backward")
            }
        }
        
        if !merged {
            let newEvent = ChordEvent(startTick: currentCell, lengthTicks: length, isRest: false, chord: chord)
            blueprint.events.append(newEvent)
            print("[APPLY] Added new event at tick \(currentCell) with length \(length)")
        }
        
        if autoAdvance {
            // Auto-advance to next cell
            currentCell = min(currentCell + 1, totalTicks - 1)
            buildingChord = nil
        }
    }
    
    // Keep the old quickAddChord for backwards compatibility if needed
    private func quickAddChord(_ chord: Chord) {
        applyChordToCell(chord: chord, autoAdvance: true)
    }
    
    private func quickAddRest() {
        print("[QUICK] Adding rest at cell \(currentCell)")
        removeOverlappingEvents(from: currentCell, to: currentCell)
        let rest = ChordEvent(startTick: currentCell, lengthTicks: 1, isRest: true, chord: .defaultMajC)
        blueprint.events.append(rest)
        currentCell = min(currentCell + 1, totalTicks - 1)
    }
}

// MARK: - Chord Event Editor

struct ChordEventEditor: View, Identifiable {
    var id: UUID { ev.id }
    var song: Song
    @Bindable var ev: ChordEvent
    let cellsPerBar: Int
    @Bindable var blueprint: SectionBlueprint
    @State private var chordText: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            Form {
                chordSection
                lengthSection
                infoSection
            }
            .navigationTitle("Edit Event")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) {
                        deleteEvent()
                    }
                }
            }
        }
        .onAppear {
            // Initialize with current chord text
            chordText = ev.chord.displayName(preferSharps: true)
        }
    }
    
    @ViewBuilder
    private var chordSection: some View {
        if !ev.isRest {
            TextField("Chord (e.g. Am7, G/B, Fadd9, C7#11)", text: $chordText)
            Button("Parse & Apply") {
                applyChordText()
            }
        } else {
            Text("This is a Rest")
        }
    }
    
    private var lengthSection: some View {
        Section("Length") {
            Stepper("Cells: \(ev.lengthTicks)", value: $ev.lengthTicks, in: 1...512)
            Button("To end of bar") {
                extend(toBarsAhead: 0)
            }
            Button("To end of next bar") {
                extend(toBarsAhead: 1)
            }
        }
    }
    
    private var infoSection: some View {
        Section("Info") {
            let startBar = ev.startTick / cellsPerBar + 1
            let startCell = ev.startTick % cellsPerBar + 1
            Text("Starts at: bar \(startBar), cell \(startCell)")
            
            if !ev.isRest {
                let roman = Roman.roman(for: ev.chord, in: song.keySig)
                Text("Roman: \(roman)")
                
                let showShapes = song.capo > 0 && song.viewMode != .numerals
                let name = ev.chord.displayName(
                    preferSharps: song.keySig.preferSharps,
                    capo: song.capo,
                    showShapesWithCapo: showShapes
                )
                Text("Name: \(name)")
            }
        }
    }
    
    private func applyChordText() {
        if let parsed = ChordParser.parse(chordText) {
            ev.isRest = false
            ev.chord = parsed
            print("[EDITOR] Applied chord: \(parsed.displayName(preferSharps: true))")
        }
    }
    
    private func extend(toBarsAhead: Int) {
        let currentBar = ev.startTick / cellsPerBar
        let endBar = currentBar + toBarsAhead
        let endTick = (endBar+1)*cellsPerBar - 1
        ev.lengthTicks = max(1, endTick - ev.startTick + 1)
    }
    
    private func deleteEvent() {
        print("[EDITOR] Deleting event from editor: \(ev.id)")
        if let index = blueprint.events.firstIndex(where: { $0.id == ev.id }) {
            blueprint.events.remove(at: index)
            modelContext.delete(ev)
            print("[EDITOR] Removed event at index \(index)")
        }
        dismiss()
    }
}