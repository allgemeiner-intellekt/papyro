// Papyro/Services/FileService.swift
import Foundation

struct FileService: Sendable {
    func copyToLibrary(source: URL, libraryRoot: URL) throws -> (URL, UUID) {
        let paperId = UUID()
        let destination = libraryRoot
            .appendingPathComponent("papers")
            .appendingPathComponent("\(paperId.uuidString).pdf")
        try FileManager.default.copyItem(at: source, to: destination)
        return (destination, paperId)
    }

    func renamePDF(from currentURL: URL, to newName: String) throws -> URL {
        let dir = currentURL.deletingLastPathComponent()
        let stem = (newName as NSString).deletingPathExtension
        let ext = (newName as NSString).pathExtension

        var candidate = dir.appendingPathComponent(newName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffixed = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidate = dir.appendingPathComponent(suffixed)
            counter += 1
        }

        try FileManager.default.moveItem(at: currentURL, to: candidate)
        return candidate
    }

    func generateFilename(year: Int?, author: String?, title: String) -> String {
        let yearPart = year.map(String.init) ?? "unknown"
        let authorPart = slugify(author ?? "unknown")
        let titlePart = slugify(title)
        let stem = "\(yearPart)_\(authorPart)_\(titlePart)"
        let maxLength = 80
        let truncated = stem.count > maxLength ? String(stem.prefix(maxLength)) : stem
        return "\(truncated).pdf"
    }

    private func slugify(_ text: String) -> String {
        // Normalize diacritics, then lowercase
        let normalized = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        // Remove characters that are not a-z, 0-9, space, or hyphen
        var result = ""
        for char in normalized {
            if char.isLetter || char.isNumber || char == " " || char == "-" {
                result.append(char)
            }
        }

        // Collapse runs of whitespace/hyphens into a single hyphen
        var collapsed = ""
        var lastWasSep = false
        for char in result {
            let isSep = char == " " || char == "-"
            if isSep {
                if !lastWasSep {
                    collapsed.append("-")
                }
                lastWasSep = true
            } else {
                collapsed.append(char)
                lastWasSep = false
            }
        }

        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
