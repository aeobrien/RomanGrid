import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Codable mirror used for export/import (stable format)
struct ExportSong: Codable {
    var song: SongDTO
    var blueprints: [SectionBlueprintDTO]
    var arrangement: [SectionInstanceDTO]
    var events: [ChordEventDTO]
}

// DTOs (decouple from SwiftData models to keep file format stable)
struct SongDTO: Codable {
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
}
struct SectionBlueprintDTO: Codable {
    var id: UUID
    var name: String
    var bars: Int
    var resolution: GridResolution
    var defaultKeyOverride: KeySignature?
}
struct SectionInstanceDTO: Codable {
    var id: UUID
    var displayName: String
    var repeats: Int
    var keyOverride: KeySignature?
    var lyrics: String
    var blueprintID: UUID
}
struct ChordEventDTO: Codable {
    var id: UUID
    var sectionBlueprintID: UUID
    var startTick: Int
    var lengthTicks: Int
    var isRest: Bool
    var chord: Chord
}

extension Song {
    func toExportBundle() -> ExportSong {
        // Capture events with their parent blueprint IDs
        var evDTOs: [ChordEventDTO] = []
        for bp in blueprints {
            for ev in bp.events {
                evDTOs.append(
                    ChordEventDTO(
                        id: ev.id,
                        sectionBlueprintID: bp.id,
                        startTick: ev.startTick,
                        lengthTicks: ev.lengthTicks,
                        isRest: ev.isRest,
                        chord: ev.chord
                    )
                )
            }
        }
        return ExportSong(
            song: SongDTO(id: id, title: title, artist: artist, tags: tags, notes: notes, keySig: keySig, tempoBPM: tempoBPM, timeSig: timeSig, capo: capo, viewMode: viewMode),
            blueprints: blueprints.map { SectionBlueprintDTO(id: $0.id, name: $0.name, bars: $0.bars, resolution: $0.resolution, defaultKeyOverride: $0.defaultKeyOverride) },
            arrangement: arrangement.map { SectionInstanceDTO(id: $0.id, displayName: $0.displayName, repeats: $0.repeats, keyOverride: $0.keyOverride, lyrics: $0.lyrics, blueprintID: $0.blueprintID) },
            events: evDTOs
        )
    }
}

extension ExportSong {
    func importInto(_ context: ModelContext) -> Song {
        let s = Song(title: song.title, artist: song.artist, tags: song.tags, notes: song.notes, keySig: song.keySig, tempoBPM: song.tempoBPM, timeSig: song.timeSig, capo: song.capo, viewMode: song.viewMode)
        s.id = song.id
        
        var bpMap: [UUID: SectionBlueprint] = [:]
        for bpDTO in blueprints {
            let bp = SectionBlueprint(name: bpDTO.name, bars: bpDTO.bars, resolution: bpDTO.resolution, defaultKeyOverride: bpDTO.defaultKeyOverride)
            bp.id = bpDTO.id
            context.insert(bp)
            bpMap[bpDTO.id] = bp
            s.blueprints.append(bp)
        }
        for evDTO in events {
            guard let bp = bpMap[evDTO.sectionBlueprintID] else { continue }
            let ev = ChordEvent(startTick: evDTO.startTick, lengthTicks: evDTO.lengthTicks, isRest: evDTO.isRest, chord: evDTO.chord)
            ev.id = evDTO.id
            context.insert(ev)
            bp.events.append(ev)
        }
        for instDTO in arrangement {
            let inst = SectionInstance(displayName: instDTO.displayName, repeats: instDTO.repeats, keyOverride: instDTO.keyOverride, lyrics: instDTO.lyrics, blueprintID: instDTO.blueprintID)
            inst.id = instDTO.id
            context.insert(inst)
            s.arrangement.append(inst)
        }
        context.insert(s)
        return s
    }
}

// Simple helpers for SwiftUI file import/export
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { self.data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { .init(regularFileWithContents: data) }
}
