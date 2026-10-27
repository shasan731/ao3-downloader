import AppKit
import Foundation
import PDFKit

struct PDFMergeInput: Sendable {
    let entry: SeriesEntry
    let work: Work
    let fileURL: URL
}

private final class PDFNavigationNode {
    let label: String
    let page: PDFPage
    let children: [PDFNavigationNode]

    init(label: String, page: PDFPage, children: [PDFNavigationNode] = []) {
        self.label = label
        self.page = page
        self.children = children
    }
}

private struct PDFOutlineDescriptor {
    let label: String
    let pageIndex: Int?
    let children: [PDFOutlineDescriptor]
}

private struct PDFContentsRow {
    let label: String
    let level: Int
    let page: PDFPage
}

struct PDFMerger: Sendable {
    private let legacyCoverMarker = "AO3Downloader:ManagedCover"
    private let managedPagePrefix = "AO3Downloader:FrontMatter:"
    private let pageSize = NSSize(width: 612, height: 792)

    func merge(_ inputs: [PDFMergeInput], metadata: EditableBookMetadata? = nil,
               asAnthology: Bool = false, to outputURL: URL) throws {
        guard !inputs.isEmpty else { throw AO3Error.mergeFailed("no PDF works were supplied") }
        let output = PDFDocument()
        var navigation: [PDFNavigationNode] = []
        var importedManagedBook = false

        for input in inputs.sorted(by: { $0.entry.position < $1.entry.position }) {
            try Task.checkCancellation()
            guard let source = PDFDocument(url: input.fileURL), !source.isLocked, source.pageCount > 0 else {
                throw AO3Error.mergeFailed("part \(input.entry.position), \(input.work.title), is malformed or password-protected")
            }
            let descriptors = outlineDescriptors(from: source.outlineRoot, in: source)
            let creator = source.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String
            let appCreated = creator == "ArchiveBind" || creator == "AO3 Downloader"
            let editingManagedBook = metadata != nil && inputs.count == 1
                && ((appCreated && containsCurrentFrontMatter(source)) || containsLegacyCover(source))
            importedManagedBook = importedManagedBook || editingManagedBook
            var pageMap: [Int: PDFPage] = [:]

            for index in 0..<source.pageCount {
                try Task.checkCancellation()
                guard let page = source.page(at: index) else {
                    throw AO3Error.mergeFailed("part \(input.entry.position) has an unreadable page")
                }
                if metadata != nil && inputs.count == 1
                    && (isLegacyCover(page) || (appCreated && isCurrentFrontMatter(page))) { continue }
                output.insert(page, at: output.pageCount)
                guard let inserted = output.page(at: output.pageCount - 1) else {
                    throw AO3Error.mergeFailed("part \(input.entry.position) could not be added to the combined PDF")
                }
                pageMap[index] = inserted
            }

            var importedNavigation = navigationNodes(from: descriptors, pageMap: pageMap)
                .filter { !isGenericFrontMatterLabel($0.label) }
            if importedNavigation.count == 1,
               normalized(importedNavigation[0].label) == normalized(input.work.title),
               !importedNavigation[0].children.isEmpty {
                importedNavigation = importedNavigation[0].children
            }
            if editingManagedBook, !importedNavigation.isEmpty {
                navigation.append(contentsOf: importedNavigation)
            } else if let firstPage = pageMap.keys.sorted().first.flatMap({ pageMap[$0] }) {
                let label = asAnthology || inputs.count > 1
                    ? "Book \(input.entry.position): \(input.work.title)" : input.work.title
                navigation.append(.init(label: label,
                                        page: firstPage, children: importedNavigation))
            } else {
                throw AO3Error.mergeFailed("part \(input.entry.position) contains no readable body pages")
            }
        }

        let fallbackAuthors = Array(Set(inputs.flatMap { $0.work.creators })).sorted()
        let customAuthors = metadata?.authors ?? []
        let authors = customAuthors.isEmpty ? fallbackAuthors : customAuthors
        let title = metadata?.title ?? (inputs.count == 1 ? inputs[0].work.title : "Collected Works")
        var frontMatter: [PDFPage] = []

        if let coverURL = metadata?.coverImageURL {
            guard let image = NSImage(contentsOf: coverURL), let page = PDFPage(image: image) else {
                throw AO3Error.mergeFailed("cover image must be a readable JPEG or PNG")
            }
            mark(page, as: "cover")
            frontMatter.append(page)
        }
        frontMatter.append(try titlePage(title: title, authors: authors,
                                         isAnthology: asAnthology || inputs.count > 1 || importedManagedBook))
        let contents = try contentsPages(title: title, navigation: navigation, in: output,
                                         precedingPageCount: frontMatter.count)
        frontMatter.append(contentsOf: contents)
        for (index, page) in frontMatter.enumerated() { output.insert(page, at: index) }

        output.outlineRoot = outlineRoot(titlePage: frontMatter.first(where: { marker(on: $0) == "title" }),
                                         contentsPage: contents.first, navigation: navigation)
        output.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: title,
            PDFDocumentAttribute.authorAttribute: (authors.isEmpty ? ["Unknown Creator"] : authors).joined(separator: ", "),
            PDFDocumentAttribute.creatorAttribute: "ArchiveBind"
        ]

        let expectedPages = output.pageCount
        guard output.write(to: outputURL), let verification = PDFDocument(url: outputURL),
              verification.pageCount == expectedPages,
              (verification.outlineRoot?.numberOfChildren ?? 0) >= navigation.count else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AO3Error.mergeFailed("the merged PDF failed page-count or navigation verification")
        }
    }

    private func containsCurrentFrontMatter(_ document: PDFDocument) -> Bool {
        (0..<document.pageCount).contains { index in
            document.page(at: index).map(isCurrentFrontMatter) ?? false
        }
    }

    private func containsLegacyCover(_ document: PDFDocument) -> Bool {
        document.page(at: 0).map(isLegacyCover) ?? false
    }

    private func isCurrentFrontMatter(_ page: PDFPage) -> Bool {
        page.annotations.contains { $0.contents?.hasPrefix(managedPagePrefix) == true }
    }

    private func isLegacyCover(_ page: PDFPage) -> Bool {
        page.annotations.contains { $0.contents == legacyCoverMarker }
    }

    private func marker(on page: PDFPage) -> String? {
        page.annotations.compactMap(\.contents).first(where: { $0.hasPrefix(managedPagePrefix) })
            .map { String($0.dropFirst(managedPagePrefix.count)) }
    }

    private func mark(_ page: PDFPage, as kind: String) {
        let marker = PDFAnnotation(bounds: .zero, forType: .text, withProperties: nil)
        marker.contents = managedPagePrefix + kind
        page.addAnnotation(marker)
    }

    private func outlineDescriptors(from root: PDFOutline?, in document: PDFDocument) -> [PDFOutlineDescriptor] {
        guard let root else { return [] }
        return (0..<root.numberOfChildren).compactMap { index in
            root.child(at: index).map { descriptor(from: $0, in: document) }
        }
    }

    private func descriptor(from outline: PDFOutline, in document: PDFDocument) -> PDFOutlineDescriptor {
        let pageIndex: Int?
        if let page = outline.destination?.page {
            let index = document.index(for: page)
            pageIndex = index == NSNotFound ? nil : index
        } else {
            pageIndex = nil
        }
        let children = (0..<outline.numberOfChildren).compactMap { index in
            outline.child(at: index).map { descriptor(from: $0, in: document) }
        }
        return .init(label: outline.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                     pageIndex: pageIndex, children: children)
    }

    private func navigationNodes(from descriptors: [PDFOutlineDescriptor], pageMap: [Int: PDFPage]) -> [PDFNavigationNode] {
        descriptors.flatMap { descriptor -> [PDFNavigationNode] in
            let children = navigationNodes(from: descriptor.children, pageMap: pageMap)
            let destination = descriptor.pageIndex.flatMap { pageMap[$0] } ?? children.first?.page
            guard let destination else { return children }
            let label = descriptor.label.isEmpty ? (children.first?.label ?? "Chapter") : descriptor.label
            return [.init(label: label, page: destination, children: children)]
        }
    }

    private func isGenericFrontMatterLabel(_ label: String) -> Bool {
        ["cover", "title page", "contents", "table of contents"].contains(normalized(label))
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func titlePage(title: String, authors: [String], isAnthology: Bool) throws -> PDFPage {
        let page = try illustratedPage { rect in
            draw(isAnthology ? "A SERIES ANTHOLOGY" : "A COMPLETE WORK",
                 in: NSRect(x: 72, y: rect.height - 150, width: rect.width - 144, height: 24),
                 font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor, alignment: .center)
            draw(title, in: NSRect(x: 62, y: rect.height / 2, width: rect.width - 124, height: 150),
                 font: .systemFont(ofSize: 34, weight: .regular), color: .labelColor, alignment: .center)
            draw("◆", in: NSRect(x: 72, y: rect.height / 2 - 45, width: rect.width - 144, height: 30),
                 font: .systemFont(ofSize: 16), color: .secondaryLabelColor, alignment: .center)
            let byline = authors.isEmpty ? "Unknown Creator" : "by " + authors.joined(separator: ", ")
            draw(byline, in: NSRect(x: 72, y: rect.height / 2 - 105, width: rect.width - 144, height: 55),
                 font: .systemFont(ofSize: 17), color: .labelColor, alignment: .center)
            draw("Bound with ArchiveBind", in: NSRect(x: 72, y: 55, width: rect.width - 144, height: 24),
                 font: .systemFont(ofSize: 9), color: .secondaryLabelColor, alignment: .center)
        }
        mark(page, as: "title")
        return page
    }

    private func contentsPages(title: String, navigation: [PDFNavigationNode], in document: PDFDocument,
                               precedingPageCount: Int) throws -> [PDFPage] {
        let rows = flattened(navigation)
        let chunks = chunk(rows)
        let pages = chunks.isEmpty ? [[]] : chunks
        let totalFrontMatter = precedingPageCount + pages.count
        return try pages.enumerated().map { pageIndex, pageRows in
            let page = try illustratedPage { rect in
                draw(pageIndex == 0 ? "CONTENTS" : "CONTENTS — CONTINUED",
                     in: NSRect(x: 56, y: rect.height - 92, width: rect.width - 112, height: 38),
                     font: .systemFont(ofSize: pageIndex == 0 ? 26 : 17, weight: .medium),
                     color: .labelColor, alignment: .left)
                if pageIndex == 0 {
                    draw(title, in: NSRect(x: 56, y: rect.height - 122, width: rect.width - 112, height: 22),
                         font: .systemFont(ofSize: 10), color: .secondaryLabelColor, alignment: .left)
                }
                var y = rect.height - 160
                for row in pageRows {
                    let height: CGFloat = row.level == 0 ? 27 : 22
                    let indent = CGFloat(row.level) * 22
                    let destinationIndex = document.index(for: row.page)
                    let pageNumber = destinationIndex == NSNotFound ? "" : String(destinationIndex + totalFrontMatter + 1)
                    draw(row.label, in: NSRect(x: 60 + indent, y: y - height, width: rect.width - 155 - indent, height: height),
                         font: .systemFont(ofSize: row.level == 0 ? 12.5 : 10.5,
                                          weight: row.level == 0 ? .semibold : .regular),
                         color: row.level == 0 ? .labelColor : .darkGray, alignment: .left,
                         lineBreakMode: .byTruncatingTail)
                    draw(pageNumber, in: NSRect(x: rect.width - 90, y: y - height, width: 34, height: height),
                         font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular), color: .darkGray, alignment: .right)
                    y -= height
                }
            }
            mark(page, as: "contents")
            var y = pageSize.height - 160
            for row in pageRows {
                let height: CGFloat = row.level == 0 ? 27 : 22
                let link = PDFAnnotation(bounds: NSRect(x: 56, y: y - height, width: pageSize.width - 112, height: height),
                                         forType: .link, withProperties: nil)
                link.destination = destination(for: row.page)
                page.addAnnotation(link)
                y -= height
            }
            return page
        }
    }

    private func flattened(_ nodes: [PDFNavigationNode], level: Int = 0) -> [PDFContentsRow] {
        nodes.flatMap { node in
            [.init(label: node.label, level: level, page: node.page)] + flattened(node.children, level: level + 1)
        }
    }

    private func chunk(_ rows: [PDFContentsRow]) -> [[PDFContentsRow]] {
        var result: [[PDFContentsRow]] = []
        var current: [PDFContentsRow] = []
        var used: CGFloat = 0
        let available: CGFloat = pageSize.height - 220
        for row in rows {
            let height: CGFloat = row.level == 0 ? 27 : 22
            if used + height > available, !current.isEmpty {
                result.append(current)
                current = []
                used = 0
            }
            current.append(row)
            used += height
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func outlineRoot(titlePage: PDFPage?, contentsPage: PDFPage?,
                             navigation: [PDFNavigationNode]) -> PDFOutline {
        let root = PDFOutline()
        if let titlePage {
            let title = PDFOutline(); title.label = "Title Page"; title.destination = destination(for: titlePage)
            root.insertChild(title, at: root.numberOfChildren)
        }
        if let contentsPage {
            let contents = PDFOutline(); contents.label = "Contents"; contents.destination = destination(for: contentsPage)
            root.insertChild(contents, at: root.numberOfChildren)
        }
        for node in navigation { root.insertChild(outline(for: node), at: root.numberOfChildren) }
        return root
    }

    private func outline(for node: PDFNavigationNode) -> PDFOutline {
        let outline = PDFOutline()
        outline.label = node.label
        outline.destination = destination(for: node.page)
        outline.isOpen = false
        for child in node.children { outline.insertChild(self.outline(for: child), at: outline.numberOfChildren) }
        return outline
    }

    private func destination(for page: PDFPage) -> PDFDestination {
        PDFDestination(page: page, at: NSPoint(x: 0, y: page.bounds(for: .mediaBox).height))
    }

    private func illustratedPage(_ drawing: @escaping (NSRect) -> Void) throws -> PDFPage {
        let image = NSImage(size: pageSize, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            drawing(rect)
            return true
        }
        guard let page = PDFPage(image: image) else { throw AO3Error.mergeFailed("could not create book front matter") }
        return page
    }

    private func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor,
                      alignment: NSTextAlignment, lineBreakMode: NSLineBreakMode = .byWordWrapping) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]).draw(in: rect)
    }
}
