import Combine
import Foundation

/// A deadline is a calendar day. Saving it without a time zone keeps the displayed date stable.
public enum WorkDay {
    public static func local(_ date: Date = Date()) -> String {
        formatter().string(from: date)
    }

    public static func parse(_ value: String) -> Date? {
        guard value.utf8.count == 10 else { return nil }
        let formatter = formatter()
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            return nil
        }
        return date
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

public struct WorkItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var dueDate: String
    public var notes: String
    public let createdAt: Date
    public var completedAt: Date?
    // Older work files have no pin field. Leave it absent for unpinned work.
    fileprivate var pinned: Bool?
    public fileprivate(set) var projectID: UUID?
    fileprivate var manualOrder: WorkManualOrder?

    public var isPinned: Bool { pinned == true }
}

fileprivate struct WorkManualOrder: Codable, Equatable {
    let section: WorkSection
    let position: Int
}

public enum WorkProjectColor: String, Codable, CaseIterable {
    case blue, teal, green, orange, red, pink, purple, gray
}

public struct WorkProject: Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    private let storedColor: WorkProjectColor?

    public var color: WorkProjectColor { storedColor ?? .blue }

    fileprivate init(id: UUID, name: String, color: WorkProjectColor) {
        self.id = id
        self.name = name
        storedColor = color
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case storedColor = "color"
    }
}

public enum WorkSection: String, CaseIterable, Identifiable, Codable {
    case pinned, overdue, today, upcoming, completed

    public var id: Self { self }

    public static func grouped(_ items: [WorkItem], today: String) -> [Self: [WorkItem]] {
        let groups = Dictionary(grouping: items) { containing($0, today: today) }
        return Dictionary(uniqueKeysWithValues: groups.map { section, rows in
            (section, section.ordered(rows))
        })
    }

    fileprivate static func containing(_ item: WorkItem, today: String) -> Self {
        if item.completedAt != nil { return .completed }
        if item.isPinned { return .pinned }
        if item.dueDate < today { return .overdue }
        if item.dueDate == today { return .today }
        return .upcoming
    }

    fileprivate func ordered(_ rows: [WorkItem]) -> [WorkItem] {
        let byPriority = rows.sorted { left, right in
            if let leftCompletion = left.completedAt, let rightCompletion = right.completedAt,
               leftCompletion != rightCompletion {
                return leftCompletion > rightCompletion
            }
            if left.dueDate != right.dueDate { return left.dueDate < right.dueDate }
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.id.uuidString < right.id.uuidString
        }

        let manuallyOrdered = byPriority.filter { $0.manualOrder?.section == self }
        guard manuallyOrdered.count > 1 else { return byPriority }
        var ranked = manuallyOrdered.sorted {
            ($0.manualOrder?.position ?? Int.max) < ($1.manualOrder?.position ?? Int.max)
        }.makeIterator()

        // Keep the default slots for work that has not been reordered in this section.
        return byPriority.map { item in
            item.manualOrder?.section == self ? (ranked.next() ?? item) : item
        }
    }
}

/// Keeps the last persisted state. The app owns this store and makes changes on its main thread.
public final class WorkStore: ObservableObject {
    @Published public private(set) var items: [WorkItem] = []
    @Published public private(set) var projects: [WorkProject] = []
    @Published public private(set) var loadError: String?
    @Published public private(set) var projectLoadError: String?
    private let fileURL: URL
    private let projectFileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        projectFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("work-projects.json")
        do {
            let saved = try JSONDecoder().decode([WorkItem].self, from: Data(contentsOf: fileURL))
            guard Set(saved.map(\.id)).count == saved.count else { throw WorkError.duplicateID }
            for item in saved {
                _ = try Self.validatedTitle(item.title, dueDate: item.dueDate, notes: item.notes)
            }
            items = saved
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A new store is saved on its first edit.
        } catch {
            loadError = "无法读取工作记录。\(error.localizedDescription)"
        }
        do {
            let saved = try JSONDecoder().decode([WorkProject].self, from: Data(contentsOf: projectFileURL))
            guard Set(saved.map(\.id)).count == saved.count else { throw WorkError.duplicateID }
            var names: Set<String> = []
            for project in saved {
                let name = try Self.validatedProjectName(project.name)
                guard names.insert(Self.projectNameKey(name)).inserted else {
                    throw WorkError.duplicateProjectName
                }
            }
            projects = saved
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Work saved before projects were introduced is unassigned.
        } catch {
            projectLoadError = "无法读取项目。\(error.localizedDescription)"
        }
    }

    @discardableResult
    public func createProject(name: String, color: WorkProjectColor = .blue) throws -> WorkProject {
        let name = try availableProjectName(name)
        let project = WorkProject(id: UUID(), name: name, color: color)
        try saveProjects(projects + [project])
        return project
    }

    public func updateProject(id: UUID, name: String, color: WorkProjectColor) throws {
        let name = try availableProjectName(name, excluding: id)
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw WorkError.projectNotFound
        }
        var next = projects
        next[index] = WorkProject(id: id, name: name, color: color)
        guard next[index] != projects[index] else { return }
        try saveProjects(next)
    }

    public func moveProject(id: UUID, relativeTo targetID: UUID, after: Bool) throws {
        if let projectLoadError { throw WorkError.unreadableStore(projectLoadError) }
        guard let sourceIndex = projects.firstIndex(where: { $0.id == id }),
              let targetIndex = projects.firstIndex(where: { $0.id == targetID }) else {
            throw WorkError.projectNotFound
        }
        guard sourceIndex != targetIndex else { return }

        let targetAfterRemoval = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        let insertionIndex = after ? targetAfterRemoval + 1 : targetAfterRemoval
        guard sourceIndex != insertionIndex else { return }

        var reordered = projects
        let project = reordered.remove(at: sourceIndex)
        reordered.insert(project, at: insertionIndex)
        try saveProjects(reordered)
    }

    private func availableProjectName(_ text: String, excluding id: UUID? = nil) throws -> String {
        if let projectLoadError { throw WorkError.unreadableStore(projectLoadError) }
        let name = try Self.validatedProjectName(text)
        let key = Self.projectNameKey(name)
        guard !projects.contains(where: { $0.id != id && Self.projectNameKey($0.name) == key }) else {
            throw WorkError.duplicateProjectName
        }
        return name
    }

    private func saveProjects(_ next: [WorkProject]) throws {
        do {
            try Self.write(next, to: projectFileURL)
            projects = next
        } catch {
            throw WorkError.saveProjectFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func create(title: String, dueDate: String, notes: String, projectID: UUID? = nil,
                       id: UUID = UUID(), now: Date = Date()) throws -> WorkItem {
        let title = try Self.validatedTitle(title, dueDate: dueDate, notes: notes)
        if let existing = items.first(where: { $0.id == id }) {
            guard existing.title == title, existing.dueDate == dueDate, existing.notes == notes else {
                throw WorkError.duplicateID
            }
            return existing
        }
        try validateProject(projectID)
        let item = WorkItem(id: id, title: title, dueDate: dueDate, notes: notes,
                            createdAt: now, projectID: projectID)
        try save(items + [item])
        return item
    }

    public func update(id: UUID, title: String, dueDate: String, notes: String) throws {
        let projectID = items[try indexOf(id)].projectID
        try update(id: id, title: title, dueDate: dueDate, notes: notes, projectID: projectID)
    }

    public func update(id: UUID, title: String, dueDate: String, notes: String,
                       projectID: UUID?) throws {
        let title = try Self.validatedTitle(title, dueDate: dueDate, notes: notes)
        var updated = items
        let index = try indexOf(id)
        if updated[index].projectID != projectID {
            try validateProject(projectID)
            updated[index].manualOrder = nil
        }
        updated[index].title = title
        updated[index].dueDate = dueDate
        updated[index].notes = notes
        updated[index].projectID = projectID
        try save(updated)
    }

    public func move(id: UUID, to projectID: UUID?) throws {
        var updated = items
        let index = try indexOf(id)
        guard updated[index].projectID != projectID else { return }
        try validateProject(projectID)
        updated[index].projectID = projectID
        updated[index].manualOrder = nil
        try save(updated)
    }

    public func reorderWork(id: UUID, relativeTo targetID: UUID, after: Bool, today: String) throws {
        if let loadError { throw WorkError.unreadableStore(loadError) }
        if let projectLoadError { throw WorkError.unreadableStore(projectLoadError) }
        let source = items[try indexOf(id)]
        let target = items[try indexOf(targetID)]
        guard source.id != target.id else { return }

        let projectIDs = Set(projects.map(\.id))
        func project(for item: WorkItem) -> UUID? {
            guard let id = item.projectID, projectIDs.contains(id) else { return nil }
            return id
        }
        let sourceProject = project(for: source)
        let section = WorkSection.containing(source, today: today)
        guard project(for: target) == sourceProject,
              WorkSection.containing(target, today: today) == section else { return }

        let siblings = items.filter {
            project(for: $0) == sourceProject && WorkSection.containing($0, today: today) == section
        }
        var order = section.ordered(siblings).map(\.id)
        guard let sourceIndex = order.firstIndex(of: id),
              let targetIndex = order.firstIndex(of: targetID) else { return }
        let targetAfterRemoval = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        let insertionIndex = after ? targetAfterRemoval + 1 : targetAfterRemoval
        guard sourceIndex != insertionIndex else { return }

        order.remove(at: sourceIndex)
        order.insert(id, at: insertionIndex)
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { index, id in (id, index) })
        let updated = items.map { item in
            guard let position = positions[item.id] else { return item }
            var updatedItem = item
            updatedItem.manualOrder = WorkManualOrder(section: section, position: position)
            return updatedItem
        }
        try save(updated)
    }

    public func setCompleted(id: UUID, completed: Bool, now: Date = Date()) throws {
        var updated = items
        let index = try indexOf(id)
        let previous = updated[index].completedAt
        let next = completed ? (previous ?? now) : nil
        guard previous != next else { return }
        updated[index].completedAt = next
        try save(updated)
    }

    public func setPinned(id: UUID, pinned: Bool) throws {
        var updated = items
        let index = try indexOf(id)
        guard updated[index].isPinned != pinned else { return }
        updated[index].pinned = pinned ? true : nil
        try save(updated)
    }

    private func indexOf(_ id: UUID) throws -> Int {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw WorkError.notFound }
        return index
    }

    private func validateProject(_ id: UUID?) throws {
        guard let id else { return }
        if let projectLoadError { throw WorkError.unreadableStore(projectLoadError) }
        guard projects.contains(where: { $0.id == id }) else { throw WorkError.projectNotFound }
    }

    private static func validatedProjectName(_ text: String) throws -> String {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkError.missingProjectName }
        guard name.count <= 60 else { throw WorkError.projectNameTooLong }
        return name
    }

    private static func projectNameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func validatedTitle(_ text: String, dueDate: String, notes: String) throws -> String {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw WorkError.missingTitle }
        guard title.utf8.count <= 512 else { throw WorkError.titleTooLong }
        guard notes.utf8.count <= 8192 else { throw WorkError.notesTooLong }
        guard WorkDay.parse(dueDate) != nil else { throw WorkError.invalidDeadline }
        return title
    }

    private func save(_ next: [WorkItem]) throws {
        if let loadError { throw WorkError.unreadableStore(loadError) }
        do {
            try Self.write(next, to: fileURL)
            items = next
        } catch {
            throw WorkError.saveFailed(error.localizedDescription)
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private enum WorkError: LocalizedError {
    case missingTitle, titleTooLong, notesTooLong, invalidDeadline, notFound, duplicateID
    case missingProjectName, projectNameTooLong, duplicateProjectName, projectNotFound
    case unreadableStore(String)
    case saveFailed(String)
    case saveProjectFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTitle: return "请输入工作标题。"
        case .titleTooLong: return "工作标题太长，请缩短后再保存。"
        case .notesTooLong: return "概要太长，请缩短后再保存。"
        case .invalidDeadline: return "请选择有效的截止日期。"
        case .notFound: return "找不到这条工作。"
        case .duplicateID: return "工作编号已被另一条记录使用。"
        case .missingProjectName: return "请输入项目名称。"
        case .projectNameTooLong: return "项目名称最多 60 个字符。"
        case .duplicateProjectName: return "已有同名项目。"
        case .projectNotFound: return "找不到这个项目。"
        case .unreadableStore(let message): return message
        case .saveFailed(let message): return "保存工作失败。\(message)"
        case .saveProjectFailed(let message): return "保存项目失败。\(message)"
        }
    }
}
