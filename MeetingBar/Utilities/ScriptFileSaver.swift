import Foundation

enum ScriptFileSaveError: Error {
    case wrongDirectory
}

/// Commits editor settings only after the atomic file write succeeds.
/// File operations are injectable so permission failures can be tested without
/// modifying the user's Application Scripts directory or sandbox permissions.
struct ScriptFileSaver {
    var scriptsDirectory: () throws -> URL = {
        try FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
    var writeScript: (String, URL) throws -> Void = { source, url in
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    func save(
        source: String,
        name: String,
        directory: URL,
        expectedDirectory: URL,
        onSaved: (String, URL) -> Void
    ) throws {
        guard directory.standardizedFileURL == expectedDirectory.standardizedFileURL else {
            throw ScriptFileSaveError.wrongDirectory
        }
        try writeScript(source, directory.appendingPathComponent(name))
        onSaved(source, directory)
    }
}
