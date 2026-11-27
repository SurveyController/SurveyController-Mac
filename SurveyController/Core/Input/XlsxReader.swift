import Foundation
import zlib

enum XlsxReader {
    enum ReadError: LocalizedError {
        case invalidWorkbook

        var errorDescription: String? { "无法读取 Excel 工作簿，请检查文件是否为有效的 .xlsx" }
    }

    static func read(_ url: URL) throws -> [[Int: String]] {
        let archive = try Archive(Data(contentsOf: url, options: .mappedIfSafe))
        let workbook = try archive.data(for: "xl/workbook.xml")
        let relationships = try archive.data(for: "xl/_rels/workbook.xml.rels")
        let sheet = try worksheetPath(workbook, relationships)
        let sheetPath = [sheet, "xl/worksheets/sheet1.xml"]
            .compactMap { $0 }
            .first { archive.entries[$0] != nil }
            ?? archive.entries.keys.sorted().first { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
        guard let sheetPath, let xml = try archive.data(for: sheetPath) else { throw ReadError.invalidWorkbook }

        let shared = try archive.data(for: "xl/sharedStrings.xml").map {
            try parse($0, using: SharedStrings()).strings
        } ?? []
        return try parse(xml, using: Worksheet(shared: shared)).rows
    }

    private static func worksheetPath(_ workbook: Data?, _ relationships: Data?) throws -> String? {
        guard let workbook, let relationships else { return nil }
        let directory = try parse(workbook, using: WorkbookDirectory())
        let targets = try parse(relationships, using: WorkbookDirectory())
        guard let sheetID = directory.sheetID, let target = targets.targets[sheetID] else { return nil }
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        if target.hasPrefix("xl/") { return target }
        return ("xl/" + target as NSString).standardizingPath
    }

    private static func parse<Handler: XMLParserDelegate>(_ xml: Data, using handler: Handler) throws -> Handler {
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        guard parser.parse() else { throw ReadError.invalidWorkbook }
        return handler
    }

    private final class WorkbookDirectory: NSObject, XMLParserDelegate {
        var sheetID: String?
        var targets: [String: String] = [:]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "sheet", sheetID == nil { sheetID = attributes["r:id"] ?? attributes["id"] }
            if name == "Relationship", attributes["TargetMode"] != "External",
               let id = attributes["Id"], let target = attributes["Target"] {
                targets[id] = target.replacingOccurrences(of: "\\", with: "/")
            }
        }
    }

    private final class SharedStrings: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var text = ""
        private var inText = false
        private var inPhonetic = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "si": text = ""
            case "rPh": inPhonetic = true
            case "t": inText = !inPhonetic
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "t": inText = false
            case "rPh": inPhonetic = false
            case "si": strings.append(text)
            default: break
            }
        }
    }

    private final class Worksheet: NSObject, XMLParserDelegate {
        let shared: [String]
        var rows: [[Int: String]] = []
        private var rowNumber = 1
        private var row: [Int: String] = [:]
        private var nextColumn = 0
        private var column = 0
        private var type = ""
        private var text = ""
        private var inCell = false
        private var inText = false

        init(shared: [String]) {
            self.shared = shared
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "row":
                rowNumber = Int(attributes["r"] ?? "") ?? rows.count + 1
                guard (1...1_048_576).contains(rowNumber), rowNumber > rows.count else {
                    parser.abortParsing()
                    return
                }
                row = [:]
                nextColumn = 0
            case "c":
                inCell = true
                column = attributes["r"].flatMap(Self.columnIndex) ?? nextColumn
                type = attributes["t"] ?? ""
                text = ""
            case "v", "t": inText = inCell
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": inText = false
            case "c":
                inCell = false
                if type == "s", let index = Int(text), shared.indices.contains(index) {
                    row[column] = shared[index]
                } else if type != "s" && type != "e" {
                    row[column] = text
                }
                nextColumn = column + 1
            case "row":
                if rowNumber > rows.count + 1 { rows.append(contentsOf: repeatElement([:], count: rowNumber - rows.count - 1)) }
                rows.append(row)
            default: break
            }
        }

        private static func columnIndex(_ address: String) -> Int? {
            let letters = address.utf8.prefix { (65...90).contains($0) }
            guard !letters.isEmpty, letters.count <= 3 else { return nil }
            return letters.reduce(0) { $0 * 26 + Int($1) - 64 } - 1
        }
    }

    private struct Archive {
        struct Entry {
            let offset: Int
            let compressedSize: Int
            let size: Int
            let method: Int
            let flags: Int
        }

        let archive: Data
        let entries: [String: Entry]

        init(_ archive: Data) throws {
            self.archive = archive
            guard archive.count >= 22 else { throw ReadError.invalidWorkbook }
            let minimum = max(0, archive.count - 65_557)
            guard let end = stride(from: archive.count - 22, through: minimum, by: -1).first(where: {
                archive.u32($0) == 0x06054b50 && $0 + 22 + archive.u16($0 + 20) == archive.count
            }) else { throw ReadError.invalidWorkbook }

            let count = archive.u16(end + 10)
            var offset = archive.u32(end + 16)
            var directory: [String: Entry] = [:]
            for _ in 0..<count {
                guard offset <= end - 46, archive.u32(offset) == 0x02014b50 else { throw ReadError.invalidWorkbook }
                let pathLength = archive.u16(offset + 28)
                let next = offset + 46 + pathLength + archive.u16(offset + 30) + archive.u16(offset + 32)
                guard next <= end else { throw ReadError.invalidWorkbook }

                if let name = String(data: archive.subdata(in: (offset + 46)..<(offset + 46 + pathLength)), encoding: .utf8) {
                    directory[name] = Entry(
                        offset: archive.u32(offset + 42),
                        compressedSize: archive.u32(offset + 20),
                        size: archive.u32(offset + 24),
                        method: archive.u16(offset + 10),
                        flags: archive.u16(offset + 8)
                    )
                }
                offset = next
            }
            entries = directory
        }

        func data(for path: String) throws -> Data? {
            guard let entry = entries[path] else { return nil }
            let offset = entry.offset
            guard offset <= archive.count - 30, archive.u32(offset) == 0x04034b50,
                  entry.flags & 1 == 0, entry.size <= 128 * 1024 * 1024 else { throw ReadError.invalidWorkbook }
            let dataOffset = offset + 30 + archive.u16(offset + 26) + archive.u16(offset + 28)
            guard dataOffset <= archive.count - entry.compressedSize else { throw ReadError.invalidWorkbook }
            let compressed = archive.subdata(in: dataOffset..<(dataOffset + entry.compressedSize))
            if entry.method == 0, entry.compressedSize == entry.size { return compressed }
            guard entry.method == 8, entry.size > 0 else { throw ReadError.invalidWorkbook }

            var result = Data(count: entry.size)
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw ReadError.invalidWorkbook
            }
            defer { inflateEnd(&stream) }
            let status = compressed.withUnsafeBytes { source in
                result.withUnsafeMutableBytes { output in
                    stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(source.count)
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END, stream.total_out == entry.size else { throw ReadError.invalidWorkbook }
            return result
        }
    }
}

private extension Data {
    func u16(_ offset: Int) -> Int {
        Int(self[offset]) | (Int(self[offset + 1]) << 8)
    }

    func u32(_ offset: Int) -> Int {
        u16(offset) | (u16(offset + 2) << 16)
    }
}
