import Foundation
import XCTest

@testable import MeetingBar

final class ScriptFileSaverTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/MeetingBar-script-tests", isDirectory: true)

    func testSettingsAreCommittedOnlyAfterWritingTheDraft() throws {
        var saver = ScriptFileSaver()
        var calls: [String] = []
        saver.writeScript = { source, url in
            XCTAssertEqual(source, "new draft")
            XCTAssertEqual(url.lastPathComponent, "eventStartScript.scpt")
            calls.append("write")
        }

        try saver.save(
            source: "new draft", name: "eventStartScript.scpt",
            directory: directory, expectedDirectory: directory
        ) { source, savedDirectory in
            XCTAssertEqual(source, "new draft")
            XCTAssertEqual(savedDirectory, directory)
            calls.append("commit")
        }

        XCTAssertEqual(calls, ["write", "commit"])
    }

    func testPermissionFailurePreservesSavedSettingsAndDraftForRetry() throws {
        let draft = "unsaved draft"
        var savedScript = "original"
        var savedDirectory: URL?
        var saver = ScriptFileSaver()
        saver.writeScript = { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }
        let commit: (String, URL) -> Void = { source, directory in
            savedScript = source
            savedDirectory = directory
        }

        XCTAssertThrowsError(try saver.save(
            source: draft, name: "eventStartScript.scpt",
            directory: directory, expectedDirectory: directory, onSaved: commit
        )) { error in
            XCTAssertEqual((error as NSError).code, NSFileWriteNoPermissionError)
        }
        XCTAssertEqual(savedScript, "original")
        XCTAssertNil(savedDirectory)

        saver.writeScript = { source, _ in XCTAssertEqual(source, draft) }
        try saver.save(
            source: draft, name: "eventStartScript.scpt",
            directory: directory, expectedDirectory: directory, onSaved: commit
        )
        XCTAssertEqual(savedScript, draft)
        XCTAssertEqual(savedDirectory, directory)
    }

    func testWrongDirectoryDoesNotWriteOrCommit() {
        var saver = ScriptFileSaver()
        saver.writeScript = { _, _ in XCTFail("Must not write outside Application Scripts") }

        XCTAssertThrowsError(try saver.save(
            source: "draft", name: "eventStartScript.scpt",
            directory: directory.appendingPathComponent("other", isDirectory: true),
            expectedDirectory: directory
        ) { _, _ in XCTFail("Must not commit a rejected directory") }) { error in
            guard let error = error as? ScriptFileSaveError, case .wrongDirectory = error else {
                return XCTFail("Expected wrong-directory error, got \(error)")
            }
        }
    }

    func testDirectoryPreparationSurfacesPermissionFailure() {
        var saver = ScriptFileSaver()
        var presentedError: NSError?
        saver.scriptsDirectory = {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }

        saver.writeScript = { _, _ in XCTFail("Must not write after directory lookup fails") }
        let preparedDirectory = saver.prepareDirectory { error in
            presentedError = error as NSError
        }

        XCTAssertNil(preparedDirectory)
        XCTAssertEqual(presentedError?.domain, NSCocoaErrorDomain)
        XCTAssertEqual(presentedError?.code, NSFileWriteNoPermissionError)
    }

    func testDirectoryPreparationReturnsTheDirectoryWithoutPresentingAnError() {
        var saver = ScriptFileSaver()
        saver.scriptsDirectory = { self.directory }

        XCTAssertEqual(saver.prepareDirectory { _ in XCTFail("Unexpected directory failure") }, directory)
    }

    func testDefaultWriterAtomicallyReplacesUTF8Script() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let file = temporaryDirectory.appendingPathComponent("eventStartScript.scpt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let source = "-- Привіт\ntell application \"Music\" to pause"
        var committed = false

        try ScriptFileSaver().save(
            source: source, name: "eventStartScript.scpt",
            directory: temporaryDirectory, expectedDirectory: temporaryDirectory
        ) { _, _ in committed = true }

        XCTAssertTrue(committed)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), source)
    }
}
