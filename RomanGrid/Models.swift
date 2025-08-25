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
    // Whether to prefer sharps or flats for display; auto-chosen by key
    var preferSharps: Bool {
        // Rough heuristic: keys with sharps or naturals prefer sharps; flats prefer flats.
        // You can refine this later.
        let sharpTones: Set<PitchClass> = [.C, .G, .D, .A, .E, .B, .FSharp, .CSharp]
        return sharpTones.contains(tonic)
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
         viewMode: ChordDisplayMode = .both) {
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
    var keyOverride: KeySignature?     // section modulation
    var lyrics: String                 // free text, not rhythm-locked
    var blueprintID: UUID              // reference to the source blueprint (by id)
    
    init(displayName: String, repeats: Int = 1, keyOverride: KeySignature? = nil, lyrics: String = "", blueprintID: UUID) {
        self.id = UUID()
        self.displayName = displayName
        self.repeats = repeats
        self.keyOverride = keyOverride
        self.lyrics = lyrics
        self.blueprintID = blueprintID
    }
}

@Model
final class ChordEvent {
    var id: UUID
    var startTick: Int         // start index in grid cells
    var lengthTicks: Int       // length in grid cells
    var isRest: Bool
    var chord: Chord           // parsed chord (keeps data, no simplification)
    
    init(startTick: Int, lengthTicks: Int, isRest: Bool = false, chord: Chord = .defaultMajC) {
        self.id = UUID()
        self.startTick = startTick
        self.lengthTicks = lengthTicks
        self.isRest = isRest
        self.chord = chord
    }
}

// MARK: - Display mode

enum ChordDisplayMode: String, Codable, CaseIterable, Identifiable {
    case names, numerals, both
    var id: String { rawValue }
}
