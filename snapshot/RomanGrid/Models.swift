import Foundation
import SwiftData

// MARK: - Music enums

enum Mode: String, Codable, CaseIterable, Identifiable {
    case ionian = "Ionian (Major)"
    case dorian = "Dorian"
    case phrygian = "Phrygian"
    case lydian = "Lydian"
    case mixolydian = "Mixolydian"
    case aeolian = "Aeolian (Minor)"
    case locrian = "Locrian"
    var id: String { rawValue }
}

enum GridResolution: Int, Codable, CaseIterable, Identifiable {
    case beat = 1     // 1 cell per beat
    case eighth = 2   // 2 cells per beat
    case sixteenth = 4// 4 cells per beat
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .beat: return "Beat"
        case .eighth: return "1/8"
        case .sixteenth: return "1/16"
        }
    }
}

struct TimeSignature: Codable, Hashable {
    var beatsPerBar: Int = 4
    var beatUnit: Int = 4
}

struct KeySignature: Codable, Hashable {
    var tonic: PitchClass = .C
    var mode: Mode = .ionian
    
    init(tonic: PitchClass = .C, mode: Mode = .ionian) {
        self.tonic = tonic
        self.mode = mode
    }
    
    // Whether to prefer sharps or flats for display; auto-chosen by key
    var preferSharps: Bool {
        // Rough heuristic: keys with sharps or naturals prefer sharps; flats prefer flats.
        // You can refine this later.
        let sharpTones: Set<PitchClass> = [.C, .G, .D, .A, .E, .B, .FSharp, .CSharp]
        return sharpTones.contains(tonic)
    }
    
    // Get a transposed version of this key signature
    func transposed(semitones: Int) -> KeySignature {
        var newKey = self
        newKey.tonic = tonic.transposed(semitones: semitones)
        return newKey
    }
}

// MARK: - SwiftData Models

@Model
final class Song {
    var id: UUID
    var title: String
    var artist: String
    var tags: [String]
    var notes: String
    var keySig: KeySignature
    var tempoBPM: Double
    var timeSig: TimeSignature
    var capo: Int
    var viewMode: ChordDisplayMode
    var transposition: Int = 0 // Global transposition in semitones (can be negative)
    
    // Library of reusable section blueprints inside this song
    @Relationship(deleteRule: .cascade) var blueprints: [SectionBlueprint]
    // Arrangement references copies of blueprints
    @Relationship(deleteRule: .cascade) var arrangement: [SectionInstance]
    
    init(title: String = "New Song",
         artist: String = "",
         tags: [String] = [],
         notes: String = "",
         keySig: KeySignature = KeySignature(),
         tempoBPM: Double = 120,
         timeSig: TimeSignature = TimeSignature(),
         capo: Int = 0,
         viewMode: ChordDisplayMode = .both,
         transposition: Int = 0) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.tags = tags
        self.notes = notes
        self.keySig = keySig
        self.tempoBPM = tempoBPM
        self.timeSig = timeSig
        self.capo = capo
        self.viewMode = viewMode
        self.transposition = transposition
        self.blueprints = []
        self.arrangement = []
    }
}

@Model
final class SectionBlueprint {
    var id: UUID
    var name: String              // "Verse", "Chorus"
    var bars: Int
    var resolution: GridResolution
    var defaultKeyOverride: KeySignature? // optional modulation baked in (rare; usually per instance)
    
    // Full grid coverage rule: the grid should be filled with ChordEvents or explicit rests.
    @Relationship(deleteRule: .cascade) var events: [ChordEvent]
    
    init(name: String = "Section",
         bars: Int = 4,
         resolution: GridResolution = .beat,
         defaultKeyOverride: KeySignature? = nil) {
        self.id = UUID()
        self.name = name
        self.bars = bars
        self.resolution = resolution
        self.defaultKeyOverride = defaultKeyOverride
        self.events = []
    }
    
    // Total ticks available in this section
    func totalTicks(beatsPerBar: Int) -> Int {
        beatsPerBar * bars * resolution.rawValue
    }
}

@Model
final class SectionInstance {
    var id: UUID
    var displayName: String            // "Verse 1"
    var repeats: Int                   // N repeats
    var keyOverride: KeySignature?     // section modulation (relative to song key)
    var lyrics: String                 // free text, not rhythm-locked
    var blueprintID: UUID              // reference to the source blueprint (by id)
    var isLinked: Bool = true          // true = uses shared blueprint, false = has own copy
    @Relationship(deleteRule: .cascade) var ownBlueprint: SectionBlueprint? // independent copy when unlinked
    @Relationship(deleteRule: .cascade) var lyricsData: LyricsSection? // structured lyrics with lines and bars
    
    init(displayName: String, repeats: Int = 1, keyOverride: KeySignature? = nil, lyrics: String = "", blueprintID: UUID, isLinked: Bool = true) {
        self.id = UUID()
        self.displayName = displayName
        self.repeats = repeats
        self.keyOverride = keyOverride
        self.lyrics = lyrics
        self.blueprintID = blueprintID
        self.isLinked = isLinked
        self.ownBlueprint = nil
        self.lyricsData = nil
    }
    
    // Calculate the effective key for this section considering:
    // 1. Song's base key
    // 2. Song's global transposition
    // 3. Section's key override
    func effectiveKey(songKey: KeySignature, songTransposition: Int) -> KeySignature {
        // If there's a section key override, use it (and apply global transposition)
        if let override = keyOverride {
            return override.transposed(semitones: songTransposition)
        }
        
        // Otherwise use the song's key, transposed by global transposition
        return songKey.transposed(semitones: songTransposition)
    }
}

@Model
final class ChordEvent {
    var id: UUID
    var startTick: Int         // start index in grid cells (relative to current resolution)
    var lengthTicks: Int       // length in grid cells (relative to current resolution)
    var absoluteStart: Double?  // absolute position in beats (optional for migration)
    var absoluteDuration: Double? // absolute duration in beats (optional for migration)
    var isRest: Bool
    var chord: Chord           // parsed chord (keeps data, no simplification)
    
    init(startTick: Int, lengthTicks: Int, isRest: Bool = false, chord: Chord = .defaultMajC, absoluteStart: Double? = nil, absoluteDuration: Double? = nil) {
        self.id = UUID()
        self.startTick = startTick
        self.lengthTicks = lengthTicks
        self.absoluteStart = absoluteStart ?? Double(startTick)
        self.absoluteDuration = absoluteDuration ?? Double(lengthTicks)
        self.isRest = isRest
        self.chord = chord
    }
    
    func updateAbsoluteValues(resolution: GridResolution, beatsPerBar: Int) {
        // Convert tick positions to absolute beat positions
        let ticksPerBeat = Double(resolution.rawValue)
        absoluteStart = Double(startTick) / ticksPerBeat
        absoluteDuration = Double(lengthTicks) / ticksPerBeat
    }
    
    func updateTicksFromAbsolute(resolution: GridResolution, beatsPerBar: Int) {
        // Convert absolute positions back to ticks for the current resolution
        guard let absStart = absoluteStart, let absDuration = absoluteDuration else {
            // If no absolute values, use tick values as-is
            absoluteStart = Double(startTick)
            absoluteDuration = Double(lengthTicks)
            return
        }
        let ticksPerBeat = Double(resolution.rawValue)
        startTick = Int((absStart * ticksPerBeat).rounded())
        lengthTicks = max(1, Int((absDuration * ticksPerBeat).rounded()))
    }
}

// MARK: - Lyrics Models

@Model
final class LyricsSection {
    var id: UUID
    @Relationship(deleteRule: .cascade) var lines: [LyricsLine]
    
    init() {
        self.id = UUID()
        self.lines = []
    }
}

@Model
final class LyricsLine {
    var id: UUID
    var text: String
    var barIndex: Int  // Which bar this line is associated with (0-based)
    var startBeat: Double  // Beat position within bar (0.0 = start, 1.0 = beat 1, etc.)
    var endBeat: Double?  // Optional end position if lyrics span multiple bars
    var isEmpty: Bool  // Explicitly mark blank lines
    
    init(text: String = "", barIndex: Int = 0, startBeat: Double = 0.0, endBeat: Double? = nil, isEmpty: Bool = false) {
        self.id = UUID()
        self.text = text
        self.barIndex = barIndex
        self.startBeat = startBeat
        self.endBeat = endBeat
        self.isEmpty = isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Display mode

enum ChordDisplayMode: String, Codable, CaseIterable, Identifiable {
    case names, numerals, both
    var id: String { rawValue }
}
