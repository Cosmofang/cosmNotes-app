import AppKit
import Sparkle

@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    private static let reminderKey = "Updates.lastPreparedVersion"
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )
    private let checkItem = NSMenuItem(title: "检查更新…", action: #selector(checkManually), keyEquivalent: "")
    private let installItem = NSMenuItem(title: "重启并更新…", action: #selector(installManually), keyEquivalent: "")
    private weak var statusButton: NSStatusBarButton?
    private var pendingInstallation: (() -> Void)?
    private var pendingVersion: String?
    private var showingReminder = false

    func addMenuItems(to menu: NSMenu, statusButton: NSStatusBarButton?) {
        self.statusButton = statusButton
        checkItem.target = self
        installItem.target = self
        installItem.isHidden = true
        menu.addItem(checkItem)
        menu.addItem(installItem)
    }

    func start() {
        controller.startUpdater()
    }

    func remindIfActive() {
        guard let version = pendingVersion, NSApp.isActive, NSApp.modalWindow == nil,
              !NSApp.windows.contains(where: { $0.attachedSheet != nil }),
              AppIdentity.preferences.string(forKey: Self.reminderKey) != version else { return }
        showReadyToInstall(version: version)
    }

    @objc private func checkManually() {
        if let version = pendingVersion {
            showReadyToInstall(version: version)
        } else {
            controller.checkForUpdates(nil)
        }
    }

    @objc private func installManually() {
        if let version = pendingVersion { showReadyToInstall(version: version) }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock install: @escaping () -> Void) -> Bool {
        pendingVersion = item.displayVersionString
        pendingInstallation = install
        installItem.isHidden = false
        statusButton?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "cosmNotes 更新已就绪")
        statusButton?.toolTip = "cosmNotes \(item.displayVersionString) 更新已就绪"
        Task { @MainActor [weak self] in self?.remindIfActive() }
        return true
    }

    private func showReadyToInstall(version: String) {
        guard !showingReminder, let install = pendingInstallation else { return }
        showingReminder = true
        defer { showingReminder = false }
        AppIdentity.preferences.set(version, forKey: Self.reminderKey)

        let alert = NSAlert()
        alert.messageText = "cosmNotes \(version) 更新已就绪"
        alert.informativeText = "重启应用以完成更新。已经保存的工作和便签会在新版中打开。"
        alert.addButton(withTitle: "重启并更新")
        alert.addButton(withTitle: "稍后")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            pendingInstallation = nil
            pendingVersion = nil
            installItem.isHidden = true
            install()
        }
    }
}
