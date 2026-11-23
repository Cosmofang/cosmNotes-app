import Foundation

public struct ReleaseUpdate: Equatable {
    public let version: String
    public let downloadURL: URL
}

public struct GitHubRelease: Decodable {
    private struct Asset: Decodable {
        let name: String
        let state: String
    }

    private let tagName: String
    private let draft: Bool
    private let prerelease: Bool
    private let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, assets
    }

    public static func check(repository: String, installedVersion: String) async throws -> ReleaseUpdate? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("cosmNotes/\(installedVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(Self.self, from: data)
        return try release.update(repository: repository, installedVersion: installedVersion)
    }

    public func update(repository: String, installedVersion: String) throws -> ReleaseUpdate? {
        guard !draft, !prerelease else { return nil }
        guard let installed = Version(installedVersion),
              tagName.hasPrefix("v"),
              let latest = Version(String(tagName.dropFirst())),
              tagName == "v\(latest.description)" else {
            throw ReleaseError.invalidVersion
        }
        guard latest > installed else { return nil }

        let archive = "cosmNotes-\(tagName)-macOS.zip"
        guard assets.contains(where: { $0.name == archive && $0.state == "uploaded" }) else {
            throw ReleaseError.missingArchive
        }
        guard let url = URL(string: "https://github.com/\(repository)/releases/download/\(tagName)/\(archive)") else {
            throw URLError(.badURL)
        }
        return ReleaseUpdate(version: latest.description, downloadURL: url)
    }
}

private struct Version: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(part)
        }
        guard numbers.count == 3 else { return nil }
        components = numbers
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

private enum ReleaseError: LocalizedError {
    case invalidVersion
    case missingArchive

    var errorDescription: String? {
        switch self {
        case .invalidVersion: return "无法识别版本号。"
        case .missingArchive: return "新版安装包尚未发布。"
        }
    }
}
