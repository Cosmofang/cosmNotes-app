import Foundation

public struct WorkCalendarMonth {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    public let start: Date
    public let leadingBlankCount: Int
    public let days: [Date]

    public init?(containing date: Date) {
        let calendar = Self.calendar
        guard let start = calendar.dateInterval(of: .month, for: date)?.start,
              let dayRange = calendar.range(of: .day, in: .month, for: date) else { return nil }

        self.start = start
        leadingBlankCount = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        days = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - dayRange.lowerBound, to: start)
        }
    }

    public func weeks(deadlineProjects: [String: [UUID?]] = [:]) -> [WorkCalendarWeek] {
        var slots = Array<Date?>(repeating: nil, count: leadingBlankCount) + days.map(Optional.some)
        let trailingBlankCount = (7 - slots.count % 7) % 7
        slots.append(contentsOf: repeatElement(nil, count: trailingBlankCount))

        return stride(from: 0, to: slots.count, by: 7).map { start in
            WorkCalendarWeek(days: Array(slots[start..<(start + 7)]), deadlineProjects: deadlineProjects)
        }
    }
}

public struct WorkCalendarWeek {
    public struct Marker: Equatable {
        public let projectID: UUID?
        public let columns: ClosedRange<Int>
        public let lane: Int
        public let continuesBefore: Bool
        public let continuesAfter: Bool
    }

    public let days: [Date?]
    public let markers: [Marker]
    public let laneCount: Int

    fileprivate init(days: [Date?], deadlineProjects: [String: [UUID?]]) {
        self.days = days
        let calendar = WorkCalendarMonth.calendar

        func projects(on day: Date?) -> Set<UUID?> {
            guard let day else { return [] }
            return Set(deadlineProjects[WorkDay.local(day), default: []])
        }

        let firstColumn = days.firstIndex { $0 != nil }
        let lastColumn = days.lastIndex { $0 != nil }
        let previousDate = firstColumn.flatMap { days[$0] }.flatMap {
            calendar.date(byAdding: .day, value: -1, to: $0)
        }
        let nextDate = lastColumn.flatMap { days[$0] }.flatMap {
            calendar.date(byAdding: .day, value: 1, to: $0)
        }
        let previousProjects = projects(on: previousDate)
        let nextProjects = projects(on: nextDate)
        let projectsByColumn = days.map(projects(on:))
        var precedingColumn: Set<UUID?> = []
        var laneEnds: [Int] = []
        var markers: [Marker] = []

        for (column, projects) in projectsByColumn.enumerated() {
            let starting = projects.subtracting(precedingColumn).sorted {
                ($0?.uuidString ?? "") < ($1?.uuidString ?? "")
            }
            for projectID in starting {
                var end = column
                while end + 1 < days.count && projectsByColumn[end + 1].contains(projectID) {
                    end += 1
                }

                let lane = laneEnds.firstIndex { $0 < column } ?? laneEnds.count
                if lane == laneEnds.count {
                    laneEnds.append(end)
                } else {
                    laneEnds[lane] = end
                }
                markers.append(Marker(
                    projectID: projectID,
                    columns: column...end,
                    lane: lane,
                    continuesBefore: column == firstColumn && previousProjects.contains(projectID),
                    continuesAfter: end == lastColumn && nextProjects.contains(projectID)
                ))
            }
            precedingColumn = projects
        }

        self.markers = markers
        laneCount = laneEnds.count
    }
}
