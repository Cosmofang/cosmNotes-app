import CosmNotesUpdates
import Foundation

private let repository = "Cosmofang/cosmNotes-app"

private enum CheckFailure: Error {
    case assertion(String)
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure.assertion(message) }
}

private func release(_ tag: String, prerelease: Bool = false, draft: Bool = false,
                     archiveState: String? = "uploaded") throws -> GitHubRelease {
    let assets = archiveState.map { state in
        [["name": "cosmNotes-\(tag)-macOS.zip", "state": state,
          "browser_download_url": "https://example.invalid/ignored.zip"]]
    } ?? []
    let object: [String: Any] = ["tag_name": tag, "prerelease": prerelease, "draft": draft, "assets": assets]
    return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: object))
}

do {
    let candidate = try release("v0.5.10")
    let update = try candidate.update(repository: repository, installedVersion: "0.5.9")
    try check(update?.version == "0.5.10", "compares version components numerically")
    try check(update?.downloadURL.absoluteString ==
              "https://github.com/Cosmofang/cosmNotes-app/releases/download/v0.5.10/cosmNotes-v0.5.10-macOS.zip",
              "uses the expected official repository asset URL")
    try check(try candidate.update(repository: repository, installedVersion: "0.5.10") == nil,
              "does not prompt for the installed version")
    try check(try candidate.update(repository: repository, installedVersion: "0.6.0") == nil,
              "does not prompt for a downgrade")
    let prerelease = try release("v1.0.0-rc.1", prerelease: true)
    let draft = try release("v1.0.0", draft: true)
    try check(try prerelease.update(repository: repository, installedVersion: "0.5.9") == nil &&
              draft.update(repository: repository, installedVersion: "0.5.9") == nil,
              "skips pre-releases and drafts")
    for invalid in try [release("v0.5.10", archiveState: nil), release("v0.5.10", archiveState: "new"),
                        release("v0.5.xyz"), release("v01.0.0")] {
        do {
            _ = try invalid.update(repository: repository, installedVersion: "0.5.9")
            throw CheckFailure.assertion("download offered for an incomplete or invalid release")
        } catch let failure as CheckFailure {
            throw failure
        } catch {
            // An invalid tag or archive must not produce a download button.
        }
    }
    print("Update checks passed.")
} catch {
    FileHandle.standardError.write(Data("Update check failed: \(error)\n".utf8))
    exit(1)
}
