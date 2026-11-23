import CosmNotesWork
import Foundation

enum CheckFailure: Error {
    case assertion(String)
}

func check(_ condition: Bool, _ label: String) throws {
    guard condition else { throw CheckFailure.assertion(label) }
}

func expectRejection(_ label: String, _ action: () throws -> Void) throws {
    do {
        try action()
    } catch {
        return
    }
    throw CheckFailure.assertion(label)
}

func withStore(_ body: (URL, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory, directory.appendingPathComponent("work-items.json"))
}

func checkCalendar() throws {
    try check(WorkDay.parse("2028-02-29") != nil, "accepts a valid leap day")
    for day in ["2027-02-29", "2026-11-31", "2026-1-01", "2026-11-19T00:00Z"] {
        try check(WorkDay.parse(day) == nil, "rejects \(day)")
    }
    guard let leapDay = WorkDay.parse("2028-02-29"),
          let february = WorkCalendarMonth(containing: leapDay),
          let lastDay = WorkDay.parse("2026-12-31"),
          let december = WorkCalendarMonth(containing: lastDay),
          let nextMonth = WorkCalendarMonth.calendar.date(byAdding: .month, value: 1, to: december.start) else {
        throw CheckFailure.assertion("builds calendar months from stored deadlines")
    }
    try check(february.leadingBlankCount == 1, "places Tuesday one cell after Monday")
    let dates = february.days.map(WorkDay.local)
    try check(dates.count == 29 && dates.first == "2028-02-01" && dates.last == "2028-02-29",
              "includes every date of leap February")
    try check(WorkDay.local(nextMonth) == "2027-01-01", "navigates from December into the next year")
    try checkCalendarMarkers()

    try withStore { _, path in
        let store = WorkStore(fileURL: path)
        let later = try store.create(title: "总结", dueDate: "2026-11-28", notes: "")
        let today = try store.create(title: "移交", dueDate: "2026-11-19", notes: "")
        let earlier = try store.create(title: "附件", dueDate: "2026-11-20", notes: "")
        let overdue = try store.create(title: "记录", dueDate: "2026-11-18", notes: "")
        let grouped = WorkSection.grouped(store.items, today: "2026-11-19")
        try check(grouped[.overdue] == [overdue], "lists overdue work")
        try check(grouped[.today] == [today], "today's due date is not overdue")
        try check(grouped[.upcoming] == [earlier, later], "sorts upcoming work by deadline")
        try check(WorkSection.grouped(store.items, today: "2026-11-20")[.overdue] == [overdue, today],
                  "moves a task to overdue on the following day")
    }
}

func checkCalendarMarkers() throws {
    guard let date = WorkDay.parse("2026-11-20"),
          let followingDate = WorkDay.parse("2026-12-01"),
          let november = WorkCalendarMonth(containing: date),
          let december = WorkCalendarMonth(containing: followingDate) else {
        throw CheckFailure.assertion("builds months for deadline markers")
    }

    let firstProject = UUID()
    let secondProject = UUID()
    let deadlines: [String: [UUID?]] = [
        "2026-11-02": [firstProject, firstProject],
        "2026-11-03": [firstProject, secondProject],
        "2026-11-05": [nil],
        "2026-11-08": [firstProject],
        "2026-11-09": [firstProject],
        "2026-11-30": [secondProject],
        "2026-12-01": [secondProject],
    ]
    let weeks = november.weeks(deadlineProjects: deadlines)
    try check(weeks.count == 6 && weeks.allSatisfy { $0.days.count == 7 }, "keeps seven calendar columns")

    let week = weeks[1]
    let firstProjectMarkers = week.markers.filter { $0.projectID == firstProject }
    let otherProjectMarker = week.markers.first { $0.projectID == secondProject }
    let unassignedMarker = week.markers.first { $0.projectID == nil }
    try check(firstProjectMarkers.map(\.columns) == [0...1, 6...6],
              "joins consecutive project dates and leaves gaps between runs")
    try check(week.laneCount == 2 && otherProjectMarker?.columns == 1...1
              && otherProjectMarker?.lane != firstProjectMarkers.first?.lane,
              "gives overlapping project markers separate lanes")
    try check(unassignedMarker?.columns == 3...3, "marks a single unassigned date")
    try check(firstProjectMarkers.last?.continuesAfter == true && weeks[2].markers.first?.continuesBefore == true,
              "continues the same project from Sunday into Monday")
    try check(weeks.last?.markers.first?.continuesAfter == true
              && december.weeks(deadlineProjects: deadlines).first?.markers.first?.continuesBefore == true,
              "continues the same project across a month boundary")
}

func checkPersistence() throws {
    try withStore { _, path in
        let store = WorkStore(fileURL: path)
        let id = UUID()
        let work = try store.create(title: "  准备资料  ", dueDate: "2026-11-19", notes: "初稿", id: id)
        let retry = try store.create(title: "准备资料", dueDate: "2026-11-19", notes: "初稿", id: id)
        try check(retry == work, "same ID and contents are idempotent")
        try expectRejection("rejects reused ID with different contents") {
            try store.create(title: "另一项", dueDate: "2026-11-19", notes: "", id: id)
        }
        try expectRejection("rejects impossible due date") {
            try store.create(title: "错误日期", dueDate: "2026-02-30", notes: "")
        }
        try store.update(id: id, title: work.title, dueDate: "2026-11-20", notes: "终稿")
        try store.setCompleted(id: id, completed: true)

        let reopened = WorkStore(fileURL: path)
        try check(reopened.items.count == 1, "persists exactly one work item")
        let saved = reopened.items[0]
        try check(saved.id == id && saved.dueDate == "2026-11-20" && saved.notes == "终稿",
                  "persists edited fields")
        try check(WorkSection.grouped(reopened.items, today: "2026-11-19")[.completed] == [saved],
                  "persists completion")
        try reopened.setCompleted(id: id, completed: false)
        try check(WorkStore(fileURL: path).items.first?.completedAt == nil, "persists reopening")
    }
}

func checkPriority() throws {
    try withStore { _, path in
        let today = "2026-11-19"
        let legacy = """
        [{
            "id": "24E1812E-5418-4174-88B0-823DC4D7628C",
            "title": "旧版工作",
            "dueDate": "2026-11-27",
            "notes": "",
            "createdAt": 0
        }]
        """
        try Data(legacy.utf8).write(to: path)
        let original = WorkStore(fileURL: path)
        guard let late = original.items.first else { throw CheckFailure.assertion("reads v0.2.0 work") }
        try check(!late.isPinned, "treats an absent pin as unpinned")
        let urgent = try original.create(title: "当天截止", dueDate: today, notes: "")
        let early = try original.create(title: "后天截止", dueDate: "2026-11-21", notes: "")
        try original.setPinned(id: late.id, pinned: true)
        try original.setPinned(id: early.id, pinned: true)

        let store = WorkStore(fileURL: path)
        let groups = WorkSection.grouped(store.items, today: today)
        try check(WorkSection.allCases.first == .pinned, "shows pins ahead of unpinned dates")
        try check(groups[.pinned]?.map(\.id) == [early.id, late.id], "persists pins in due date order")
        try check(groups[.today] == [urgent] && groups[.upcoming] == nil,
                  "does not repeat pinned work in the date groups")

        try store.update(id: late.id, title: late.title, dueDate: "2026-11-20", notes: late.notes)
        try check(WorkSection.grouped(store.items, today: today)[.pinned]?.map(\.id) == [late.id, early.id],
                  "resorts pins after a deadline changes")
        try store.setCompleted(id: late.id, completed: true)
        let completed = WorkSection.grouped(store.items, today: today)
        try check(completed[.pinned]?.map(\.id) == [early.id] && completed[.completed]?.map(\.id) == [late.id],
                  "moves completed pins into Completed")
        try store.setCompleted(id: late.id, completed: false)
        try check(WorkSection.grouped(store.items, today: today)[.pinned]?.first?.id == late.id,
                  "returns a reopened pin to Pinned")

        try store.setPinned(id: late.id, pinned: false)
        let afterUnpin = WorkSection.grouped(WorkStore(fileURL: path).items, today: today)
        try check(afterUnpin[.upcoming]?.first?.id == late.id &&
                  afterUnpin[.upcoming]?.first?.isPinned == false, "persists unpin and returns to the date group")
    }
}

func checkWorkOrdering() throws {
    try withStore { directory, path in
        let today = "2026-11-22"
        let store = WorkStore(fileURL: path)
        let project = try store.createProject(name: "展会")
        let otherProject = try store.createProject(name: "交付")
        let first = try store.create(title: "物料", dueDate: "2026-11-24", notes: "", projectID: project.id)
        let middle = try store.create(title: "设计", dueDate: "2026-11-26", notes: "", projectID: project.id)
        let last = try store.create(title: "确认", dueDate: "2026-11-28", notes: "保留概要", projectID: project.id)
        let differentProject = try store.create(title: "取件", dueDate: last.dueDate, notes: "", projectID: otherProject.id)
        let pinned = try store.create(title: "置顶", dueDate: last.dueDate, notes: "", projectID: project.id)
        try store.setPinned(id: pinned.id, pinned: true)
        let projectPath = directory.appendingPathComponent("work-projects.json")
        let projectBytes = try Data(contentsOf: projectPath)

        func upcoming(in store: WorkStore, on date: String = today) -> [UUID] {
            let work = store.items.filter { $0.projectID == project.id }
            return WorkSection.grouped(work, today: date)[.upcoming, default: []].map(\.id)
        }

        try store.reorderWork(id: last.id, relativeTo: first.id, after: false, today: today)
        let reopened = WorkStore(fileURL: path)
        try check(upcoming(in: reopened) == [last.id, first.id, middle.id], "reloads manually ordered work")
        try check(reopened.items.first { $0.id == last.id }?.notes == "保留概要", "preserves the work overview")

        let reorderedBytes = try Data(contentsOf: path)
        try reopened.reorderWork(id: last.id, relativeTo: pinned.id, after: true, today: today)
        try reopened.reorderWork(id: last.id, relativeTo: differentProject.id, after: true, today: today)
        try check(Data(contentsOf: path) == reorderedBytes, "rejects drops across projects and priority groups")
        try check(Data(contentsOf: projectPath) == projectBytes, "reordering only writes work data")

        let newWork = try reopened.create(title: "就近截止", dueDate: "2026-11-23", notes: "", projectID: project.id)
        try check(upcoming(in: reopened) == [newWork.id, last.id, first.id, middle.id],
                  "keeps the default priority of new work")
        try check(upcoming(in: reopened, on: first.dueDate) == [last.id, middle.id],
                  "updates deadline groups as the date changes")
        try reopened.reorderWork(id: last.id, relativeTo: middle.id, after: true, today: today)
        try check(upcoming(in: reopened) == [newWork.id, first.id, middle.id, last.id], "can also move work down")
    }
}

func checkStoreReadFailure() throws {
    try withStore { _, path in
        let badData = Data("{".utf8)
        try badData.write(to: path)
        let store = WorkStore(fileURL: path)
        try check(store.loadError != nil, "reports invalid store")
        try expectRejection("refuses to overwrite an unreadable store") {
            try store.create(title: "样例", dueDate: "2026-11-19", notes: "")
        }
        try check(Data(contentsOf: path) == badData, "preserves existing bytes")
        try check(store.items.isEmpty, "does not show an unsaved row")
    }
}

func checkProjects() throws {
    try withStore { directory, path in
        let store = WorkStore(fileURL: path)
        let legacyWork = try store.create(title: "已有工作", dueDate: "2026-11-21", notes: "原备注")
        let workBytes = try Data(contentsOf: path)
        let first = try store.createProject(name: "  示例计划  ")
        let second = try store.createProject(name: "物料")
        try check(first.name == "示例计划" && Data(contentsOf: path) == workBytes,
                  "can create a project independently of work")
        try expectRejection("rejects a duplicate name") {
            try store.createProject(name: "示例计划")
        }
        try expectRejection("rejects a missing project") {
            try store.move(id: legacyWork.id, to: UUID())
        }
        try check(store.items == [legacyWork], "does not add an invalid project reference")

        try store.move(id: legacyWork.id, to: first.id)
        let reopened = WorkStore(fileURL: path)
        try check(reopened.projects == [first, second], "loads independent projects after restart")
        try check(reopened.items.first?.projectID == first.id && reopened.items.first?.notes == "原备注",
                  "persists the move without altering task details")
        try reopened.update(id: legacyWork.id, title: "更新标题", dueDate: legacyWork.dueDate, notes: legacyWork.notes)
        try check(reopened.items.first?.projectID == first.id, "editing work preserves its existing project")
        try reopened.move(id: legacyWork.id, to: second.id)
        try check(WorkStore(fileURL: path).items.first?.projectID == second.id, "can move between projects")
        try reopened.move(id: legacyWork.id, to: nil)
        try check(WorkStore(fileURL: path).items.first?.projectID == nil, "can return work to Unassigned")

        let projectPath = directory.appendingPathComponent("work-projects.json")
        let legacyProjects = [first, second].map { ["id": $0.id.uuidString, "name": $0.name] }
        try JSONEncoder().encode(legacyProjects).write(to: projectPath)
        let legacyStore = WorkStore(fileURL: path)
        try check(legacyStore.projects.first?.color == .blue, "loads old projects with the default color")
        try legacyStore.move(id: legacyWork.id, to: first.id)
        let assignedWork = try Data(contentsOf: path)
        try legacyStore.updateProject(id: first.id, name: "新项目名称", color: .purple)

        let edited = WorkStore(fileURL: path)
        try check(edited.projects.first?.id == first.id && edited.projects.first?.name == "新项目名称" &&
                  edited.projects.first?.color == .purple, "persists the new name and color under the same ID")
        try check(edited.items.first?.projectID == first.id && Data(contentsOf: path) == assignedWork,
                  "keeps the existing work when the project changes")
        try expectRejection("rejects renaming to an existing project") {
            try edited.updateProject(id: first.id, name: second.name, color: .orange)
        }
        try check(edited.projects.first?.color == .purple, "keeps the saved color after a rejected edit")

        let third = try edited.createProject(name: "汇报", color: .red)
        try edited.moveProject(id: first.id, relativeTo: third.id, after: true)
        try check(edited.projects.map(\.id) == [second.id, third.id, first.id],
                  "moves a project below the last project")
        try edited.moveProject(id: first.id, relativeTo: third.id, after: false)
        let reordered = WorkStore(fileURL: path)
        try check(reordered.projects.map(\.id) == [second.id, first.id, third.id] &&
                  reordered.projects[1].color == .purple &&
                  reordered.projects[1].name == "新项目名称",
                  "reloads project order, names and colors together")
        try check(Data(contentsOf: path) == assignedWork &&
                  reordered.items.first?.projectID == first.id, "reordering preserves work assignments")
        let reorderedBytes = try Data(contentsOf: projectPath)
        try edited.moveProject(id: first.id, relativeTo: first.id, after: true)
        try edited.moveProject(id: first.id, relativeTo: third.id, after: false)
        try expectRejection("rejects a deleted destination") {
            try edited.moveProject(id: first.id, relativeTo: UUID(), after: false)
        }
        try check(Data(contentsOf: projectPath) == reorderedBytes, "no-op and invalid moves keep the saved order")

        let corrupt = Data("{".utf8)
        try corrupt.write(to: projectPath)
        let partial = WorkStore(fileURL: path)
        try check(partial.projectLoadError != nil && partial.items.count == 1, "still reads work if projects fail to load")
        try expectRejection("does not overwrite unreadable projects") {
            try partial.createProject(name: "额外项目")
        }
        try expectRejection("blocks project moves while the project file is unreadable") {
            try partial.moveProject(id: first.id, relativeTo: second.id, after: true)
        }
        try check(Data(contentsOf: projectPath) == corrupt, "preserves the original project data")
    }
}

func checkLocalInbox() throws {
    try withStore { directory, path in
        let store = WorkStore(fileURL: path)
        let id = UUID()
        try expectRejection("rejects a wake-up with no local request") {
            _ = try WorkInbox.applyCreate(id: id, directory: directory, store: store)
        }
        try check(!FileManager.default.fileExists(atPath: path.path), "wake-up does not create data")
        let inbox = directory.appendingPathComponent("work-requests", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let request = inbox.appendingPathComponent(id.uuidString.lowercased() + ".json")
        try JSONEncoder().encode(["title": "本地新增", "dueDate": "2026-11-20", "notes": "样例"])
            .write(to: request)
        let created = try WorkInbox.applyCreate(id: id, directory: directory, store: store)
        try check(created.id == id && WorkStore(fileURL: path).items == [created],
                  "persists the staged work under its request ID")
        try check(!FileManager.default.fileExists(atPath: request.path), "consumes the request")
    }
}

do {
    try checkCalendar()
    try checkPersistence()
    try checkPriority()
    try checkWorkOrdering()
    try checkProjects()
    try checkStoreReadFailure()
    try checkLocalInbox()
    print("Passed 7 work checks: calendar, persistence, priority, work order, projects, unreadable store, local inbox.")
} catch {
    FileHandle.standardError.write(Data("Work check failed: \(error)\n".utf8))
    exit(1)
}
