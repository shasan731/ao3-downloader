import Foundation

struct FanFictionURLParser: Sendable {
    private let host = "www.fanfiction.net"

    func parse(_ input: String) throws -> AO3Link {
        guard let components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == host else { throw AO3Error.unsupportedHost }
        guard components.user == nil, components.password == nil, components.port == nil else {
            throw AO3Error.invalidURL("credentials and custom ports are not allowed")
        }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts.count <= 4, parts[0] == "s",
              !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { throw AO3Error.unsupportedPath }
        if parts.count >= 3, !parts[2].allSatisfy(\.isNumber) { throw AO3Error.unsupportedPath }
        let id = parts[1]
        guard let canonical = URL(string: "https://\(host)/s/\(id)/1") else {
            throw AO3Error.invalidURL("could not create a canonical story address")
        }
        return AO3Link(kind: .work, id: id, canonicalURL: canonical)
    }
}
