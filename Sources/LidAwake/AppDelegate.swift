import AppKit
import LidAwakeCore

private final class SettingsPanelController: NSObject, NSWindowDelegate {
    weak var panel: NSPanel?
    private(set) var response: NSApplication.ModalResponse = .cancel
    private var didFinish = false

    @objc func save(_ sender: Any?) {
        finish(with: .OK)
    }

    @objc func cancel(_ sender: Any?) {
        finish(with: .cancel)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: .cancel, closePanel: false)
    }

    private func finish(with response: NSApplication.ModalResponse, closePanel: Bool = true) {
        guard !didFinish else {
            return
        }

        didFinish = true
        self.response = response
        if closePanel {
            panel?.close()
        }
        NSApp.stopModal(withCode: response)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Brand {
        static let appName = "RoamVibing"
        static let subtitle = "Keep coding when the lid closes."
    }

    private enum BatterySafety {
        static let thresholds = [10, 15, 20, 25, 30, 40, 50]
        static let checkInterval: TimeInterval = 30
    }

    private enum ThermalSafety {
        static let checkInterval: TimeInterval = 30
    }

    private enum InstantLock {
        static let armingDelays: [TimeInterval] = [5, 10, 30, 60]
        static let checkInterval: TimeInterval = 0.2
    }

    private enum SettingsDialog {
        static let contentWidth: CGFloat = 440
        static let windowWidth: CGFloat = 540
        static let windowHeight: CGFloat = 620
        static let controlHeight: CGFloat = 28
        static let rowLabelWidth: CGFloat = 170
        static let rowGap: CGFloat = 12
        static let verticalSpacing: CGFloat = 10
        static let sectionSpacing: CGFloat = 18
        static let panelPadding: CGFloat = 20
    }

    private enum PowerOperation: Equatable {
        case startingClosedLid
        case stoppingAwakeSession
        case switchingToNormalAwake
        case disablingClosedLidBypass

        var statusTitle: String {
            switch self {
            case .startingClosedLid:
                return "\(Brand.appName): Starting Closed-Lid Mode"
            case .stoppingAwakeSession:
                return "\(Brand.appName): Stopping RoamVibing Session"
            case .switchingToNormalAwake:
                return "\(Brand.appName): Switching to Normal Awake"
            case .disablingClosedLidBypass:
                return "\(Brand.appName): Disabling Closed-Lid Bypass"
            }
        }
    }

    private enum HelperOperation: Equatable {
        case installing
        case uninstalling

        var statusTitle: String {
            switch self {
            case .installing:
                return "\(Brand.appName): Installing Touch ID Helper"
            case .uninstalling:
                return "\(Brand.appName): Uninstalling Touch ID Helper"
            }
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let powerOperationQueue = DispatchQueue(label: "com.local.RoamVibing.power-operation")
    private let helperOperationQueue = DispatchQueue(label: "com.local.RoamVibing.helper-operation")
    private let batterySafetySettings = BatterySafetySettingsStore()
    private let thermalSafetySettings = ThermalSafetySettingsStore()
    private let instantActivityLockSettings = InstantActivityLockSettingsStore()
    private let muteOnLidCloseSettings = MuteOnLidCloseSettingsStore()
    private let batteryReader = IOKitBatteryReader()
    private let thermalStateReader = MacThermalStateReader()
    private let inputActivityReader = MacInputActivityReader()
    private let lidStateReader = MacLidStateReader()
    private var batterySafetyTimer: Timer?
    private var thermalSafetyTimer: Timer?
    private var instantActivityLockTimer: Timer?
    private var isShowingLowBatteryAlert = false
    private var isShowingThermalSafetyAlert = false
    private var hasShownThermalSafetyError = false
    private var activePowerOperation: PowerOperation?
    private var activeHelperOperation: HelperOperation?
    private lazy var session = makeSession()
    private lazy var lowBatteryGuard = makeLowBatteryGuard()
    private lazy var thermalSafetyGuard = makeThermalSafetyGuard()
    private lazy var instantActivityLockGuard = makeInstantActivityLockGuard()
    private lazy var muteOnLidCloseGuard = makeMuteOnLidCloseGuard()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        startBatterySafetyTimer()
        startThermalSafetyTimer()
        startInstantActivityLockTimer()
        rebuildMenu()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard activePowerOperation == nil, activeHelperOperation == nil else {
            rebuildMenu()
            return .terminateCancel
        }

        guard session.state != .stopped else {
            return .terminateNow
        }

        do {
            try session.stop(intent: .safety)
            batterySafetyTimer?.invalidate()
            thermalSafetyTimer?.invalidate()
            instantActivityLockTimer?.invalidate()
            return .terminateNow
        } catch {
            presentError(error, title: "Could Not Turn Off \(Brand.appName)")
            return .terminateCancel
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.toolTip = "\(Brand.appName): \(Brand.subtitle)"
        button.setAccessibilityLabel(Brand.appName)
        updateStatusIcon()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let subtitle = NSMenuItem(title: Brand.subtitle, action: nil, keyEquivalent: "")
        subtitle.isEnabled = false
        menu.addItem(subtitle)
        menu.addItem(.separator())

        let normalItem = NSMenuItem(
            title: normalToggleTitle,
            action: #selector(toggleNormalMode),
            keyEquivalent: "n"
        )
        normalItem.target = self
        normalItem.isEnabled = activePowerOperation == nil && activeHelperOperation == nil
        normalItem.state = session.state == .running(.normal) ? .on : .off
        menu.addItem(normalItem)

        let closedLidItem = NSMenuItem(
            title: closedLidToggleTitle,
            action: #selector(toggleClosedLidMode),
            keyEquivalent: "l"
        )
        closedLidItem.target = self
        closedLidItem.isEnabled = activePowerOperation == nil && activeHelperOperation == nil
        closedLidItem.state = session.state == .running(.closedLid) ? .on : .off
        menu.addItem(closedLidItem)

        let stopItem = NSMenuItem(
            title: "Stop RoamVibing Session",
            action: #selector(stopSession),
            keyEquivalent: "s"
        )
        stopItem.target = self
        stopItem.isEnabled = session.state != .stopped && activePowerOperation == nil && activeHelperOperation == nil
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.isEnabled = activePowerOperation == nil && activeHelperOperation == nil
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let safetyItem = NSMenuItem(
            title: "Safety Notes",
            action: #selector(showSafetyNotes),
            keyEquivalent: ""
        )
        safetyItem.target = self
        menu.addItem(safetyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit \(Brand.appName)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = activePowerOperation == nil && activeHelperOperation == nil
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatusIcon()
    }

    private func makeClosedLidPowerManager() -> ClosedLidPowerManaging {
        ClosedLidPowerManagerSelection.make()
    }

    private func makeSession() -> AwakeSession {
        AwakeSession(
            assertions: IOKitAssertionManager(),
            closedLidPower: makeClosedLidPowerManager()
        )
    }

    private func makeLowBatteryGuard() -> LowBatteryGuard {
        LowBatteryGuard(
            session: session,
            batteryReader: batteryReader,
            policy: batterySafetySettings.policy
        )
    }

    private func makeThermalSafetyGuard() -> ThermalSafetyGuard {
        ThermalSafetyGuard(
            session: session,
            thermalStateReader: thermalStateReader,
            policy: thermalSafetySettings.policy
        )
    }

    private func makeInstantActivityLockGuard() -> InstantActivityLockGuard {
        InstantActivityLockGuard(
            session: session,
            inputActivityReader: inputActivityReader,
            lidStateReader: lidStateReader,
            screenLocker: CommandScreenLocker(),
            policy: instantActivityLockSettings.policy
        )
    }

    private func makeMuteOnLidCloseGuard() -> MuteOnLidCloseGuard {
        MuteOnLidCloseGuard(
            lidStateReader: lidStateReader,
            audioOutputMuter: MacAudioOutputMuter(),
            policy: muteOnLidCloseSettings.policy
        )
    }

    private func rebuildRuntimeObjects() {
        guard activePowerOperation == nil, activeHelperOperation == nil, session.state == .stopped else {
            return
        }

        session = makeSession()
        lowBatteryGuard = LowBatteryGuard(
            session: session,
            batteryReader: batteryReader,
            policy: batterySafetySettings.policy
        )
        thermalSafetyGuard = ThermalSafetyGuard(
            session: session,
            thermalStateReader: thermalStateReader,
            policy: thermalSafetySettings.policy
        )
        instantActivityLockGuard = InstantActivityLockGuard(
            session: session,
            inputActivityReader: inputActivityReader,
            lidStateReader: lidStateReader,
            screenLocker: CommandScreenLocker(),
            policy: instantActivityLockSettings.policy
        )
        muteOnLidCloseGuard = makeMuteOnLidCloseGuard()
    }

    private var statusTitle: String {
        if let activePowerOperation {
            return activePowerOperation.statusTitle
        }
        if let activeHelperOperation {
            return activeHelperOperation.statusTitle
        }

        switch session.state {
        case .stopped:
            return "\(Brand.appName): Off"
        case .running(.normal):
            return "\(Brand.appName): Normal Awake On"
        case .running(.closedLid):
            return "\(Brand.appName): Closed-Lid Mode On"
        }
    }

    private var normalToggleTitle: String {
        session.state == .running(.normal) ? "Stop Normal Awake" : "Start Normal Awake"
    }

    private var closedLidToggleTitle: String {
        session.state == .running(.closedLid) ? "Stop Closed-Lid Mode" : "Start Closed-Lid Mode"
    }

    private var shouldUsePrivilegedHelper: Bool {
        ClosedLidPowerManagerSelection.shouldUsePrivilegedHelper()
    }

    private var touchIDHelperStatusTitle: String {
        let helperStatus = PrivilegedHelperInstaller().status

        switch helperStatus {
        case .notRegistered, .notFound:
            return "Touch ID Helper: Not Installed"
        case .requiresApproval:
            return "Touch ID Helper: Requires Approval"
        case .enabled:
            return shouldUsePrivilegedHelper
                ? "Touch ID Helper: Installed, in use"
                : "Touch ID Helper: Installed, not in use"
        }
    }

    private func updateStatusIcon() {
        let image = StatusIconFactory.makeCoderIcon(active: session.state != .stopped || activePowerOperation != nil || activeHelperOperation != nil)
        statusItem.button?.image = image
    }

    @objc private func toggleNormalMode() {
        if session.state == .running(.normal) {
            stopSession()
            return
        }

        start(mode: .normal)
    }

    @objc private func toggleClosedLidMode() {
        if session.state == .running(.closedLid) {
            stopSession()
            return
        }

        guard confirmClosedLidMode() else {
            return
        }

        start(mode: .closedLid)
    }

    @objc private func stopSession() {
        guard activePowerOperation == nil, activeHelperOperation == nil else {
            rebuildMenu()
            return
        }

        if session.state == .running(.closedLid) {
            beginPowerOperation(.stoppingAwakeSession, errorTitle: "Could Not Stop RoamVibing Session") {
                try self.session.stop()
            } didFinish: {
                self.instantActivityLockGuard.reset()
                self.muteOnLidCloseGuard.reset()
            }
            return
        }

        do {
            try session.stop()
            instantActivityLockGuard.reset()
            muteOnLidCloseGuard.reset()
        } catch {
            presentError(error, title: "Could Not Stop RoamVibing Session")
        }

        rebuildMenu()
    }

    @objc private func forceDisableClosedLidBypass() {
        guard activePowerOperation == nil, activeHelperOperation == nil else {
            rebuildMenu()
            return
        }

        if session.state == .running(.closedLid) {
            beginPowerOperation(.stoppingAwakeSession, errorTitle: "Could Not Disable Closed-Lid Bypass") {
                try self.session.stop(intent: .safety)
            } didFinish: {
                self.instantActivityLockGuard.reset()
                self.muteOnLidCloseGuard.reset()
            }
            return
        }

        beginPowerOperation(.disablingClosedLidBypass, errorTitle: "Could Not Disable Closed-Lid Bypass") {
            try self.makeClosedLidPowerManager().setClosedLidBypassEnabled(false, intent: .safety)
        }
    }

    @objc private func installPrivilegedHelper() {
        let helperStatus = PrivilegedHelperInstaller().status
        guard activePowerOperation == nil,
              activeHelperOperation == nil,
              session.state == .stopped,
              helperStatus != .enabled
        else {
            rebuildMenu()
            return
        }

        beginHelperOperation(.installing, errorTitle: "Could Not Install Touch ID Helper") {
            try PrivilegedHelperInstaller().install()
        } didFinish: {
            self.showAlert(
                title: "Touch ID Helper Installed",
                message: "Start Closed-Lid Mode with Touch ID or your Mac password after the helper is installed. macOS may still require System Settings approval before the helper can run."
            )
        }
    }

    @objc private func togglePrivilegedHelperUse() {
        guard activePowerOperation == nil, activeHelperOperation == nil, session.state == .stopped else {
            rebuildMenu()
            return
        }

        let helperStatus = PrivilegedHelperInstaller().status
        guard helperStatus == .enabled else {
            UserDefaults.standard.set(false, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)
            rebuildRuntimeObjects()
            showAlert(
                title: "Touch ID Helper Not Ready",
                message: "Install the Touch ID Helper and approve it in System Settings before using it. Until then, Closed-Lid Mode will keep using the administrator-password flow.",
                style: .warning
            )
            rebuildMenu()
            return
        }

        UserDefaults.standard.set(!shouldUsePrivilegedHelper, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)
        rebuildRuntimeObjects()
        rebuildMenu()
    }

    @objc private func uninstallPrivilegedHelper() {
        let helperStatus = PrivilegedHelperInstaller().status
        guard activePowerOperation == nil,
              activeHelperOperation == nil,
              session.state == .stopped,
              helperStatus != .notRegistered,
              helperStatus != .notFound
        else {
            rebuildMenu()
            return
        }

        beginHelperOperation(.uninstalling, errorTitle: "Could Not Uninstall Touch ID Helper") {
            try PrivilegedHelperInstaller().uninstall()
        } didFinish: {
            UserDefaults.standard.set(false, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)
            self.rebuildRuntimeObjects()
            self.showAlert(
                title: "Touch ID Helper Uninstalled",
                message: "RoamVibing is back to the administrator-password flow for Closed-Lid Mode."
            )
        }
    }

    @objc private func showSettings() {
        let batteryPolicy = batterySafetySettings.policy
        let thermalPolicy = thermalSafetySettings.policy
        let instantPolicy = instantActivityLockSettings.policy
        let mutePolicy = muteOnLidCloseSettings.policy
        let helperStatus = PrivilegedHelperInstaller().status

        let batteryCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        batteryCheckbox.state = batteryPolicy.isEnabled ? .on : .off
        batteryCheckbox.setAccessibilityLabel("Enable Battery Safety")
        batteryCheckbox.setAccessibilityHelp("Stops the RoamVibing session below your threshold while on battery.")

        let batteryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for threshold in BatterySafety.thresholds {
            batteryPopup.addItem(withTitle: "\(threshold)%")
            batteryPopup.lastItem?.representedObject = threshold
        }
        let selectedThreshold = BatterySafety.thresholds.contains(batteryPolicy.thresholdPercentage)
            ? batteryPolicy.thresholdPercentage
            : LowBatteryPolicy.defaultThresholdPercentage
        batteryPopup.selectItem(withTitle: "\(selectedThreshold)%")
        batteryPopup.isEnabled = batteryPolicy.isEnabled
        batteryCheckbox.target = self
        batteryCheckbox.action = #selector(toggleBatteryThresholdPopup(_:))
        batteryCheckbox.tag = 1
        batteryPopup.tag = 2
        batteryPopup.setAccessibilityLabel("Battery threshold")
        batteryPopup.setAccessibilityHelp("Choose the battery percentage where RoamVibing stops the session.")

        let thermalCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        thermalCheckbox.state = thermalPolicy.isEnabled ? .on : .off
        thermalCheckbox.setAccessibilityLabel("Enable Thermal Safety")
        thermalCheckbox.setAccessibilityHelp("Uses macOS thermal pressure to stop the RoamVibing session at serious or critical pressure. It releases wake blockers so the Mac can cool down and sleep normally, and it does not read raw CPU or GPU temperatures.")

        let instantCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        instantCheckbox.state = instantPolicy.isEnabled ? .on : .off
        instantCheckbox.setAccessibilityLabel("Enable Instant Lock on Activity")
        instantCheckbox.setAccessibilityHelp("Only applies to Closed-Lid Mode. Normal Awake does not use this lock.")

        let instantPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for delay in InstantLock.armingDelays {
            instantPopup.addItem(withTitle: "\(Int(delay)) seconds")
            instantPopup.lastItem?.representedObject = delay
        }
        let selectedDelay = InstantLock.armingDelays.contains(instantPolicy.idleArmingDelay)
            ? instantPolicy.idleArmingDelay
            : InstantActivityLockPolicy.defaultIdleArmingDelay
        instantPopup.selectItem(withTitle: "\(Int(selectedDelay)) seconds")
        instantPopup.isEnabled = instantPolicy.isEnabled
        instantCheckbox.target = self
        instantCheckbox.action = #selector(toggleInstantLockDelayPopup(_:))
        instantCheckbox.tag = 3
        instantPopup.tag = 4
        instantPopup.setAccessibilityLabel("Safety delay")
        instantPopup.setAccessibilityHelp("Choose the Closed-Lid Mode safety delay before activity can trigger an instant lock.")

        let muteCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        muteCheckbox.state = mutePolicy.isEnabled ? .on : .off
        muteCheckbox.setAccessibilityLabel("Enable Mute on Lid Close")
        muteCheckbox.setAccessibilityHelp("Mutes supported active audio outputs when the lid closes during a RoamVibing session.")

        let helperStatusLabel = NSTextField(labelWithString: touchIDHelperStatusTitle)
        helperStatusLabel.setAccessibilityLabel("Touch ID Helper status")
        let helperCheckbox = NSButton(checkboxWithTitle: "Use Touch ID Helper", target: nil, action: nil)
        helperCheckbox.state = shouldUsePrivilegedHelper && helperStatus == .enabled ? .on : .off
        helperCheckbox.isEnabled = helperStatus == .enabled && session.state == .stopped
        helperCheckbox.setAccessibilityLabel("Use Touch ID Helper")
        helperCheckbox.setAccessibilityHelp("Use the installed privileged helper for Closed-Lid Mode approval.")

        let disableBypassButton = NSButton(
            title: "Reset Closed-Lid Bypass",
            target: self,
            action: #selector(disableClosedLidBypassFromSettings(_:))
        )
        disableBypassButton.bezelStyle = .rounded
        disableBypassButton.isEnabled = true
        disableBypassButton.setAccessibilityLabel("Reset Closed-Lid Bypass")
        disableBypassButton.setAccessibilityHelp("Emergency cleanup for turning off the macOS closed-lid sleep bypass.")

        let installHelperButton = NSButton(
            title: "Install Touch ID Helper",
            target: self,
            action: #selector(installPrivilegedHelperFromSettings(_:))
        )
        installHelperButton.bezelStyle = .rounded
        installHelperButton.isEnabled = session.state == .stopped && helperStatus != .enabled
        installHelperButton.setAccessibilityLabel("Install Touch ID Helper")

        let uninstallHelperButton = NSButton(
            title: "Uninstall Touch ID Helper",
            target: self,
            action: #selector(uninstallPrivilegedHelperFromSettings(_:))
        )
        uninstallHelperButton.bezelStyle = .rounded
        uninstallHelperButton.isEnabled = session.state == .stopped && helperStatus != .notRegistered && helperStatus != .notFound
        uninstallHelperButton.setAccessibilityLabel("Uninstall Touch ID Helper")

        guard runSettingsPanel(sections: [
            settingsSection(
                title: "Battery Safety",
                description: "Stops the RoamVibing session below your threshold while on battery so macOS can sleep normally.",
                controls: [
                    batteryCheckbox,
                    settingsRow(title: "Battery threshold", popup: batteryPopup)
                ]
            ),
            settingsSection(
                title: "Thermal Safety",
                description: "Uses macOS thermal pressure to stop the RoamVibing session at serious or critical pressure. RoamVibing releases wake blockers so the Mac can cool down and sleep normally. It does not read raw CPU or GPU temperatures.",
                controls: [
                    thermalCheckbox
                ]
            ),
            settingsSection(
                title: "Instant Lock on Activity",
                description: "Only applies to Closed-Lid Mode. After the safety delay, reopening the lid or using the keyboard or mouse locks the screen and turns RoamVibing off. Normal Awake does not use this lock.",
                controls: [
                    instantCheckbox,
                    settingsRow(title: "Safety delay", popup: instantPopup)
                ]
            ),
            settingsSection(
                title: "Mute on Lid Close",
                description: "Mutes supported active audio outputs when the lid closes during a RoamVibing session.",
                controls: [
                    muteCheckbox
                ]
            ),
            settingsSection(
                title: "Emergency Reset",
                description: "Emergency cleanup. Turns off the macOS closed-lid sleep bypass if it was left enabled outside a RoamVibing session.",
                controls: [
                    disableBypassButton
                ]
            ),
            settingsSection(
                title: "Touch ID Helper",
                description: "Use the installed privileged helper so Closed-Lid Mode can ask for Touch ID or your Mac password.",
                controls: [
                    helperStatusLabel,
                    helperCheckbox,
                    installHelperButton,
                    uninstallHelperButton
                ]
            )
        ]) == .OK else {
            return
        }

        let threshold = batteryPopup.selectedItem?.representedObject as? Int
            ?? LowBatteryPolicy.defaultThresholdPercentage
        batterySafetySettings.policy = LowBatteryPolicy(
            isEnabled: batteryCheckbox.state == .on,
            thresholdPercentage: threshold
        )
        lowBatteryGuard.policy = batterySafetySettings.policy

        thermalSafetySettings.policy = ThermalSafetyPolicy(isEnabled: thermalCheckbox.state == .on)
        thermalSafetyGuard.policy = thermalSafetySettings.policy

        let delay = instantPopup.selectedItem?.representedObject as? TimeInterval
            ?? InstantActivityLockPolicy.defaultIdleArmingDelay
        instantActivityLockSettings.policy = InstantActivityLockPolicy(
            isEnabled: instantCheckbox.state == .on,
            idleArmingDelay: delay
        )
        instantActivityLockGuard.policy = instantActivityLockSettings.policy
        instantActivityLockGuard.resetForSessionStart()

        muteOnLidCloseSettings.policy = MuteOnLidClosePolicy(
            isEnabled: muteCheckbox.state == .on
        )
        muteOnLidCloseGuard.policy = muteOnLidCloseSettings.policy

        if helperCheckbox.isEnabled {
            UserDefaults.standard.set(helperCheckbox.state == .on, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)
        }
        rebuildRuntimeObjects()
        evaluateBatterySafety()
        evaluateThermalSafety()
        rebuildMenu()
    }

    @objc private func disableClosedLidBypassFromSettings(_ sender: NSButton) {
        sender.window?.close()
        NSApp.abortModal()
        forceDisableClosedLidBypass()
    }

    @objc private func installPrivilegedHelperFromSettings(_ sender: NSButton) {
        sender.window?.close()
        NSApp.abortModal()
        installPrivilegedHelper()
    }

    @objc private func uninstallPrivilegedHelperFromSettings(_ sender: NSButton) {
        sender.window?.close()
        NSApp.abortModal()
        uninstallPrivilegedHelper()
    }

    @objc private func toggleInstantLockDelayPopup(_ sender: NSButton) {
        guard let popup = sender.window?.contentView?.viewWithTag(4) as? NSPopUpButton else {
            return
        }
        popup.isEnabled = sender.state == .on
    }

    @objc private func toggleBatteryThresholdPopup(_ sender: NSButton) {
        guard let popup = sender.window?.contentView?.viewWithTag(2) as? NSPopUpButton else {
            return
        }
        popup.isEnabled = sender.state == .on
    }

    @objc private func showSafetyNotes() {
        showAlert(
            title: "Closed-Lid Mode Safety",
            message: """
            Closed-lid mode changes a privileged macOS power setting so sleep is disabled even when the lid is closed.

            Use it only on a stable, ventilated surface. Do not put the Mac in a bag while this is enabled. Turn it off before traveling or leaving the machine unattended on battery power.

            Thermal Safety uses macOS thermal pressure and stops the RoamVibing session when the system reports serious or critical thermal pressure. It releases wake blockers so the Mac can cool down and sleep normally. It does not read raw CPU or GPU temperatures.

            Instant Lock on Activity polls macOS idle-time counters only. It does not read keystrokes, capture mouse events, or request Accessibility/Input Monitoring permissions.
            """,
            style: .warning
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func start(mode: SessionMode) {
        guard activePowerOperation == nil, activeHelperOperation == nil else {
            rebuildMenu()
            return
        }

        if batterySafetyShouldBlockStartingSession() || thermalSafetyShouldBlockStartingSession() {
            return
        }

        rebuildRuntimeObjects()

        let needsPowerOperation = mode == .closedLid || session.state == .running(.closedLid)
        if needsPowerOperation {
            let operation: PowerOperation = mode == .closedLid ? .startingClosedLid : .switchingToNormalAwake
            beginPowerOperation(operation, errorTitle: "Could Not Start \(Brand.appName)") {
                try self.session.start(mode: mode)
            } didFinish: {
                self.instantActivityLockGuard.resetForSessionStart()
                self.muteOnLidCloseGuard.reset()
                self.evaluateBatterySafety()
                self.evaluateThermalSafety()
            }
            return
        }

        do {
            try session.start(mode: mode)
            instantActivityLockGuard.resetForSessionStart()
            muteOnLidCloseGuard.reset()
        } catch {
            presentError(error, title: "Could Not Start \(Brand.appName)")
        }

        rebuildMenu()
        evaluateBatterySafety()
        evaluateThermalSafety()
    }

    private func beginPowerOperation(
        _ operation: PowerOperation,
        errorTitle: String,
        work: @escaping () throws -> Void,
        didFinish: (() -> Void)? = nil
    ) {
        guard activePowerOperation == nil, activeHelperOperation == nil else {
            rebuildMenu()
            return
        }

        activePowerOperation = operation
        rebuildMenu()

        powerOperationQueue.async { [weak self] in
            guard let self else {
                return
            }

            let result = Result<Void, Error> {
                try work()
            }

            DispatchQueue.main.async {
                self.activePowerOperation = nil

                switch result {
                case .success:
                    didFinish?()
                case let .failure(error):
                    self.rebuildMenu()
                    self.presentError(error, title: errorTitle)
                    return
                }

                self.rebuildMenu()
            }
        }
    }

    private func beginHelperOperation(
        _ operation: HelperOperation,
        errorTitle: String,
        work: @escaping () throws -> Void,
        didFinish: (() -> Void)? = nil
    ) {
        guard activePowerOperation == nil, activeHelperOperation == nil else {
            rebuildMenu()
            return
        }

        activeHelperOperation = operation
        rebuildMenu()

        helperOperationQueue.async { [weak self] in
            guard let self else {
                return
            }

            let result = Result<Void, Error> {
                try work()
            }

            DispatchQueue.main.async {
                self.activeHelperOperation = nil

                switch result {
                case .success:
                    didFinish?()
                case let .failure(error):
                    self.rebuildMenu()
                    self.presentError(error, title: errorTitle)
                    return
                }

                self.rebuildMenu()
            }
        }
    }

    private func startBatterySafetyTimer() {
        batterySafetyTimer?.invalidate()
        batterySafetyTimer = Timer.scheduledTimer(
            withTimeInterval: BatterySafety.checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.evaluateBatterySafety()
        }
        batterySafetyTimer?.tolerance = 5
    }

    private func startThermalSafetyTimer() {
        thermalSafetyTimer?.invalidate()
        thermalSafetyTimer = Timer.scheduledTimer(
            withTimeInterval: ThermalSafety.checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.evaluateThermalSafety()
        }
        thermalSafetyTimer?.tolerance = 5
    }

    private func startInstantActivityLockTimer() {
        instantActivityLockTimer?.invalidate()
        instantActivityLockTimer = Timer.scheduledTimer(
            withTimeInterval: InstantLock.checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.evaluateMuteOnLidClose()
            self?.evaluateInstantActivityLock()
        }
        instantActivityLockTimer?.tolerance = 0.05
    }

    private func evaluateBatterySafety() {
        guard activePowerOperation == nil else {
            return
        }

        lowBatteryGuard.policy = batterySafetySettings.policy

        do {
            switch try lowBatteryGuard.evaluate() {
            case .noAction:
                return
            case let .stoppedSession(percentage, threshold):
                rebuildMenu()
                showLowBatteryStoppedAlert(percentage: percentage, threshold: threshold)
            }
        } catch {
            presentError(error, title: "Could Not Apply Battery Safety")
        }
    }

    private func evaluateThermalSafety() {
        guard activePowerOperation == nil else {
            return
        }

        thermalSafetyGuard.policy = thermalSafetySettings.policy

        do {
            switch try thermalSafetyGuard.evaluate() {
            case .noAction:
                hasShownThermalSafetyError = false
                return
            case let .stoppedSession(state):
                hasShownThermalSafetyError = false
                rebuildMenu()
                showThermalSafetyStoppedAlert(state: state)
            }
        } catch {
            if hasShownThermalSafetyError {
                return
            }
            hasShownThermalSafetyError = true
            presentError(error, title: "Could Not Apply Thermal Safety")
        }
    }

    private func evaluateInstantActivityLock() {
        guard activePowerOperation == nil else {
            return
        }

        instantActivityLockGuard.policy = instantActivityLockSettings.policy

        do {
            switch try instantActivityLockGuard.evaluate() {
            case .noAction, .armed:
                return
            case .locked:
                rebuildMenu()
            }
        } catch {
            instantActivityLockGuard.reset()
            presentError(error, title: "Could Not Lock Screen")
        }
    }

    private func evaluateMuteOnLidClose() {
        guard activePowerOperation == nil, session.state != .stopped else {
            muteOnLidCloseGuard.reset()
            return
        }

        muteOnLidCloseGuard.policy = muteOnLidCloseSettings.policy

        do {
            _ = try muteOnLidCloseGuard.evaluate()
        } catch {
            NSLog("%@: Mute on Lid Close failed: %@", Brand.appName, String(describing: error))
        }
    }

    private func batterySafetyShouldBlockStartingSession() -> Bool {
        let policy = batterySafetySettings.policy
        guard policy.isEnabled,
              let reading = batteryReader.currentBatteryReading(),
              reading.isRunningOnBattery,
              reading.percentage <= policy.thresholdPercentage
        else {
            return false
        }

        showAlert(
            title: "Battery Safety Blocked RoamVibing Session",
            message: "Battery is at \(reading.percentage)%, at or below your \(policy.thresholdPercentage)% threshold. Connect power, lower the threshold, or turn Battery Safety off.",
            style: .warning
        )
        return true
    }

    private func thermalSafetyShouldBlockStartingSession() -> Bool {
        let policy = thermalSafetySettings.policy
        guard policy.isEnabled else {
            return false
        }

        let state = thermalStateReader.currentThermalState()
        guard state.shouldStopRoamVibingSession else {
            return false
        }

        showAlert(
            title: "Thermal Safety Blocked RoamVibing Session",
            message: "macOS reports \(thermalStateDescription(state)) thermal pressure. Thermal Safety uses macOS thermal pressure, not raw CPU/GPU temperatures. Let the Mac cool down, improve ventilation, or turn Thermal Safety off.",
            style: .warning
        )
        return true
    }

    private func showLowBatteryStoppedAlert(percentage: Int, threshold: Int) {
        guard !isShowingLowBatteryAlert else {
            return
        }

        isShowingLowBatteryAlert = true
        showAlert(
            title: "Battery Safety Stopped \(Brand.appName)",
            message: "Battery is at \(percentage)%, at or below your \(threshold)% threshold. \(Brand.appName) stopped the RoamVibing session so macOS can sleep normally.",
            style: .warning
        )
        isShowingLowBatteryAlert = false
    }

    private func showThermalSafetyStoppedAlert(state: ThermalPressureState) {
        guard !isShowingThermalSafetyAlert else {
            return
        }

        isShowingThermalSafetyAlert = true
        showAlert(
            title: "Thermal Safety Stopped \(Brand.appName)",
            message: "macOS reports \(thermalStateDescription(state)) thermal pressure. \(Brand.appName) stopped the RoamVibing session and released wake blockers so the Mac can cool down and sleep normally. Thermal Safety does not read raw CPU or GPU temperatures.",
            style: .warning
        )
        isShowingThermalSafetyAlert = false
    }

    private func thermalStateDescription(_ state: ThermalPressureState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        }
    }

    private func settingsSection(title: String, description: String, controls: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.preferredMaxLayoutWidth = SettingsDialog.contentWidth
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = SettingsDialog.verticalSpacing
        section.translatesAutoresizingMaskIntoConstraints = false
        section.addArrangedSubview(titleLabel)
        section.addArrangedSubview(descriptionLabel)

        controls.forEach { control in
            control.translatesAutoresizingMaskIntoConstraints = false
            section.addArrangedSubview(control)
            control.widthAnchor.constraint(equalToConstant: SettingsDialog.contentWidth).isActive = true
        }

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalToConstant: SettingsDialog.contentWidth),
            descriptionLabel.widthAnchor.constraint(equalToConstant: SettingsDialog.contentWidth)
        ])

        return section
    }

    private func settingsRow(title: String, popup: NSPopUpButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = SettingsDialog.rowGap
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(label)
        row.addArrangedSubview(popup)

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: SettingsDialog.rowLabelWidth),
            popup.heightAnchor.constraint(equalToConstant: SettingsDialog.controlHeight)
        ])

        return row
    }

    private func runSettingsPanel(sections: [NSView]) -> NSApplication.ModalResponse {
        let panel = NSPanel(contentRect: NSRect(
            x: 0,
            y: 0,
            width: SettingsDialog.windowWidth,
            height: SettingsDialog.windowHeight
        ), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Settings"
        panel.isReleasedWhenClosed = false

        let rootView = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: SettingsDialog.windowWidth,
            height: SettingsDialog.windowHeight
        ))
        panel.contentView = rootView

        let logoView = NSImageView()
        logoView.image = NSImage(named: "RoamVibingIcon") ?? NSApp.applicationIconImage
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.setAccessibilityLabel("RoamVibing logo")
        logoView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsDialog.sectionSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: SettingsDialog.panelPadding,
            left: SettingsDialog.panelPadding,
            bottom: SettingsDialog.panelPadding,
            right: SettingsDialog.panelPadding
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        documentView.addSubview(stack)
        scrollView.documentView = documentView

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let controller = SettingsPanelController()
        controller.panel = panel
        saveButton.target = controller
        saveButton.action = #selector(SettingsPanelController.save(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SettingsPanelController.cancel(_:))

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = SettingsDialog.rowGap
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(logoView)
        rootView.addSubview(scrollView)
        rootView.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            logoView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: SettingsDialog.panelPadding),
            logoView.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 72),
            logoView.heightAnchor.constraint(equalToConstant: 72),
            scrollView.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: SettingsDialog.verticalSpacing),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -SettingsDialog.verticalSpacing),
            buttonRow.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -SettingsDialog.panelPadding),
            buttonRow.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -SettingsDialog.panelPadding),
            cancelButton.widthAnchor.constraint(equalToConstant: 110),
            saveButton.widthAnchor.constraint(equalToConstant: 110),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])

        panel.delegate = controller
        panel.center()
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        panel.makeKeyAndOrderFront(nil)

        let response = withExtendedLifetime(controller) {
            NSApp.runModal(for: panel)
        }
        panel.orderOut(nil)
        return response
    }

    private func confirmClosedLidMode() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Start Closed-Lid Mode?"
        alert.informativeText = """
        This may ask for administrator approval or use the installed privileged helper to run:
        /usr/bin/pmset -a disablesleep 1

        Normal Awake mode is enough when the lid stays open. Closed-Lid Mode is for downloads, scripts, or audio with the MacBook closed and no external display attached.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Start Closed-Lid Mode")
        alert.addButton(withTitle: "Cancel")
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ error: Error, title: String) {
        showAlert(
            title: title,
            message: (error as? LocalizedError)?.errorDescription ?? String(describing: error),
            style: .critical
        )
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        alert.runModal()
    }
}
