import AppKit
import CosmNotesWork
import Observation
import SwiftUI

final class WorkTimelineController: NSWindowController, NSWindowDelegate {
    private static let defaultExpandedSize = NSSize(width: 376, height: 472)
    private static let minimumExpandedSize = NSSize(width: 344, height: 350)
    private static let collapsedSize = NSSize(width: 240, height: 42)
    private static let expandedSizePreference = "WorkTimeline.expandedSize"
    private static let windowPinPreference = "WorkTimeline.isWindowPinned"
    private static let titlePreference = "WorkTimeline.title"
    private let presentation = WorkTimelinePresentation()
    private var expandedSize: NSSize

    init(store: WorkStore) {
        let bounds = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let expandedSize = Self.restoredExpandedSize()
        self.expandedSize = expandedSize
        let frame = Self.fittedFrame(
            size: expandedSize,
            topRight: NSPoint(x: bounds.maxX - 20, y: bounds.maxY - 24),
            bounds: bounds
        )
        let panel = WorkTimelinePanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = AppIdentity.preferences.string(forKey: Self.titlePreference) ?? WorkTimelinePresentation.defaultTitle
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        panel.dragTracking = presentation.dragTracking
        presentation.title = panel.title
        presentation.isWindowPinned = AppIdentity.preferences.bool(forKey: Self.windowPinPreference)
        applyWindowPin(to: panel)

        let hosting = NSHostingController(rootView: WorkTimelineView(
            store: store,
            presentation: presentation,
            onRenameTitle: { [weak self] in self?.renameTitle($0) },
            onToggleWindowPin: { [weak self] in self?.toggleWindowPin() },
            onCollapse: { [weak self] in self?.toggleCollapse() },
            onClose: { [weak self] in self?.close() }
        ))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        panel.contentViewController = hosting
        panel.minSize = Self.minimumSize(in: bounds)
        Self.hideSystemButtons(in: panel)
        panel.setFrame(frame, display: false)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { return nil }

    func show(activate: Bool = true) {
        guard let panel = window, activate || presentation.isWindowPinned else { return }
        setCollapsed(false)
        if activate {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func showNewWork() {
        show()
        if presentation.sheet == nil {
            presentation.sheet = TimelineSheet(content: .work(nil))
        }
    }

    private func renameTitle(_ title: String) {
        guard title != presentation.title else { return }
        AppIdentity.preferences.set(title, forKey: Self.titlePreference)
        presentation.title = title
        window?.title = title
    }

    private func toggleWindowPin() {
        guard let panel = window as? NSPanel else { return }
        presentation.isWindowPinned.toggle()
        applyWindowPin(to: panel)
        AppIdentity.preferences.set(presentation.isWindowPinned, forKey: Self.windowPinPreference)
    }

    private func applyWindowPin(to panel: NSPanel) {
        let isPinned = presentation.isWindowPinned
        panel.isFloatingPanel = isPinned
        panel.level = isPinned ? .floating : .normal
        panel.collectionBehavior = isPinned ? [.moveToActiveSpace, .fullScreenAuxiliary] : [.moveToActiveSpace]
    }

    private func toggleCollapse() {
        setCollapsed(!presentation.isCollapsed)
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard let panel = window, collapsed != presentation.isCollapsed,
              let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        presentation.dragTracking.complete(at: nil)
        let frame = panel.frame
        withAnimation(collapsed ? nil : ExpansionMotion.animation) {
            presentation.isCollapsed = collapsed
        }
        if collapsed {
            expandedSize = frame.size
            panel.minSize = Self.collapsedSize
            panel.styleMask.remove(.resizable)
        } else {
            panel.styleMask.insert(.resizable)
            panel.minSize = Self.minimumSize(in: bounds)
        }
        Self.hideSystemButtons(in: panel)
        let target = Self.fittedFrame(
            size: collapsed ? Self.collapsedSize : expandedSize,
            topRight: NSPoint(x: frame.maxX, y: frame.maxY),
            bounds: bounds
        )
        panel.setFrame(target, display: true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard !presentation.isCollapsed, let window else { return }
        expandedSize = window.frame.size
        AppIdentity.preferences.set(NSStringFromSize(expandedSize), forKey: Self.expandedSizePreference)
    }

    private static func restoredExpandedSize() -> NSSize {
        guard let value = AppIdentity.preferences.string(forKey: expandedSizePreference) else {
            return defaultExpandedSize
        }
        let size = NSSizeFromString(value)
        guard size.width.isFinite && size.height.isFinite,
              size.width > 0 && size.height > 0 else {
            return defaultExpandedSize
        }
        return NSSize(width: max(size.width, minimumExpandedSize.width),
                      height: max(size.height, minimumExpandedSize.height))
    }

    private static func minimumSize(in bounds: NSRect) -> NSSize {
        NSSize(width: min(minimumExpandedSize.width, bounds.width),
               height: min(minimumExpandedSize.height, bounds.height))
    }

    private static func hideSystemButtons(in window: NSWindow) {
        // The timeline draws its own controls in the full-width header.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
    }

    private static func fittedFrame(size: NSSize, topRight: NSPoint, bounds: NSRect) -> NSRect {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        return NSRect(
            x: min(max(topRight.x - width, bounds.minX), bounds.maxX - width),
            y: min(max(topRight.y - height, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }
}

private final class WorkTimelinePanel: NSPanel {
    var dragTracking: TimelineDragTracking?

    override func sendEvent(_ event: NSEvent) {
        if let tracking = dragTracking, tracking.isTracking {
            switch event.type {
            case .leftMouseDragged:
                if let location = dragLocation(for: event) { tracking.update(location) }
            case .leftMouseUp:
                tracking.complete(at: dragLocation(for: event))
            case .leftMouseDown:
                tracking.complete(at: nil)
            case .keyDown where event.keyCode == 53:
                tracking.cancel()
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        dragTracking?.complete(at: nil)
        super.resignKey()
    }

    private func dragLocation(for event: NSEvent) -> CGPoint? {
        guard let view = contentView else { return nil }
        let location = view.convert(event.locationInWindow, from: nil)
        return CGPoint(x: location.x - view.bounds.minX,
                       y: view.isFlipped ? location.y - view.bounds.minY : view.bounds.maxY - location.y)
    }
}

private final class TimelineDragTracking {
    private(set) var isTracking = false
    private var location: CGPoint?
    private var onUpdate: ((CGPoint) -> Void)?
    private var onEnd: ((CGPoint?) -> Void)?

    func begin(update: @escaping (CGPoint) -> Void, end: @escaping (CGPoint?) -> Void) {
        isTracking = true
        onUpdate = update
        onEnd = end
    }

    func update(_ point: CGPoint) {
        location = point
        onUpdate?(point)
    }

    func refresh() {
        if let location { onUpdate?(location) }
    }

    // Escape clears the preview but keeps the current press consumed until mouse-up.
    func cancel() { stop(at: nil) }

    func complete(at location: CGPoint?) {
        isTracking = false
        stop(at: location)
    }

    private func stop(at location: CGPoint?) {
        let end = onEnd
        self.location = nil
        onUpdate = nil
        onEnd = nil
        end?(location)
    }
}

private final class WorkTimelinePresentation: ObservableObject {
    static let defaultTitle = "工作时间轴"
    let dragTracking = TimelineDragTracking()
    @Published var title = defaultTitle
    @Published var isCollapsed = false
    @Published var isWindowPinned = false
    @Published var sheet: TimelineSheet?
}

private struct TimelineSheet: Identifiable {
    enum Content {
        case work(WorkItem?, scope: WorkFilter? = nil, focusSummary: Bool = false)
        case project(WorkProject?)
    }

    let id = UUID()
    let content: Content
}

private enum WorkFilter: Hashable {
    case all
    case unassigned
    case project(UUID)

    var projectID: UUID? {
        if case .project(let id) = self { return id }
        return nil
    }
}

private struct TimelineDragPreview {
    let title: String
    let location: CGPoint
}

@Observable
private final class TimelineDragFeedback {
    var preview: TimelineDragPreview?
}

private struct TimelineDragOverlay: View {
    let feedback: TimelineDragFeedback

    var body: some View {
        if let preview = feedback.preview {
            Text(preview.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .position(x: preview.location.x, y: preview.location.y + 22)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private enum OrderGroup: Hashable {
    case projects
    case work(WorkFilter, WorkSection)

    var spacing: CGFloat { self == .projects ? 14 : 2 }
}

private struct OrderRow: Hashable {
    let group: OrderGroup
    let id: UUID
}

private struct OrderDropTarget: Equatable {
    let row: OrderRow
    let after: Bool
}

private struct OrderPreview {
    let source: OrderRow
    let sourceFrame: CGRect
    let target: OrderDropTarget?
    let targetFrame: CGRect?

    private var spaceTaken: CGFloat { sourceFrame.height + source.group.spacing }

    var placeholderFrame: CGRect {
        guard let target, let targetFrame else { return sourceFrame }
        let insertionY = target.after ? targetFrame.maxY + source.group.spacing : targetFrame.minY
        let adjustment = targetFrame.minY > sourceFrame.minY ? spaceTaken : 0
        return CGRect(origin: CGPoint(x: sourceFrame.minX, y: insertionY - adjustment), size: sourceFrame.size)
    }

    func offset(for row: OrderRow, frame: CGRect?) -> CGFloat {
        guard row.group == source.group, row != source, let frame, let target, let targetFrame else { return 0 }
        if sourceFrame.minY < targetFrame.minY {
            let beforeInsertion = frame.minY < targetFrame.minY || (row == target.row && target.after)
            return frame.minY > sourceFrame.minY && beforeInsertion ? -spaceTaken : 0
        }
        let afterInsertion = frame.minY > targetFrame.minY || (row == target.row && !target.after)
        return frame.minY < sourceFrame.minY && afterInsertion ? spaceTaken : 0
    }
}

private enum TimelineDragSource {
    case order(OrderRow)
    case assignment(UUID)
    case calendar
}

private final class TimelineDragFrames {
    var projectChips: [WorkFilter: CGRect] = [:]
    var projectBar: CGRect = .null
    var orderRows: [OrderRow: CGRect] = [:]
    var scrollViewport: CGRect = .null
    var scrollOrigin: CGPoint = .zero
}

private struct WorkTimelineView: View {
    private static let coordinateSpace = "work-timeline"
    private static let orderCoordinateSpace = "work-timeline-list"
    private static let projectHeaderHeight: CGFloat = 34
    private static let workActionSize: CGFloat = 22
    private static let workHeaderSpacing: CGFloat = 9
    private static let workRowVerticalPadding: CGFloat = 7
    private static let calendarReorderDistance: CGFloat = 36

    @ObservedObject var store: WorkStore
    @ObservedObject var presentation: WorkTimelinePresentation
    let onRenameTitle: (String) -> Void
    let onToggleWindowPin: () -> Void
    let onCollapse: () -> Void
    let onClose: () -> Void

    @State private var expandedBranches: Set<WorkFilter> = [.unassigned]
    @State private var expandedCompleted: Set<WorkFilter> = []
    @State private var expandedWorkSummaries: Set<UUID> = []
    @State private var updateError: String?
    @State private var selection: WorkFilter = .all
    @AppStorage("WorkCalendar.isCollapsed", store: AppIdentity.preferences) private var isCalendarCollapsed = false
    @AppStorage("WorkCalendar.isBelowProjects", store: AppIdentity.preferences) private var isCalendarBelowProjects = false
    @State private var browsedMonth: Date?
    @State private var selectedDeadline: String?
    @State private var dropTarget: WorkFilter?
    @State private var projectContentHeight = WorkProjectLayout.rowHeight
    @State private var dragFrames = TimelineDragFrames()
    @State private var dragFeedback = TimelineDragFeedback()
    @State private var orderTarget: OrderDropTarget?
    @State private var draggedRow: (row: OrderRow, frame: CGRect)?
    @State private var calendarReadyToMove = false
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if !presentation.isCollapsed {
                VStack(spacing: 0) {
                    projectBar
                    Divider()
                        .opacity(0.55)
                        .padding(.horizontal, 16)
                    TimelineView(.everyMinute) { context in
                        timeline(on: context.date)
                    }
                }
                .transition(ExpansionMotion.transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.coordinateSpace)
        .glassPanel(in: RoundedRectangle(cornerRadius: 16))
        .overlay { TimelineDragOverlay(feedback: dragFeedback) }
        .sheet(item: $presentation.sheet) { request in
            switch request.content {
            case .work(let item, let scope, let focusSummary):
                WorkEditor(
                    store: store,
                    item: item,
                    defaultProjectID: (scope ?? selection).projectID,
                    defaultDueDate: selectedDeadline.flatMap(WorkDay.parse) ?? Date(),
                    focusSummary: focusSummary
                )
            case .project(let project):
                WorkProjectEditor(store: store, project: project)
            }
        }
        .alert("无法保存更改", isPresented: Binding(
            get: { updateError != nil }, set: { if !$0 { updateError = nil } }
        )) {
            Button("好", role: .cancel) { updateError = nil }
        } message: {
            Text(updateError ?? "")
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            timelineTitle
                .font(.system(size: 16, weight: .semibold))

            Spacer(minLength: 4)

            if !presentation.isCollapsed {
                AppearancePicker()
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(ExpansionMotion.transition)
            }

            HStack(spacing: 3) {
                if !presentation.isCollapsed {
                    iconButton("新增工作", symbol: "plus", inToolbar: true) {
                        presentation.sheet = TimelineSheet(content: .work(nil))
                    }
                    .transition(ExpansionMotion.transition)
                }
                iconButton(presentation.isWindowPinned ? "取消置顶窗口" : "置顶窗口",
                           symbol: presentation.isWindowPinned ? "pin.fill" : "pin",
                           inToolbar: true, action: onToggleWindowPin)
                iconButton(presentation.isCollapsed ? "展开时间轴" : "收起时间轴",
                           symbol: presentation.isCollapsed ? "chevron.down" : "chevron.up",
                           inToolbar: true, action: onCollapse)
                iconButton("关闭时间轴", symbol: "xmark", inToolbar: true, action: onClose)
            }
            .padding(3)
            .glassControls(in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background {
            WindowDragArea()
        }
    }

    @ViewBuilder
    private var timelineTitle: some View {
        if isEditingTitle {
            Label {
                TextField(WorkTimelinePresentation.defaultTitle, text: $titleDraft)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("时间轴名称")
                    .focused($titleFocused)
                    .focusEffectDisabled()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    .onSubmit(saveTitle)
                    .onExitCommand(perform: cancelTitleEdit)
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { cancelTitleEdit() }
                    }
                    .task { @MainActor in titleFocused = true }
            } icon: {
                Image(systemName: "calendar")
            }
        } else {
            Label(presentation.title, systemImage: "calendar")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minHeight: 28)
                .help(presentation.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityAction(named: Text("修改标题"), beginTitleEdit)
                .allowsHitTesting(false)
                .background {
                    WindowDragArea(onDoubleClick: beginTitleEdit)
                }
        }
    }

    private func beginTitleEdit() {
        titleDraft = presentation.title
        isEditingTitle = true
    }

    private func saveTitle() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { onRenameTitle(title) }
        cancelTitleEdit()
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
        titleFocused = false
    }

    @ViewBuilder
    private func iconButton(_ label: String, symbol: String, inToolbar: Bool = false,
                            action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)

        if inToolbar {
            button
                .buttonStyle(.plain)
                .focusEffectDisabled()
        } else {
            button.buttonStyle(.borderless)
        }
    }

    private var projectBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("项目")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                iconButton("新增项目", symbol: "folder.badge.plus", action: showNewProject)
                    .disabled(store.projectLoadError != nil)
            }

            HStack(spacing: 6) {
                projectChip("全部工作", symbol: "square.grid.2x2", filter: .all)
                trackDropFrame(projectChip("未归类", symbol: "tray", filter: .unassigned), for: .unassigned)
            }

            if !store.projects.isEmpty {
                ScrollView(.vertical) {
                    WorkProjectLayout {
                        ForEach(store.projects) { project in
                            trackDropFrame(projectRow(project), for: .project(project.id))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        projectContentHeight = height
                    }
                }
                .frame(height: min(174, projectContentHeight))
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .named(Self.coordinateSpace))
                } action: { frame in
                    dragFrames.projectBar = frame
                }
            }

            if let error = store.projectLoadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func projectChip(_ name: String, symbol: String, filter: WorkFilter) -> some View {
        Button {
            selection = filter
        } label: {
            Label(name, systemImage: symbol)
                .lineLimit(1)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .glassCard(in: Capsule(), tint: Color.accentColor.opacity(
                    selection == filter ? 0.20 : 0
                ))
                .overlay {
                    if dropTarget == filter {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == filter ? .isSelected : [])
    }

    private func projectRow(_ project: WorkProject) -> some View {
        let filter = WorkFilter.project(project.id)
        let color = project.color.tint
        let highlighted = selection == filter || dropTarget == filter

        return HStack(spacing: 4) {
            Button {
                selection = filter
            } label: {
                Text(project.name)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: WorkProjectLayout.rowHeight, alignment: .leading)
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(project.name)
            .accessibilityAddTraits(selection == filter ? .isSelected : [])

            iconButton("编辑项目：\(project.name)", symbol: "pencil") {
                presentation.sheet = TimelineSheet(content: .project(project))
            }
            .padding(.trailing, 3)
            .layoutPriority(1)
        }
        .frame(height: WorkProjectLayout.rowHeight)
        .glassCard(in: Capsule(), tint: color.opacity(highlighted ? 0.29 : 0.16))
        .overlay {
            if dropTarget == filter {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
    }

    private func trackDropFrame<Content: View>(_ content: Content, for filter: WorkFilter) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named(Self.coordinateSpace))
            } action: { frame in
                dragFrames.projectChips[filter] = frame
            }
            .onDisappear {
                dragFrames.projectChips.removeValue(forKey: filter)
            }
    }

    private func projectFilter(at location: CGPoint) -> WorkFilter? {
        if dragFrames.projectChips[.unassigned]?.contains(location) == true { return .unassigned }
        guard dragFrames.projectBar.contains(location) else { return nil }
        return dragFrames.projectChips.first { $0.value.contains(location) }?.key
    }

    private func trackOrderFrame<Content: View>(_ content: Content, for row: OrderRow) -> some View {
        let preview = orderPreview
        let isSource = preview?.source == row
        let offset = preview?.offset(for: row, frame: dragFrames.orderRows[row]) ?? 0

        // Keep each row's measured frame fixed while its visible contents move.
        // Hitting the moving frames would continuously shift the drop target.
        return ZStack {
            content
                .opacity(isSource ? 0 : 1)
                .offset(y: offset)
                .animation(preview == nil ? nil : ExpansionMotion.animation, value: offset)
        }
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named(Self.orderCoordinateSpace))
        } action: { frame in
            dragFrames.orderRows[row] = frame
        }
        .onDisappear {
            dragFrames.orderRows.removeValue(forKey: row)
        }
    }

    private var orderPreview: OrderPreview? {
        guard let draggedRow else { return nil }
        return OrderPreview(source: draggedRow.row, sourceFrame: draggedRow.frame, target: orderTarget,
                            targetFrame: orderTarget.flatMap { dragFrames.orderRows[$0.row] })
    }

    @ViewBuilder
    private var orderPlaceholder: some View {
        if let preview = orderPreview {
            let frame = preview.placeholderFrame
            let shape = RoundedRectangle(cornerRadius: preview.source.group == .projects ? 11 : 10)
            shape
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.32),
                                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .animation(ExpansionMotion.animation, value: frame.origin)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func orderPlacement(for source: OrderRow, at location: CGPoint) -> OrderDropTarget? {
        guard dragFrames.scrollViewport.contains(location) else { return nil }
        let point = CGPoint(x: location.x - dragFrames.scrollOrigin.x, y: location.y - dragFrames.scrollOrigin.y)
        let isProject = source.group == .projects
        let gap = source.group.spacing / 2
        let splitY = isProject ? Self.projectHeaderHeight / 2 : Self.workRowVerticalPadding + Self.workActionSize
        guard let (row, frame) = dragFrames.orderRows.first(where: { row, frame in
            row.group == source.group && row != source && frame.insetBy(dx: 0, dy: -gap).contains(point)
        }) else { return nil }
        return OrderDropTarget(row: row, after: point.y >= frame.minY + splitY)
    }

    private func timelineDrag(_ source: TimelineDragSource, title: String,
                              today: String) -> some Gesture<DragGesture.Value> {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                let tracking = presentation.dragTracking
                guard !tracking.isTracking else { return }
                if case .order(let row) = source {
                    guard let frame = dragFrames.orderRows[row] else { return }
                    draggedRow = (row, frame)
                }
                let start = value.startLocation
                tracking.begin(update: { location in
                    updateDrag(source, title: title, start: start, location: location)
                }, end: { location in
                    defer { clearDragFeedback() }
                    if let location {
                        finishDrag(source, start: start, location: location, today: today)
                    }
                })
                tracking.update(value.location)
            }
    }

    private func updateDrag(_ source: TimelineDragSource, title: String, start: CGPoint, location: CGPoint) {
        dragFeedback.preview = TimelineDragPreview(title: title, location: location)
        switch source {
        case .order(let row):
            let target = orderPlacement(for: row, at: location)
            if target != orderTarget { orderTarget = target }
        case .assignment:
            let target = projectFilter(at: location)
            if target != dropTarget { dropTarget = target }
        case .calendar:
            let ready = canMoveCalendar(from: start, to: location)
            if ready != calendarReadyToMove { calendarReadyToMove = ready }
        }
    }

    private func finishDrag(_ source: TimelineDragSource, start: CGPoint, location: CGPoint, today: String) {
        do {
            switch source {
            case .order(let row):
                guard dragFrames.scrollViewport.contains(location), let target = orderTarget else { return }
                if row.group == .projects {
                    try store.moveProject(id: row.id, relativeTo: target.row.id, after: target.after)
                } else {
                    try store.reorderWork(id: row.id, relativeTo: target.row.id, after: target.after, today: today)
                }
            case .assignment(let itemID):
                guard let target = projectFilter(at: location) else { return }
                try store.move(id: itemID, to: target.projectID)
            case .calendar:
                if canMoveCalendar(from: start, to: location) { isCalendarBelowProjects.toggle() }
            }
        } catch {
            updateError = error.localizedDescription
        }
    }

    private func canMoveCalendar(from start: CGPoint, to location: CGPoint) -> Bool {
        let direction: CGFloat = isCalendarBelowProjects ? -1 : 1
        let vertical = location.y - start.y
        return dragFrames.scrollViewport.contains(location) &&
            vertical * direction >= Self.calendarReorderDistance &&
            abs(vertical) > abs(location.x - start.x)
    }

    private func clearDragFeedback() {
        draggedRow = nil
        dragFeedback.preview = nil
        orderTarget = nil
        dropTarget = nil
        calendarReadyToMove = false
    }

    private var visibleWork: [WorkItem] {
        switch selection {
        case .all:
            return store.items
        case .unassigned:
            let knownProjects = Set(store.projects.map(\.id))
            return store.items.filter { item in
                guard let id = item.projectID else { return true }
                return !knownProjects.contains(id)
            }
        case .project(let id):
            return store.items.filter { $0.projectID == id }
        }
    }

    private func timeline(on date: Date) -> some View {
        let scopedItems = visibleWork
        let today = WorkDay.local(date)
        let items = selectedDeadline.map { day in scopedItems.filter { $0.dueDate == day } } ?? scopedItems
        let projectColors = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0.color.tint) })
        let deadlineProjects = scopedItems.reduce(into: [String: [UUID?]]()) { deadlines, item in
            let projectID = item.projectID.flatMap { projectColors[$0] == nil ? nil : $0 }
            deadlines[item.dueDate, default: []].append(projectID)
        }
        let month = Binding(
            get: { browsedMonth ?? date },
            set: { newMonth in
                let isCurrentMonth = WorkCalendarMonth.calendar.isDate(newMonth, equalTo: date, toGranularity: .month)
                browsedMonth = isCurrentMonth ? nil : newMonth
                selectedDeadline = nil
            }
        )
        let calendar = WorkMonthCalendar(month: month, today: date, selectedDay: selectedDeadline,
                                         deadlineProjects: deadlineProjects, projectColors: projectColors,
                                         isCollapsed: $isCalendarCollapsed, isBelowProjects: $isCalendarBelowProjects,
                                         reorderGesture: AnyGesture(timelineDrag(.calendar, title: "月历", today: today)),
                                         reorderReady: calendarReadyToMove,
                                         onSelect: selectDeadline)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: OrderGroup.projects.spacing) {
                if !isCalendarBelowProjects {
                    calendar
                }

                if let selectedDeadline, let selectedDate = WorkDay.parse(selectedDeadline) {
                    HStack {
                        Text(verbatim: WorkMonthCalendar.dateLabel(selectedDate))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("全部日期") { self.selectedDeadline = nil }
                            .buttonStyle(.borderless)
                    }
                    .font(.system(size: 13))
                }

                if let error = store.loadError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("无法读取工作", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 15, weight: .semibold))
                        Text(error)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(.secondary)
                }

                if selection == .all && (!store.projects.isEmpty || !items.isEmpty) {
                    projectTree(items: items, today: today)
                } else {
                    if items.isEmpty && store.loadError == nil {
                        Text(emptyWorkMessage)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    workGroups(items, today: today, scope: selection)
                    timelineFooter
                }

                if isCalendarBelowProjects {
                    calendar
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .coordinateSpace(name: Self.orderCoordinateSpace)
            .overlay(alignment: .topLeading) { orderPlaceholder }
            .onGeometryChange(for: CGPoint.self) { geometry in
                geometry.frame(in: .named(Self.coordinateSpace)).origin
            } action: { origin in
                dragFrames.scrollOrigin = origin
                presentation.dragTracking.refresh()
            }
        }
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named(Self.coordinateSpace))
        } action: { frame in
            dragFrames.scrollViewport = frame
        }
    }

    private var emptyWorkMessage: String {
        selectedDeadline == nil ? "暂无工作" : "当天暂无工作"
    }

    private func selectDeadline(_ date: Date) {
        let day = WorkDay.local(date)
        if selectedDeadline == day {
            selectedDeadline = nil
            return
        }

        selectedDeadline = day
        let projectIDs = Set(store.projects.map(\.id))
        withAnimation(ExpansionMotion.animation) {
            for item in store.items where item.dueDate == day {
                expandedBranches.insert(projectScope(for: item, projectIDs: projectIDs))
            }
        }
    }

    @ViewBuilder
    private var timelineFooter: some View {
        switch selection {
        case .all:
            addProjectButton
        case .unassigned:
            addUnassignedWorkButton
        case .project(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                addWorkButton(for: project.id, projectName: project.name)
            }
        }
    }

    @ViewBuilder
    private func projectTree(items: [WorkItem], today: String) -> some View {
        let projectIDs = Set(store.projects.map(\.id))
        let grouped = Dictionary(grouping: items) { item in
            projectScope(for: item, projectIDs: projectIDs)
        }
        let hasExpandedProject = store.projects.contains { expandedBranches.contains(.project($0.id)) }

        ForEach(store.projects) { project in
            let scope = WorkFilter.project(project.id)
            trackOrderFrame(
                projectBranch(project.name, icon: "folder.fill", color: project.color.tint,
                              scope: scope, items: grouped[scope, default: []], today: today),
                for: OrderRow(group: .projects, id: project.id)
            )
        }
        if let unassigned = grouped[.unassigned] {
            projectBranch("未归类", icon: "tray", color: .secondary,
                          scope: .unassigned, items: unassigned, today: today)
        }
        if !hasExpandedProject {
            addProjectButton
        }
    }

    private func projectScope(for item: WorkItem, projectIDs: Set<UUID>) -> WorkFilter {
        if let id = item.projectID, projectIDs.contains(id) { return .project(id) }
        return .unassigned
    }

    private var addProjectButton: some View {
        centeredAddButton("添加项目", action: showNewProject)
            .disabled(store.projectLoadError != nil)
    }

    private func addWorkButton(for projectID: UUID, projectName: String) -> some View {
        centeredAddButton("添加工作") {
            presentation.sheet = TimelineSheet(content: .work(nil, scope: .project(projectID)))
        }
        .accessibilityLabel("为 \(projectName) 添加工作")
    }

    private var addUnassignedWorkButton: some View {
        centeredAddButton("新增工作") {
            presentation.sheet = TimelineSheet(content: .work(nil, scope: .unassigned))
        }
        .accessibilityLabel("新增未归类工作")
    }

    private func centeredAddButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func showNewProject() {
        presentation.sheet = TimelineSheet(content: .project(nil))
    }

    private func orderHandle(_ row: OrderRow, title: String, label: String, size: CGFloat,
                             today: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(timelineDrag(.order(row), title: title, today: today))
            .accessibilityLabel(label)
            .help("上下拖动调整顺序")
    }

    private func projectBranch(_ name: String, icon: String, color: Color, scope: WorkFilter,
                               items: [WorkItem], today: String) -> some View {
        let isExpanded = expandedBranches.contains(scope)
        let row = scope.projectID.map { OrderRow(group: .projects, id: $0) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    if isExpanded {
                        expandedBranches.remove(scope)
                    } else {
                        withAnimation(ExpansionMotion.animation) {
                            _ = expandedBranches.insert(scope)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 12)
                            .foregroundStyle(.secondary)
                        Image(systemName: icon)
                            .foregroundStyle(color)
                        Text(name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: Self.projectHeaderHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起项目：\(name)" : "展开项目：\(name)")

                if let row, store.projects.count > 1 {
                    orderHandle(row, title: name, label: "调整项目顺序：\(name)",
                                size: Self.projectHeaderHeight, today: today)
                }
            }
            .glassCard(in: RoundedRectangle(cornerRadius: 11), tint: color.opacity(0.13))

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        if items.isEmpty {
                            Text(emptyWorkMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        } else {
                            workGroups(items, today: today, scope: scope)
                        }
                    }
                    .padding(.leading, 20)
                    .background(alignment: .leading) {
                        Rectangle()
                            .fill(color.opacity(0.30))
                            .frame(width: 1)
                            .padding(.leading, 12)
                            .allowsHitTesting(false)
                    }

                    if let projectID = scope.projectID {
                        addWorkButton(for: projectID, projectName: name)
                    } else if scope == .unassigned {
                        addUnassignedWorkButton
                    }
                }
                .transition(ExpansionMotion.transition)
            }
        }
    }

    @ViewBuilder
    private func workGroups(_ items: [WorkItem], today: String, scope: WorkFilter) -> some View {
        let sections = WorkSection.grouped(items, today: today)
        ForEach(WorkSection.allCases) { section in
            if let items = sections[section], !items.isEmpty {
                workSection(section, items: items, scope: scope, today: today)
            }
        }
    }

    @ViewBuilder
    private func workSection(_ section: WorkSection, items: [WorkItem], scope: WorkFilter, today: String) -> some View {
        if section == .completed {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedCompleted.contains(scope) },
                set: { expanded in
                    if expanded {
                        expandedCompleted.insert(scope)
                    } else {
                        expandedCompleted.remove(scope)
                    }
                }
            )) {
                workRows(items, group: .work(scope, section), today: today)
            } label: {
                Text("已完成（\(items.count)）")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            .disclosureGroupStyle(ExpansionDisclosureStyle())
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.heading)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(section == .overdue ? Color.red : Color.primary)
                    .accessibilityAddTraits(.isHeader)
                workRows(items, group: .work(scope, section), today: today)
            }
        }
    }

    private func workRows(_ items: [WorkItem], group: OrderGroup, today: String) -> some View {
        VStack(spacing: group.spacing) {
            ForEach(items) { item in
                let row = OrderRow(group: group, id: item.id)
                trackOrderFrame(workRow(item, row: row, canReorder: items.count > 1, today: today), for: row)
            }
        }
    }

    private func workRow(_ item: WorkItem, row: OrderRow, canReorder: Bool, today: String) -> some View {
        let isExpanded = expandedWorkSummaries.contains(item.id)

        return VStack(alignment: .leading, spacing: 8) {
            workHeader(item, row: row, isExpanded: isExpanded, canReorder: canReorder, today: today)

            if isExpanded {
                workSummary(item)
                    .padding(.leading, Self.workActionSize + Self.workHeaderSpacing)
                    .transition(ExpansionMotion.transition)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, Self.workRowVerticalPadding)
        .glassCard(in: RoundedRectangle(cornerRadius: 10))
    }

    private func workHeader(_ item: WorkItem, row: OrderRow, isExpanded: Bool,
                            canReorder: Bool, today: String) -> some View {
        let completed = item.completedAt != nil
        let completionLabel = completed ? "恢复为待完成" : "标记为已完成"
        let pinLabel = item.isPinned ? "取消置顶" : "置顶工作"
        let deadline = WorkDay.parse(item.dueDate).map(WorkMonthCalendar.dateLabel) ?? item.dueDate

        return HStack(alignment: .top, spacing: Self.workHeaderSpacing) {
            Button {
                do {
                    try store.setCompleted(id: item.id, completed: !completed)
                } catch {
                    updateError = error.localizedDescription
                }
            } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .frame(width: Self.workActionSize, height: Self.workActionSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(completed ? Color.accentColor : Color.secondary)
            .accessibilityLabel("\(completionLabel)：\(item.title)")
            .help(completionLabel)

            HStack(alignment: .center, spacing: Self.workHeaderSpacing) {
                Button {
                    withAnimation(isExpanded ? nil : ExpansionMotion.animation) {
                        if isExpanded {
                            expandedWorkSummaries.remove(item.id)
                        } else {
                            expandedWorkSummaries.insert(item.id)
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .medium))
                                .strikethrough(completed)
                                .lineLimit(2)
                            Text("截止 \(deadline)")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: Self.workActionSize)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .highPriorityGesture(timelineDrag(.assignment(item.id), title: item.title, today: today))
                .accessibilityLabel(isExpanded ? "收起概要：\(item.title)" : "展开概要：\(item.title)")
                .accessibilityValue("截止 \(deadline)")
                .accessibilityHint("可拖到上方的项目")

                if !completed {
                    Button {
                        do {
                            try store.setPinned(id: item.id, pinned: !item.isPinned)
                        } catch {
                            updateError = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 13))
                            .frame(width: Self.workActionSize, height: Self.workActionSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(item.isPinned ? Color.accentColor : Color.secondary)
                    .accessibilityLabel("\(pinLabel)：\(item.title)")
                    .help(pinLabel)
                }

                iconButton("编辑工作：\(item.title)", symbol: "pencil") {
                    presentation.sheet = TimelineSheet(content: .work(item))
                }

                if canReorder {
                    orderHandle(row, title: item.title, label: "调整工作顺序：\(item.title)",
                                size: Self.workActionSize, today: today)
                }
            }
        }
    }

    private func workSummary(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    presentation.sheet = TimelineSheet(content: .work(item, focusSummary: true))
                } label: {
                    Label("添加概要", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("概要")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: item.notes)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 9)
        .padding(.vertical, 2)
        .background(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private extension WorkSection {
    var heading: String {
        switch self {
        case .pinned: return "已置顶"
        case .overdue: return "逾期"
        case .today: return "今天"
        case .upcoming: return "接下来"
        case .completed: return "已完成"
        }
    }
}

private struct WorkEditor: View {
    private enum Field { case title, summary }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var title: String
    @State private var dueDate: Date
    @State private var pickerMonth = Date()
    @State private var isShowingDueCalendar = false
    @State private var summary: String
    @State private var projectID: UUID?
    @State private var isSaving = false
    @State private var saveError: String?

    let store: WorkStore
    let item: WorkItem?
    let focusSummary: Bool

    init(store: WorkStore, item: WorkItem?, defaultProjectID: UUID?, defaultDueDate: Date, focusSummary: Bool) {
        self.store = store
        self.item = item
        self.focusSummary = focusSummary
        _title = State(initialValue: item?.title ?? "")
        _dueDate = State(initialValue: item.flatMap { WorkDay.parse($0.dueDate) } ?? defaultDueDate)
        _summary = State(initialValue: item?.notes ?? "")
        _projectID = State(initialValue: item == nil ? defaultProjectID : item?.projectID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item == nil ? "新增工作" : "编辑工作")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 5) {
                Text("标题（必填）")
                TextField("标题（必填）", text: $title, prompt: Text("输入工作标题"))
                    .labelsHidden()
                    .accessibilityLabel("标题（必填）")
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
            }

            deadlinePicker

            if !store.projects.isEmpty {
                Picker("项目", selection: $projectID) {
                    Text("未归类").tag(nil as UUID?)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                    if let id = projectID, !store.projects.contains(where: { $0.id == id }) {
                        Text("原项目").tag(Optional(id))
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("概要（选填）")
                TextEditor(text: $summary)
                    .accessibilityLabel("概要（选填）")
                    .focused($focusedField, equals: .summary)
                    .frame(height: 136)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .glassCard(in: RoundedRectangle(cornerRadius: 9))
                    .task { @MainActor in
                        if focusSummary { focusedField = .summary }
                    }
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .buttonStyle(GlassActionStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button(isSaving ? "保存中…" : "保存", action: save)
                    .buttonStyle(GlassActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 15))
        .padding(18)
        .frame(width: 344)
        .background(.regularMaterial)
        .defaultFocus($focusedField, focusSummary ? .summary : .title)
    }

    private var deadlinePicker: some View {
        let label = WorkMonthCalendar.dateLabel(dueDate)

        return HStack(spacing: 8) {
            Text("截止日期")
                .accessibilityHidden(true)
            Button {
                pickerMonth = dueDate
                isShowingDueCalendar = true
            } label: {
                Label(label, systemImage: "calendar")
                    .monospacedDigit()
            }
            .buttonStyle(GlassActionStyle())
            .accessibilityLabel("截止日期")
            .accessibilityValue(label)
            .popover(isPresented: $isShowingDueCalendar) {
                WorkMonthCalendar(month: $pickerMonth, today: Date(), selectedDay: WorkDay.local(dueDate)) { day in
                    dueDate = day
                    isShowingDueCalendar = false
                }
                .padding(10)
                .frame(width: 314)
            }
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let day = WorkDay.local(dueDate)
                if let item {
                    try store.update(id: item.id, title: title, dueDate: day, notes: summary, projectID: projectID)
                } else {
                    try store.create(title: title, dueDate: day, notes: summary, projectID: projectID)
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
