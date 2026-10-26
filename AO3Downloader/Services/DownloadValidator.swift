import Foundation
import ZIPFoundation

struct DownloadValidator {
    func validate(file: URL, format: DownloadFormat) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else { throw AO3Error.invalidDownload("empty file") }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let signature = try handle.read(upToCount: 8) ?? Data()
        switch format {
        case .pdf:
            guard signature.starts(with: Data("%PDF-".utf8)) else { throw AO3Error.invalidDownload("not a PDF") }
        case .epub:
            guard signature.starts(with: Data([0x50, 0x4b])) else { throw AO3Error.invalidDownload("not a ZIP archive") }
            guard let archive = Archive(url: file, accessMode: .read), archive["mimetype"] != nil,
                  archive["META-INF/container.xml"] != nil else { throw AO3Error.invalidDownload("missing EPUB structure") }
        case .html:
            let lower = String(data: signature, encoding: .utf8)?.lowercased() ?? ""
            guard lower.contains("<") else { throw AO3Error.invalidDownload("not HTML") }
        }
    }
}

