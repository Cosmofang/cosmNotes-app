import Foundation

/// The URL wakes the app. Only a matching request staged by a local client can create a row.
public enum WorkInbox {
    private struct CreateRequest: Decodable {
        let title: String
        let dueDate: String
        let notes: String
    }

    public static func applyCreate(id: UUID, directory: URL, store: WorkStore) throws -> WorkItem {
        let requestFile = directory.appendingPathComponent("work-requests", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased() + ".json")
        let data = try Data(contentsOf: requestFile)
        let request = try JSONDecoder().decode(CreateRequest.self, from: data)
        let item = try store.create(title: request.title, dueDate: request.dueDate,
                                    notes: request.notes, id: id)
        try? FileManager.default.removeItem(at: requestFile)
        return item
    }
}
