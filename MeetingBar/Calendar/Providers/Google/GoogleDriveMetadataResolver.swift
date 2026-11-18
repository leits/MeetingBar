//
//  GoogleDriveMetadataResolver.swift
//  MeetingBar
//
//  Replaces "Google Docs"-style fallback titles of Drive links in invites with
//  the file's real name and icon (#917). Uses the read-only
//  `drive.metadata.readonly` scope and requests only `name` and `iconLink`;
//  document contents are never fetched. Lookups are cached for the app's
//  lifetime (including failures, so inaccessible files are not retried on
//  every refresh).
//

import Foundation

@MainActor
final class GoogleDriveMetadataResolver {
    static let scope = "https://www.googleapis.com/auth/drive.metadata.readonly"

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias AccessToken = @MainActor () async throws -> String

    struct Metadata: Equatable {
        let name: String
        let iconURL: URL?
    }

    private let transport: Transport
    private let accessToken: AccessToken
    /// `nil` value = looked up and unavailable (no access, deleted, …).
    private var cache: [String: Metadata?] = [:]

    init(transport: @escaping Transport, accessToken: @escaping AccessToken) {
        self.transport = transport
        self.accessToken = accessToken
    }

    func resolveDocuments(in events: [MBEvent]) async -> [MBEvent] {
        let pendingIDs = Set(events.flatMap { event in
            event.documents.compactMap { $0.hasProvidedTitle ? nil : $0.googleFileID }
        }).filter { cache[$0] == nil }

        for fileID in pendingIDs {
            guard !Task.isCancelled else { break }
            cache[fileID] = .some(await fetchMetadata(fileID: fileID))
        }

        return events.map { event in
            var event = event
            event.documents = event.documents.map { document in
                guard !document.hasProvidedTitle,
                      let fileID = document.googleFileID,
                      let metadata = cache[fileID] ?? nil else { return document }
                return document.resolved(title: metadata.name, iconURL: metadata.iconURL)
            }
            return event
        }
    }

    private func fetchMetadata(fileID: String) async -> Metadata? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.path += "/" + fileID
        components.queryItems = [
            URLQueryItem(name: "fields", value: "name,iconLink"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
            let (data, response) = try await transport(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String, !name.isEmpty else {
                return nil
            }
            let iconURL = (json["iconLink"] as? String).flatMap(URL.init(string:))
            return Metadata(name: name, iconURL: iconURL)
        } catch {
            MeetingBarLogger.calendar.debug("Drive metadata lookup failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}
