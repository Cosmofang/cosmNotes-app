import AppKit
import CosmNotesUpdates

@MainActor
final class UpdateController: NSObject {
    private static let reminderKey = "Updates.lastRemindedVersion"
    private static let interval: TimeInterval = 4 * 60 * 60

    private let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private let checkItem = NSMenuItem(title: "检查更新…", action: #selector(checkManually), keyEquivalent: "")
    private let downloadItem = NSMenuItem(title: "", action: #selector(downloadUpdate), keyEquivalent: "")
    private weak var statusButton: NSStatusBarButton?
    private var timer: Timer?
    private var available: ReleaseUpdate?
    private var checking = false
    private var manualResultRequested = false

    func addMenuItems(to menu: NSMenu, statusButton: NSStatusBarButton?) {
        self.statusButton = statusButton
        checkItem.target = self
        downloadItem.target = self
        downloadItem.isHidden = true
        menu.addItem(checkItem)
        menu.addItem(downloadItem)
    }

    func start() {
        guard timer == nil, !installedVersion.isEmpty else { return }
        check()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func remindIfActive() {
        guard let update = available, NSApp.isActive, NSApp.modalWindow == nil,
              !NSApp.windows.contains(where: { $0.attachedSheet != nil }),
              AppIdentity.preferences.string(forKey: Self.reminderKey) != update.version else { return }
        showUpdate(update)
    }

    @objc private func checkManually() {
        manualResultRequested = true
        check()
    }

    @objc private func downloadUpdate() {
        if let available { NSWorkspace.shared.open(available.downloadURL) }
    }

    private func check() {
        guard !checking else { return }
        checking = true
        checkItem.title = "正在检查更新…"
        Task {
            let result: Result<ReleaseUpdate?, Error>
            do {
                result = .success(try await GitHubRelease.check(repository: AppIdentity.releaseRepository,
                                                               installedVersion: installedVersion))
            } catch {
                result = .failure(error)
            }
            receive(result)
        }
    }

    private func receive(_ result: Result<ReleaseUpdate?, Error>) {
        let manual = manualResultRequested
        manualResultRequested = false
        checking = false
        checkItem.title = "检查更新…"

        switch result {
        case .success(let update):
            available = update
            downloadItem.isHidden = update == nil
            downloadItem.title = update.map { "下载更新 v\($0.version)…" } ?? ""
            statusButton?.image = NSImage(
                systemSymbolName: update == nil ? "note.text" : "arrow.down.circle",
                accessibilityDescription: update == nil ? AppIdentity.name : "cosmNotes 有更新"
            )
            statusButton?.toolTip = update.map { "cosmNotes v\($0.version) 可下载" }
            if manual {
                if let update {
                    showUpdate(update)
                } else {
                    showMessage("已是最新版本", detail: "当前版本 v\(installedVersion)。")
                }
            } else {
                remindIfActive()
            }
        case .failure(let error):
            if manual { showMessage("暂时无法检查更新", detail: error.localizedDescription) }
        }
    }

    private func showUpdate(_ update: ReleaseUpdate) {
        AppIdentity.preferences.set(update.version, forKey: Self.reminderKey)
        let alert = NSAlert()
        alert.messageText = "cosmNotes v\(update.version) 可下载"
        alert.informativeText = "当前版本 v\(installedVersion)。下载并解压后，退出 cosmNotes，再将新应用拖入「应用程序」替换旧版。"
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "稍后")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.downloadURL)
        }
    }

    private func showMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        NSApp.activate()
        alert.runModal()
    }
}
