import Foundation

struct AO3URLParser: Sendable {
    private let host = "archiveofourown.org"

    func parse(_ input: String) throws -> AO3Link {
        guard let components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == host else { throw AO3Error.unsupportedHost }
        guard components.user == nil, components.password == nil, components.port == nil else {
            throw AO3Error.invalidURL("credentials and custom ports are not allowed")
        }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let kind: AO3LinkKind
        let id: String
        if parts.count >= 2, parts[0] == "works", parts[1].allSatisfy(\.isNumber) {
            kind = .work; id = parts[1]
            if parts.count > 2 && !(parts.count == 4 && parts[2] == "chapters" && parts[3].allSatisfy(\.isNumber)) {
                throw AO3Error.unsupportedPath
            }
        } else if parts.count == 2, parts[0] == "series", parts[1].allSatisfy(\.isNumber) {
            kind = .series; id = parts[1]
        } else { throw AO3Error.unsupportedPath }
        guard !id.isEmpty else { throw AO3Error.unsupportedPath }
        return AO3Link(kind: kind, id: id, canonicalURL: URL(string: "https://\(host)/\(kind == .work ? "works" : "series")/\(id)")!)
    }
}

