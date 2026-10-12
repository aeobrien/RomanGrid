import Foundation

// MARK: - Pitch classes and helpers

enum PitchClass: Int, Codable, CaseIterable, Identifiable {
    case C=0, CSharp=1, D=2, DSharp=3, E=4, F=5, FSharp=6, G=7, GSharp=8, A=9, ASharp=10, B=11
    var id: Int { rawValue }
    
    // Enharmonic aliases (Db, Eb, Gb, Ab, Bb)
    static let flatNames: [PitchClass: String] = [
        .C: "C", .CSharp: "Db", .D: "D", .DSharp: "Eb", .E: "E",
        .F: "F", .FSharp: "Gb", .G: "G", .GSharp: "Ab", .A: "A",
        .ASharp: "Bb", .B: "B"
    ]
    static let sharpNames: [PitchClass: String] = [
        .C: "C", .CSharp: "C#", .D: "D", .DSharp: "D#", .E: "E",
        .F: "F", .FSharp: "F#", .G: "G", .GSharp: "G#", .A: "A",
        .ASharp: "A#", .B: "B"
    ]
    
    func name(preferSharps: Bool) -> String {
        preferSharps ? PitchClass.sharpNames[self]! : PitchClass.flatNames[self]!
    }
    
    static func from(name: String) -> PitchClass? {
        // Accept C, C#, Db, etc. Normalise
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines)
                      .replacingOccurrences(of: "♯", with: "#")
                      .replacingOccurrences(of: "♭", with: "b")
        let mapping: [String: PitchClass] = [
            "C": .C, "B#": .C,
            "C#": .CSharp, "Db": .CSharp,
            "D": .D,
            "D#": .DSharp, "Eb": .DSharp,
            "E": .E, "Fb": .E,
            "F": .F, "E#": .F,
            "F#": .FSharp, "Gb": .FSharp,
            "G": .G,
            "G#": .GSharp, "Ab": .GSharp,
            "A": .A,
            "A#": .ASharp, "Bb": .ASharp,
            "B": .B, "Cb": .B
        ]
        return mapping[s]
    }
    
    func transposed(semitones: Int) -> PitchClass {
        let v = (rawValue + semitones) % 12
        return PitchClass(rawValue: (v + 12) % 12)! // safe
    }
}

// MARK: - Chord structure

struct Chord: Codable, Hashable {
    enum Quality: String, Codable {
        case maj, min, dim, aug, sus2, sus4, five // five = power chord (5)
    }
    // Extensions/flags we explicitly support v1
    struct Flags: OptionSet, Codable, Hashable {
        let rawValue: Int
        static let six    = Flags(rawValue: 1<<0)
        static let seven  = Flags(rawValue: 1<<1)     // dominant 7 unless maj7 also set
        static let maj7   = Flags(rawValue: 1<<2)
        static let nine   = Flags(rawValue: 1<<3)     // 9th chord (not "add9")
        static let add9   = Flags(rawValue: 1<<4)     // add9 (no 7th)
    }
    // Alterations usable as suffixes: #11, b9, etc.
    struct Alteration: Codable, Hashable {
        var text: String // keep literal like "#11", "b9", "b13"
    }
    
    var root: PitchClass
    var quality: Quality
    var flags: Flags
    var alterations: [Alteration]
    var bass: PitchClass? // slash bass, transposes with root
    
    static let defaultMajC = Chord(root: .C, quality: .maj, flags: [], alterations: [], bass: nil)
    
    // Render chord name in a given key preference (sharps/flats) and optional capo
    func displayName(preferSharps: Bool, capo: Int = 0, showShapesWithCapo: Bool = false) -> String {
        // If capo shapes requested, shift "shape root" downward by capo
        let actualRoot = root
        let showRoot = showShapesWithCapo ? actualRoot.transposed(semitones: -capo) : actualRoot
        let showBass = bass.map { showShapesWithCapo ? $0.transposed(semitones: -capo) : $0 }
        
        var s = showRoot.name(preferSharps: preferSharps)
        switch quality {
        case .maj: break
        case .min: s += "m"
        case .dim: s += "dim"
        case .aug: s += "aug"
        case .sus2: s += "sus2"
        case .sus4: s += "sus4"
        case .five: s += "5"
        }
        if flags.contains(.maj7) { s += "maj7" }
        else if flags.contains(.seven) { s += "7" }
        if flags.contains(.six) { s += "6" }
        if flags.contains(.nine) { s += "9" }
        if flags.contains(.add9) { s += "add9" }
        if !alterations.isEmpty {
            let alts = alterations.map { $0.text }.joined()
            s += alts
        }
        if let b = showBass {
            s += "/\(b.name(preferSharps: preferSharps))"
        }
        return s
    }
    
    // Transpose chord by semitone offset (positive up)
    func transposed(semitones: Int) -> Chord {
        Chord(
            root: root.transposed(semitones: semitones),
            quality: quality,
            flags: flags,
            alterations: alterations,
            bass: bass?.transposed(semitones: semitones)
        )
    }
}

// MARK: - Parser: from text like "G/B", "Am7", "G7#11", "Fadd9", "Bbmaj7", "Gsus4", "C5"

struct ChordParser {
    // Very pragmatic regex: Root, optional accidental, remainder for flags/alterations, optional slash
    // Examples handled in tests in your head for now :-)
    static func parse(_ text: String) -> Chord? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        
        // Split slash first
        let parts = cleaned.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let head = String(parts.first ?? "")
        let slash = parts.count == 2 ? String(parts[1]) : nil
        
        // Root match: one letter A-G plus optional accidental (#/b)
        guard let rootMatch = head.firstMatch(of: #/^[A-Ga-g](?:#|b)?/#) else { return nil }
        let rootStr = String(rootMatch.0).uppercased()
        guard let root = PitchClass.from(name: rootStr) else { return nil }
        let tail = String(head.dropFirst(rootStr.count))
        
        var quality: Chord.Quality = .maj
        var flags: Chord.Flags = []
        var alterations: [Chord.Alteration] = []
        
        // Quality & flags detection (order matters a bit)
        var t = tail
        
        // Power chord
        if t.hasPrefix("5") { quality = .five; t = String(t.dropFirst()) }
        // Minor markers
        if t.hasPrefix("mMaj7") { quality = .min; flags.insert(.maj7); t = String(t.dropFirst(5)) }
        else if t.hasPrefix("maj7") { flags.insert(.maj7); t = String(t.dropFirst(4)) }
        else if t.hasPrefix("m7") { quality = .min; flags.insert(.seven); t = String(t.dropFirst(2)) }
        else if t.hasPrefix("m6") { quality = .min; flags.insert(.six); t = String(t.dropFirst(2)) }
        else if t.hasPrefix("m") { quality = .min; t = String(t.dropFirst(1)) }
        else if t.hasPrefix("dim7") { quality = .dim; flags.insert(.seven); t = String(t.dropFirst(4)) }
        else if t.hasPrefix("dim") { quality = .dim; t = String(t.dropFirst(3)) }
        else if t.hasPrefix("aug") { quality = .aug; t = String(t.dropFirst(3)) }
        
        // Sevenths / Six / 9 / add9 in any remaining order (simple greedy)
        if t.contains("maj7") { flags.insert(.maj7); t = t.replacingOccurrences(of: "maj7", with: "") }
        if t.contains("7") { flags.insert(.seven); t = t.replacingOccurrences(of: "7", with: "") }
        if t.contains("6") { flags.insert(.six); t = t.replacingOccurrences(of: "6", with: "") }
        if t.contains("add9") { flags.insert(.add9); t = t.replacingOccurrences(of: "add9", with: "") }
        if t.contains("9") { flags.insert(.nine); t = t.replacingOccurrences(of: "9", with: "") }
        if t.contains("sus2") { quality = .sus2; t = t.replacingOccurrences(of: "sus2", with: "") }
        if t.contains("sus4") { quality = .sus4; t = t.replacingOccurrences(of: "sus4", with: "") }
        
        // Alterations: collect tokens like #11, b9, b13, #5, b5
        let altPattern = try! NSRegularExpression(pattern: "(#[0-9]{1,2}|b[0-9]{1,2})")
        let ns = t as NSString
        let matches = altPattern.matches(in: t, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let str = ns.substring(with: m.range)
            alterations.append(.init(text: str))
        }
        
        let bassPC = slash.flatMap { PitchClass.from(name: $0) }
        
        return Chord(root: root, quality: quality, flags: flags, alterations: alterations, bass: bassPC)
    }
}

// MARK: - Roman numeral engine

struct Roman {
    // Modal semitone ladders (relative to tonic)
    static func scale(for mode: Mode) -> [Int] {
        switch mode {
        case .ionian:     return [0,2,4,5,7,9,11]
        case .dorian:     return [0,2,3,5,7,9,10]
        case .phrygian:   return [0,1,3,5,7,8,10]
        case .lydian:     return [0,2,4,6,7,9,11]
        case .mixolydian: return [0,2,4,5,7,9,10]
        case .aeolian:    return [0,2,3,5,7,8,10]
        case .locrian:    return [0,1,3,5,6,8,10]
        }
    }
    
    static let romanBase = ["I","II","III","IV","V","VI","VII"]
    
    // MARK: Letter-aware helpers
    
    // Cyclic list of letters starting from the tonic's letter (e.g. G,A,B,C,D,E,F for G)
    private static func diatonicLetters(from tonic: PitchClass) -> [String] {
        // Map pitch classes to a base letter (no accidental); good enough for degree numbering.
        let pcToLetter: [PitchClass:String] = [
            .C:"C", .CSharp:"C", .D:"D", .DSharp:"D", .E:"E",
            .F:"F", .FSharp:"F", .G:"G", .GSharp:"G", .A:"A",
            .ASharp:"A", .B:"B"
        ]
        let letters = ["C","D","E","F","G","A","B"]
        let tonicLetter = pcToLetter[tonic]!
        let start = letters.firstIndex(of: tonicLetter)! // safe
        return (0..<7).map { letters[(start + $0) % 7] }
    }
    
    // Given degree index 0..6, return the diatonic pitch class for that letter-degree in this key.
    private static func diatonicPitchClass(forDegree idx: Int, tonic: PitchClass, mode: Mode) -> PitchClass {
        let sc = scale(for: mode)            // existing: [0,2,4,5,7,9,11] (etc by mode)
        return tonic.transposed(semitones: sc[idx])
    }
    
    // Signed semitone alteration from the actual pitch to the diatonic letter-degree (−6..+6)
    private static func alteration(from actual: PitchClass, toDiatonic diatonic: PitchClass) -> Int {
        var diff = (actual.rawValue - diatonic.rawValue) % 12
        if diff < -6 { diff += 12 }
        if diff >  6 { diff -= 12 }
        return diff
    }
    
    // Letter-aware degree: choose degree by LETTER first, then accidental from diatonic reference.
    static func degree(for root: PitchClass, in key: KeySignature) -> (idx: Int, accidental: Int) {
        let letters = diatonicLetters(from: key.tonic) // e.g. G,A,B,C,D,E,F for G-based keys
        // Evaluate alteration for each degree letter; choose minimal |alteration|
        var bestIdx = 0
        var bestAlt = 99
        for i in 0..<7 {
            let dia = diatonicPitchClass(forDegree: i, tonic: key.tonic, mode: key.mode)
            let alt = alteration(from: root, toDiatonic: dia)
            let absAlt = abs(alt)
            if absAlt < abs(bestAlt) {
                bestAlt = alt; bestIdx = i
            } else if absAlt == abs(bestAlt) {
                // Tie-break: in Ionian (major), favour flats on III/VI/VII (common borrowed usage).
                if key.mode == .ionian, [2,5,6].contains(i), bestAlt > 0 { bestAlt = alt; bestIdx = i }
            }
        }
        return (bestIdx, bestAlt)
    }
    
    // OLD METHOD - Keep for backward compatibility if needed elsewhere
    static func degree(for offset: Int, mode: Mode) -> (idx:Int, accidental:Int) {
        let sc = scale(for: mode)
        let off = (offset + 12) % 12
        var bestIdx = 0, bestDelta = 99
        for (i, semis) in sc.enumerated() {
            let d = abs(off - semis)
            if d < bestDelta {
                bestDelta = d; bestIdx = i
            }
        }
        let accidental = off - sc[bestIdx] // -2…+2 (we'll clamp to -1/0/+1 typically)
        return (bestIdx, accidental)
    }
    
    // Build roman string using letter-aware degree calculation
    static func roman(for chord: Chord, in key: KeySignature) -> String {
        // NEW: call letter-aware degree(for:root:in:)
        let (idx, acc) = degree(for: chord.root, in: key)
        var numeral = romanBase[idx]
        
        // Put accidentals on the numeral
        if acc < 0 { numeral = String(repeating: "♭", count: -acc) + numeral }
        else if acc > 0 { numeral = String(repeating: "♯", count: acc) + numeral }
        
        // Case by chord's third (quality)
        // For suspended chords, use case based on underlying diatonic quality
        if chord.quality == .sus2 || chord.quality == .sus4 {
            // Check if this degree is naturally major or minor in the key
            let scale = self.scale(for: key.mode)
            let diatonicThirdInterval: Int
            
            // Get the diatonic third interval for this degree
            // idx is degree 0-6, we need the third above it
            let thirdDegreeIdx = (idx + 2) % 7
            let rootSemitones = scale[idx]
            let thirdSemitones = scale[thirdDegreeIdx]
            
            // Calculate interval accounting for octave wrap
            if thirdDegreeIdx < idx {
                // Third wrapped to next octave
                diatonicThirdInterval = (thirdSemitones + 12) - rootSemitones
            } else {
                diatonicThirdInterval = thirdSemitones - rootSemitones
            }
            
            // Major third = 4 semitones, minor third = 3 semitones
            if diatonicThirdInterval == 3 {
                numeral = numeral.lowercased()
            }
            // else keep uppercase for major
        } else {
            // Non-suspended chords: use quality directly
            switch chord.quality {
            case .min, .dim:
                numeral = numeral.lowercased()
            default: break
            }
        }
        
        if chord.quality == .dim { numeral += "°" }
        if chord.quality == .aug { numeral += "+" }
        
        // Add figures/suffixes to preserve data
        var suffix = ""
        if chord.quality == .sus2 { suffix += "sus2" }
        if chord.quality == .sus4 { suffix += "sus4" }
        if chord.quality == .five { suffix += "5" }
        if chord.flags.contains(.maj7) { suffix += "maj7" }
        else if chord.flags.contains(.seven) { suffix += "7" }
        if chord.flags.contains(.six) { suffix += "6" }
        if chord.flags.contains(.nine) { suffix += "9" }
        if chord.flags.contains(.add9) { suffix += "add9" }
        if !chord.alterations.isEmpty {
            suffix += chord.alterations.map { $0.text }.joined()
        }
        if let bass = chord.bass {
            // Check if this is an inversion (bass is a chord tone)
            let third = chord.root.transposed(semitones: (chord.quality == .min || chord.quality == .dim) ? 3 : 4)
            let fifth = chord.root.transposed(semitones: chord.quality == .dim ? 6 : (chord.quality == .aug ? 8 : 7))
            let seventh = chord.flags.contains(.maj7) ? chord.root.transposed(semitones: 11) : 
                          chord.flags.contains(.seven) ? chord.root.transposed(semitones: 10) : nil
            
            if bass == third {
                // First inversion - add 'b' suffix
                return numeral + suffix + "b"
            } else if bass == fifth {
                // Second inversion - add 'c' suffix  
                return numeral + suffix + "c"
            } else if bass == seventh {
                // Third inversion - add 'd' suffix
                return numeral + suffix + "d"
            } else {
                // Non-chord tone bass - show as slash chord
                // Use new letter-aware degree calculation
                let (bidx, bacc) = degree(for: bass, in: key)
                var broman = romanBase[bidx]
                if bacc < 0 { broman = String(repeating: "♭", count: -bacc) + broman }
                else if bacc > 0 { broman = String(repeating: "♯", count: bacc) + broman }
                broman = broman.uppercased() // conventionally uppercase for scale degree label
                suffix += "/\(broman)"
            }
        }
        return suffix.isEmpty ? numeral : "\(numeral)\(suffix)"
    }
}
