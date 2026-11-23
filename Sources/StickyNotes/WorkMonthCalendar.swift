import CosmNotesWork
import SwiftUI

struct WorkMonthCalendar: View {
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private static let markerDiameter: CGFloat = 5
    private static let markerLaneHeight: CGFloat = 7

    @Binding var month: Date
    let today: Date
    let selectedDay: String?
    var deadlineProjects: [String: [UUID?]] = [:]
    var projectColors: [UUID: Color] = [:]
    var isCollapsed: Binding<Bool>?
    var isBelowProjects: Binding<Bool>?
    var reorderGesture: AnyGesture<DragGesture.Value>?
    var reorderReady = false
    let onSelect: (Date) -> Void

    var body: some View {
        if let grid = WorkCalendarMonth(containing: month) {
            let calendar = WorkCalendarMonth.calendar
            VStack(spacing: 7) {
                heading(for: grid.start, calendar: calendar)
                if isCollapsed?.wrappedValue != true {
                    monthGrid(grid, calendar: calendar)
                        .transition(ExpansionMotion.transition)
                }
            }
            .padding(10)
            .glassCard(in: RoundedRectangle(cornerRadius: 14),
                       tint: reorderReady ? Color.primary.opacity(0.08) : .clear)
        }
    }

    static func dateLabel(_ date: Date) -> String {
        let calendar = WorkCalendarMonth.calendar
        return "\(monthLabel(date, calendar: calendar))\(calendar.component(.day, from: date))日"
    }

    private static func monthLabel(_ date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.year, from: date))年\(calendar.component(.month, from: date))月"
    }

    private func monthGrid(_ grid: WorkCalendarMonth, calendar: Calendar) -> some View {
        let weeks = grid.weeks(deadlineProjects: deadlineProjects)
        let todayKey = WorkDay.local(today)

        return VStack(spacing: 3) {
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            ForEach(weeks.indices, id: \.self) { index in
                weekRow(weeks[index], todayKey: todayKey, calendar: calendar)
            }
        }
    }

    private func weekRow(_ week: WorkCalendarWeek, todayKey: String, calendar: Calendar) -> some View {
        let markerHeight = CGFloat(max(1, week.laneCount)) * Self.markerLaneHeight

        return HStack(spacing: 0) {
            ForEach(week.days.indices, id: \.self) { column in
                if let day = week.days[column] {
                    let key = WorkDay.local(day)
                    dayButton(day, number: calendar.component(.day, from: day), key: key,
                              isToday: key == todayKey, markerHeight: markerHeight)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 23 + markerHeight)
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !week.markers.isEmpty {
                weekMarkers(week)
                    .frame(height: markerHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func weekMarkers(_ week: WorkCalendarWeek) -> some View {
        Canvas { context, size in
            let columnWidth = size.width / CGFloat(week.days.count)
            let radius = Self.markerDiameter / 2
            for marker in week.markers {
                let firstColumn = CGFloat(marker.columns.lowerBound)
                let lastColumn = CGFloat(marker.columns.upperBound)
                let left = marker.continuesBefore
                    ? firstColumn * columnWidth : (firstColumn + 0.5) * columnWidth - radius
                let right = marker.continuesAfter
                    ? (lastColumn + 1) * columnWidth : (lastColumn + 0.5) * columnWidth + radius
                let top = CGFloat(marker.lane) * Self.markerLaneHeight
                let bounds = CGRect(x: left, y: top, width: right - left, height: Self.markerDiameter)
                let color = marker.projectID.flatMap { projectColors[$0] } ?? .secondary
                context.fill(Capsule().path(in: bounds), with: .color(color))
            }
        }
    }

    private func heading(for start: Date, calendar: Calendar) -> some View {
        HStack(spacing: 5) {
            monthTitle(Self.monthLabel(start, calendar: calendar))
            Spacer(minLength: 4)
            HStack(spacing: 1) {
                if !calendar.isDate(start, equalTo: today, toGranularity: .month) {
                    Button("本月") { month = today }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .padding(.leading, 6)
                }
                monthButton("上个月", symbol: "chevron.left", date: calendar.date(byAdding: .month, value: -1, to: start))
                monthButton("下个月", symbol: "chevron.right", date: calendar.date(byAdding: .month, value: 1, to: start))
                if let isCollapsed {
                    let collapsed = isCollapsed.wrappedValue
                    calendarButton(collapsed ? "展开日历" : "收拢日历",
                                   symbol: collapsed ? "chevron.down" : "chevron.up") {
                        withAnimation(collapsed ? ExpansionMotion.animation : nil) {
                            isCollapsed.wrappedValue.toggle()
                        }
                    }
                }
            }
            .padding(2)
            .glassControls(in: Capsule())
        }
    }

    @ViewBuilder
    private func monthTitle(_ label: String) -> some View {
        let title = Text(verbatim: label)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityAddTraits(.isHeader)

        if let isBelowProjects, let reorderGesture {
            let destination = isBelowProjects.wrappedValue ? "移到项目上方" : "移到项目下方"
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                title
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .gesture(reorderGesture)
            .help("拖动月历\(destination)")
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text(destination)) {
                isBelowProjects.wrappedValue.toggle()
            }
        } else {
            title
        }
    }

    private func monthButton(_ title: String, symbol: String, date: Date?) -> some View {
        calendarButton(title, symbol: symbol) {
            if let date { month = date }
        }
        .disabled(date == nil)
    }

    private func calendarButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 25, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
        .help(title)
    }

    private func dayButton(_ day: Date, number: Int, key: String, isToday: Bool, markerHeight: CGFloat) -> some View {
        let count = deadlineProjects[key, default: []].count
        let isSelected = key == selectedDay
        let date = Self.dateLabel(day)
        let dayLabel = isToday ? "\(date)，今天" : date
        let label = count == 0 ? dayLabel : "\(dayLabel)，\(count) 项工作到期"
        let shape = RoundedRectangle(cornerRadius: 5)

        return Button {
            onSelect(day)
        } label: {
            Text(number, format: .number)
                .font(.system(size: 14, weight: isSelected || isToday ? .semibold : .regular).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 23)
                .padding(.bottom, markerHeight)
                .background(isSelected ? Color.accentColor.opacity(0.20) : .clear, in: shape)
                .overlay {
                    if isToday {
                        shape.strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(label)
    }
}
