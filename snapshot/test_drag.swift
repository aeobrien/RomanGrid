// Test script to verify drag-to-extend implementation
// This shows the key changes made to fix the drag gesture

/*
FIXES IMPLEMENTED:

1. DRAG GESTURE FIX:
   - Moved from background GeometryReader to simultaneousGesture on ScrollView
   - Added draggedCells Set to track cells during drag
   - Added purple highlight for cells being dragged
   - Separated handleDragChanged and handleDragEnded functions
   - Fixed coordinate calculations in getCellFromLocation
   - Added check in onTapGesture to prevent tap during drag

2. CHORD BUILDER HEIGHT FIX:
   - Removed nested VStack(spacing: 0) wrapper
   - Changed from padding-based sizing to direct VStack with spacing
   - Moved padding to single layer at end
   - Container now properly collapses when second row is hidden

KEY CODE SECTIONS:

// Drag gesture on ScrollView instead of background:
.simultaneousGesture(
    DragGesture(minimumDistance: 5)
        .onChanged { value in
            handleDragChanged(value, cellWidth: cellWidth, cellHeight: cellHeight)
        }
        .onEnded { _ in
            handleDragEnded()
        }
)

// New drag handling functions:
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

// Visual feedback during drag:
@ViewBuilder
private func cellSelection(tick: Int) -> some View {
    if draggedCells.contains(tick) {
        Rectangle()
            .stroke(.purple, lineWidth: 2)  // Purple for dragging
    } else if isSelected(tick) {
        Rectangle()
            .stroke(.blue, lineWidth: 2)    // Blue for selected
    } else if tick == currentCell {
        Rectangle()
            .stroke(.orange, lineWidth: 2)  // Orange for current
    }
}

// Chord builder simplified structure:
var body: some View {
    VStack(spacing: 8) {  // Direct VStack, no wrapper
        // First row
        HStack(spacing: 8) {
            // Root and Quality pickers
        }
        
        // Second row (collapsible)
        if showSecondRow {
            HStack(spacing: 8) {
                // 7th, Inversion, Bass pickers
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        
        Divider()
        actionRow
    }
    .padding(8)  // Single padding layer
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(8)
    .padding(.horizontal, 8)
}

EXPECTED BEHAVIOR:
1. Tapping a cell selects it (orange highlight)
2. Dragging from one cell to another shows purple highlights during drag
3. After drag ends, creates/extends chord across dragged cells
4. Chord builder grey background shrinks when second row is collapsed
5. Logs show [DRAG] events, not just [TAP] events
*/

print("Test implementation guide created")