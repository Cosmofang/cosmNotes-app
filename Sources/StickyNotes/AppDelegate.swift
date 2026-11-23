import AppKit
import CosmNotesWork
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    @MainActor private lazy var updates = UpdateController()
    private var controllers: [UUID: NoteWindowController] = [:]
    private var historyWindow: NSWindow?
    private lazy var workStore = WorkStore(
        fileURL: AppIdentity.dataDirectory.appendingPathComponent("work-items.json"))
    private lazy var workTimeline = WorkTimelineController(store: workStore)
    private var didLoadNotes = false
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护: 如果已经有一份在运行, 激活它并退出自己
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: AppIdentity.bundleIdentifier)
        if running.count > 1 {
            running.first { $0 != NSRunningApplication.current }?
                .activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        AppAppearance.restore()
        setupStatusItem()

        NoteStore.shared.load()
        didLoadNotes = true
        let workCommandLaunch = ProcessInfo.processInfo.environment["COSMNOTES_BACKGROUND_WORK"] == "1"
            || pendingURLs.contains { $0.scheme == AppIdentity.urlScheme && $0.host == "work-create" }
        let showWorkOnLaunch = CommandLine.arguments.contains("--show-work")
            || (!workCommandLaunch && NoteStore.shared.notes.isEmpty && !workStore.items.isEmpty)
        if NoteStore.shared.notes.isEmpty {
            if !workCommandLaunch && !showWorkOnLaunch {
                // 第一次使用给欢迎教程, 之后弹类型选择
                if AppIdentity.preferences.bool(forKey: "hasLaunchedBefore") {
                    if pendingURLs.isEmpty { promptNewNote() }
                } else {
                    createWelcomeNote()
                    AppIdentity.preferences.set(true, forKey: "hasLaunchedBefore")
                }
            }
        } else {
            NoteStore.shared.notes.forEach(showWindow)
        }

        pendingURLs.forEach(handleURL)
        pendingURLs.removeAll()

        if CommandLine.arguments.contains("--show-history") {
            showHistory()
        }
        if showWorkOnLaunch {
            showWorkTimeline()
        }
        updates.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updates.remindIfActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard didLoadNotes else { return }
        NoteStore.shared.saveNow()
    }

    /// 在启动台/访达里再次点开 app 时:
    /// 没有便签 → 创建一张新的; 已有便签 → 全部带到前面
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard didLoadNotes else { return true }
        // 通过 URL 创建便签时 open 也会触发 reopen, 跳过避免弹类型选择框
        if Date().timeIntervalSince(lastURLHandled) < 2 { return true }
        if controllers.isEmpty {
            if workTimeline.window?.isVisible == true || !workStore.items.isEmpty {
                showWorkTimeline()
            } else {
                promptNewNote()
            }
        } else {
            showAll()
        }
        return true
    }

    // MARK: 菜单栏图标

    @MainActor
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "note.text", accessibilityDescription: AppIdentity.name)

        let menu = NSMenu()
        menu.addItem(withTitle: "新建文字便签", action: #selector(newTextNote), keyEquivalent: "n")
        menu.addItem(withTitle: "新建待办事项", action: #selector(newTodoNote), keyEquivalent: "t")
        menu.addItem(withTitle: "历史便签", action: #selector(showHistory), keyEquivalent: "h")
        menu.addItem(.separator())

        menu.addItem(withTitle: "工作时间轴", action: #selector(showWorkTimeline), keyEquivalent: "")
        menu.addItem(withTitle: "新增工作…", action: #selector(newWork), keyEquivalent: "")
        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem(
            title: "加粗快捷键: \(BoldShortcut.display)",
            action: #selector(setBoldShortcut), keyEquivalent: ""))

        menu.addItem(.separator())
        updates.addMenuItems(to: menu, statusButton: statusItem.button)
        menu.addItem(withTitle: "关于 \(AppIdentity.name)", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "退出 \(AppIdentity.name)", action: #selector(quit), keyEquivalent: "q")
        menu.items.filter { $0.target == nil }.forEach { $0.target = self }
        statusItem.menu = menu
    }

    // MARK: 便签管理

    @objc private func newTextNote() { createNote(kind: .text) }
    @objc private func newTodoNote() { createNote(kind: .todo) }
    @objc private func showWorkTimeline() { workTimeline.show() }
    @objc private func newWork() { workTimeline.showNewWork() }

    /// 弹出类型选择, 再创建对应类型的便签
    private func promptNewNote() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "创建新便签"
        alert.informativeText = "选择便签类型:"
        alert.addButton(withTitle: "📝 文字便签")
        alert.addButton(withTitle: "✅ 待办事项")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  createNote(kind: .text)
        case .alertSecondButtonReturn: createNote(kind: .todo)
        default: break
        }
    }

    @discardableResult
    private func createNote(kind: NoteKind, text: String = "", theme: NoteTheme? = nil,
                            mode: NoteMode = .floating, preview: Bool = false,
                            collapsed: Bool = false,
                            highlights: [TextHighlight] = [],
                            bolds: [TextHighlight] = []) -> Note {
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(
            x: screen.midX - 140 + cascade,
            y: screen.midY - 20 - cascade,
            width: 280, height: 280)

        // 未指定颜色时顺延取色, 避免全是黄色
        let usedThemes = NoteStore.shared.notes.map(\.theme)
        let nextTheme = theme
            ?? NoteTheme.allCases.first { !usedThemes.contains($0) }
            ?? NoteTheme.allCases[NoteStore.shared.notes.count % NoteTheme.allCases.count]

        let note = Note(text: text, kind: kind, theme: nextTheme,
                        mode: mode, isPreview: preview,
                        highlights: highlights, bolds: bolds, frame: frame)
        NoteStore.shared.add(note)
        showWindow(note)
        if collapsed {
            controllers[note.id]?.toggleCollapse()
        }
        return note
    }

    // MARK: URL Scheme (cosmnotes://add?...)
    // 供命令行 / AI 工具以细粒度命令操作便签。
    // 数据始终由正在运行的 App 通过 NoteStore 修改和保存，
    // 避免外部工具直接重写 notes.json 造成竞争或数据丢失。
    //
    // 创建:
    //   open "cosmnotes://add?kind=todo&theme=mint&text=%E5%86%85%E5%AE%B9"
    // 参数: kind=text|todo, theme=lemon|peach|mint|sky|lilac,
    //       mode=floating|normal|desktop, preview=1, collapsed=1, text=百分号编码内容,
    //       highlight/bold=荧光和加粗范围, 格式 "起点,长度;起点,长度" (UTF-16), 空串=清空
    // 更新: cosmnotes://update?id=<UUID>&text=...&theme=...&mode=...&preview=0|1&collapsed=0|1
    //       &highlight=...&bold=...  (改了 text 又不传标记, 旧标记会被清空)
    // 删除: cosmnotes://delete?id=<UUID>
    // 恢复: cosmnotes://restore?id=<历史记录 UUID>
    // 删除历史: cosmnotes://history-delete?id=<历史记录 UUID>
    // 移动/缩放: cosmnotes://frame?id=<UUID>&x=...&y=...&w=...&h=...

    private var lastURLHandled = Date.distantPast

    func application(_ application: NSApplication, open urls: [URL]) {
        guard didLoadNotes else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        urls.forEach(handleURL)
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == AppIdentity.urlScheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        lastURLHandled = Date()

        var q: [String: String] = [:]
        comps.queryItems?.forEach { q[$0.name] = $0.value }

        switch url.host {
        case "work-create":
            guard let rawID = q["id"], let id = UUID(uuidString: rawID) else { return }
            do {
                _ = try WorkInbox.applyCreate(id: id, directory: AppIdentity.dataDirectory, store: workStore)
                workTimeline.show(activate: false)
            } catch {
                NSLog("cosmNotes: 无法完成工作新增请求 %@", id.uuidString)
            }
        case "add":
            let text = q["text"] ?? ""
            createNote(
                kind: NoteKind(rawValue: q["kind"] ?? "") ?? .text,
                text: text,
                theme: NoteTheme(rawValue: q["theme"] ?? ""),
                mode: NoteMode(rawValue: q["mode"] ?? "") ?? .floating,
                preview: q["preview"] == "1",
                collapsed: q["collapsed"] == "1",
                highlights: parseMarks(q["highlight"], in: text),
                bolds: parseMarks(q["bold"], in: text))

        case "update":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }) else { return }
            if let text = q["text"] {
                note.text = text
                // 外部入口是整段替换，旧文字范围已不再可靠;
                // 调用方要保留标记就自己算好新范围一起传进来。
                note.highlights = []
                note.bolds = []
            }
            if let marks = q["highlight"] { note.highlights = parseMarks(marks, in: note.text) }
            if let marks = q["bold"] { note.bolds = parseMarks(marks, in: note.text) }
            if let theme = NoteTheme(rawValue: q["theme"] ?? "") { note.theme = theme }
            if let mode = NoteMode(rawValue: q["mode"] ?? "") {
                note.mode = mode
                controllers[id]?.applyMode()
            }
            if note.kind == .text, let preview = queryBool(q["preview"]) {
                note.isPreview = preview
            }
            if let collapsed = queryBool(q["collapsed"]), collapsed != note.isCollapsed {
                controllers[id]?.toggleCollapse()
            } else if note.isCollapsed, q["text"] != nil {
                // 折叠条宽度跟随新标题重算，不需要先展开再折叠。
                controllers[id]?.refreshCollapsedWidth()
            }

        case "delete":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }) else { return }
            delete(note)

        case "restore":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let item = NoteStore.shared.archived.first(where: { $0.id == id }) else { return }
            restore(item)

        case "history-delete":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr) else { return }
            NoteStore.shared.removeArchived(id)

        case "frame":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }),
                  let controller = controllers[id], let window = controller.window else { return }
            var frame = window.frame
            if let value = queryDouble(q["x"]) { frame.origin.x = value }
            if let value = queryDouble(q["y"]) { frame.origin.y = value }
            if let value = queryDouble(q["w"]) { frame.size.width = max(120, value) }
            if let value = queryDouble(q["h"]) {
                frame.size.height = note.isCollapsed ? NoteWindowController.barHeight : max(120, value)
            }
            if !note.isCollapsed {
                // 外部指定的尺寸和手动拖的一样算数, 否则会被自动适配立刻改回去
                if q["w"] != nil { note.manualWidth = true }
                if q["h"] != nil { note.manualHeight = true }
            }
            window.setFrame(frame, display: true, animate: true)
            note.frame = frame
            if !note.isCollapsed { note.expandedFrame = frame }
            NoteStore.shared.scheduleSave()

        case "show-all":
            showAll()

        case "show-history":
            showHistory()

        default:
            break
        }
    }

    /// 标记参数格式: "起点,长度;起点,长度" (UTF-16 下标), 空串表示清空。
    /// 越界的段直接丢掉, 免得外部工具算错位置把文字画花。
    private func parseMarks(_ value: String?, in text: String) -> [TextHighlight] {
        guard let value, !value.isEmpty else { return [] }
        let limit = (text as NSString).length
        return value.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let loc = Int(parts[0]), let len = Int(parts[1]),
                  loc >= 0, len > 0, loc + len <= limit else { return nil }
            return TextHighlight(NSRange(location: loc, length: len))
        }
    }

    private func queryBool(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "1", "true", "yes":  return true
        case "0", "false", "no": return false
        default:                    return nil
        }
    }

    private func queryDouble(_ value: String?) -> CGFloat? {
        guard let value, let number = Double(value), number.isFinite else { return nil }
        return CGFloat(number)
    }

    @objc private func showAll() {
        NSApp.activate(ignoringOtherApps: true)
        for controller in controllers.values {
            controller.window?.orderFront(nil)
            // 贴在桌面的便签临时浮上来露个脸, 3 秒后沉回桌面
            if controller.note.mode == .desktop {
                controller.window?.level = .floating
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak controller] in
                    controller?.applyMode()
                }
            }
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机启动失败"
            alert.informativeText = "\(error.localizedDescription)\n\n提示: 应用需要放在“应用程序”文件夹中才能注册开机启动。"
            alert.runModal()
        }
    }

    /// 改加粗快捷键: 弹窗期间直接按下新组合键即可
    @objc private func setBoldShortcut(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "设置加粗快捷键"
        alert.informativeText = "现在按下新的组合键 (至少含 ⌘/⌃/⌥ 之一)。当前: \(BoldShortcut.display)"
        alert.addButton(withTitle: "恢复默认 ⌘B")
        alert.addButton(withTitle: "取消")
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !mods.intersection([.command, .control, .option]).isEmpty,
                  let ch = event.charactersIgnoringModifiers?.lowercased(),
                  ch.count == 1, ch != " " else { return event }
            BoldShortcut.save(key: ch, modifiers: mods)
            NSApp.abortModal()
            return nil
        }
        let response = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if response == .alertFirstButtonReturn {
            BoldShortcut.save(key: "b", modifiers: [.command])
        }
        sender.title = "加粗快捷键: \(BoldShortcut.display)"
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppIdentity.name,
            .credits: NSAttributedString(string: "StickyNotes 大神的迭代版\n原作者 simony3 · StickyNotes v2.2.0 · MIT")
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showWindow(_ note: Note) {
        if note.frame.width < 50 {
            note.frame = CGRect(x: 200, y: 200, width: 280, height: 280)
        }
        let controller = NoteWindowController(
            note: note,
            onDelete: { [weak self] n in self?.delete(n) },
            onNewNote: { [weak self] kind in self?.createNote(kind: kind) }
        )
        controller.window?.setFrame(note.frame, display: true)
        controllers[note.id] = controller
        // 淡入出现
        controller.window?.alphaValue = 0
        controller.window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = ExpansionMotion.duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            controller.window?.animator().alphaValue = 1
        }
        if note.mode != .desktop {
            controller.window?.makeKey()
        }
    }

    private func delete(_ note: Note) {
        controllers[note.id]?.window?.orderOut(nil)
        controllers[note.id] = nil
        NoteStore.shared.archive(note)   // 有内容的便签先归档进历史
        NoteStore.shared.remove(note)
    }

    // MARK: 历史便签

    @objc private func showHistory() {
        NSApp.activate(ignoringOtherApps: true)
        if historyWindow == nil {
            let view = HistoryView(store: NoteStore.shared) { [weak self] item in
                self?.restore(item)
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = "历史便签"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.center()
            historyWindow = win
        }
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    /// 把历史记录恢复成一张新便签
    private func restore(_ item: ArchivedNote) {
        guard let archived = NoteStore.shared.unarchive(item.id) else { return }
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = Note(
            text: archived.text, kind: archived.kind, theme: archived.theme,
            highlights: archived.highlights,
            bolds: archived.bolds,
            frame: CGRect(x: screen.midX - 140 + cascade, y: screen.midY - 20 - cascade,
                          width: 280, height: 280))
        NoteStore.shared.add(note)
        showWindow(note)
    }

    private func createWelcomeNote() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = Note(
            text: """
            # 欢迎使用 \(AppIdentity.name) 👋

            这是一张支持 **Markdown** 的便签:

            - 点右上角 👁 预览渲染效果
            - 点 ✏️ 回到编辑模式
            - 鼠标悬停顶栏可换颜色、切换窗口模式
            - [ ] 待办事项写法
            - [x] 已完成事项

            > 内容自动保存, 拖动边缘可调整大小

            菜单栏的 📝 图标可以新建便签、设置开机启动。
            """,
            theme: .lemon,
            frame: CGRect(x: screen.midX - 160, y: screen.midY - 40, width: 320, height: 360))
        NoteStore.shared.add(note)
        showWindow(note)
    }
}
