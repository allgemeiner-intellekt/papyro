// Papyro/Services/IndexService.swift
import Foundation

struct IndexService: Sendable {

    private var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    func save(_ paper: Paper, in libraryRoot: URL) throws {
        let indexDir = libraryRoot.appendingPathComponent("index")
        let fileURL = indexDir.appendingPathComponent("\(paper.id.uuidString).json")
        let data = try encoder.encode(paper)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadAll(from libraryRoot: URL) throws -> [Paper] {
        let indexDir = libraryRoot.appendingPathComponent("index")
        let contents = try FileManager.default.contentsOfDirectory(
            at: indexDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        return contents.compactMap { url in
            guard url.pathExtension == "json",
                  url.lastPathComponent != "_all.json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Paper.self, from: data)
        }
    }

    func rebuildCombinedIndex(from papers: [Paper], in libraryRoot: URL) throws {
        let allJsonURL = libraryRoot.appendingPathComponent("index/_all.json")
        let data = try encoder.encode(papers)
        try data.write(to: allJsonURL, options: .atomic)
    }

    func delete(_ paper: Paper, in libraryRoot: URL) throws {
        let fileURL = libraryRoot
            .appendingPathComponent("index")
            .appendingPathComponent("\(paper.id.uuidString).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func loadOne(at url: URL) throws -> Paper? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Paper.self, from: data)
    }
}
