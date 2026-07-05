import XCTest

final class InstantActivityLockAppWiringTests: XCTestCase {
    func testAppDelegateWiresInstantActivityLockMenuAndTimer() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("Instant Lock on Activity"))
        XCTAssertTrue(source.contains("@objc private func showSettings()"))
        XCTAssertTrue(source.contains("startInstantActivityLockTimer"))
        XCTAssertTrue(source.contains("evaluateInstantActivityLock"))
        XCTAssertTrue(source.contains("InstantActivityLockGuard"))
        XCTAssertTrue(source.contains("MacLidStateReader"))
    }

    func testLidStateReaderPollsClamshellState() throws {
        let source = try readText("Sources/LidAwake/MacLidStateReader.swift")

        XCTAssertTrue(source.contains("AppleClamshellState"))
        XCTAssertTrue(source.contains("currentLidState"))
        XCTAssertFalse(source.contains("CGEventTapCreate"))
        XCTAssertFalse(source.contains("AXIsProcessTrusted"))
    }

    func testInputActivityReaderPollsAggregateInputIdleTimeWithoutEventTap() throws {
        let source = try readText("Sources/LidAwake/MacInputActivityReader.swift")

        XCTAssertTrue(source.contains("CGEventSource.secondsSinceLastEventType"))
        XCTAssertTrue(source.contains("secondsSinceLastKeyboardOrMouseInput"))
        XCTAssertFalse(source.contains("CGEventTapCreate"))
        XCTAssertFalse(source.contains("AXIsProcessTrusted"))
    }

    func testInstantActivityLockSettingsDefaultToEnabled() throws {
        let source = try readText("Sources/LidAwake/InstantActivityLockSettingsStore.swift")

        XCTAssertTrue(source.contains("InstantActivityLock.isEnabled"))
        XCTAssertTrue(source.contains("InstantActivityLock.idleArmingDelay"))
        XCTAssertTrue(source.contains("isEnabled = true"))
        XCTAssertTrue(source.contains("InstantActivityLockPolicy.defaultIdleArmingDelay"))
    }

    func testMuteOnLidCloseSettingsDefaultToEnabled() throws {
        let source = try readText("Sources/LidAwake/MuteOnLidCloseSettingsStore.swift")

        XCTAssertTrue(source.contains("MuteOnLidClose.isEnabled"))
        XCTAssertTrue(source.contains("MuteOnLidClosePolicy.default.isEnabled"))
        XCTAssertTrue(source.contains("isEnabled = MuteOnLidClosePolicy.default.isEnabled"))
    }

    func testMacAudioOutputMuterUsesCoreAudioWithoutShellOrPermissions() throws {
        let source = try readText("Sources/LidAwake/MacAudioOutputMuter.swift")
        let package = try readText("Package.swift")

        XCTAssertTrue(source.contains("import CoreAudio"))
        XCTAssertTrue(source.contains("final class MacAudioOutputMuter: AudioOutputMuting"))
        XCTAssertTrue(source.contains("kAudioHardwarePropertyDefaultOutputDevice"))
        XCTAssertTrue(source.contains("kAudioHardwarePropertyDefaultSystemOutputDevice"))
        XCTAssertTrue(source.contains("kAudioDevicePropertyDeviceIsRunningSomewhere"))
        XCTAssertTrue(source.contains("scope: kAudioObjectPropertyScopeGlobal"))
        XCTAssertTrue(source.contains("kAudioDevicePropertyStreams"))
        XCTAssertTrue(source.contains("scope: kAudioDevicePropertyScopeOutput"))
        XCTAssertTrue(source.contains("kAudioDevicePropertyMute"))
        XCTAssertTrue(source.contains("noMutableOutputDevice"))
        XCTAssertTrue(package.contains(".linkedFramework(\"CoreAudio\")"))
        XCTAssertFalse(source.contains("/usr/bin/osascript"))
        XCTAssertFalse(source.contains("CGEventTapCreate"))
        XCTAssertFalse(source.contains("AXIsProcessTrusted"))
    }

    func testAppDelegateWiresMuteOnLidCloseIntoLidPollingLoop() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")
        let timerRange = try XCTUnwrap(source.range(of: "private func startInstantActivityLockTimer()"))
        let timerSource = source[timerRange.lowerBound...]
        let muteEvaluationRange = try XCTUnwrap(timerSource.range(of: "self?.evaluateMuteOnLidClose()"))
        let instantLockEvaluationRange = try XCTUnwrap(timerSource.range(of: "self?.evaluateInstantActivityLock()"))

        XCTAssertTrue(source.contains("private let muteOnLidCloseSettings = MuteOnLidCloseSettingsStore()"))
        XCTAssertTrue(source.contains("private lazy var muteOnLidCloseGuard = makeMuteOnLidCloseGuard()"))
        XCTAssertTrue(source.contains("private func makeMuteOnLidCloseGuard() -> MuteOnLidCloseGuard"))
        XCTAssertTrue(source.contains("lidStateReader: lidStateReader"))
        XCTAssertTrue(source.contains("audioOutputMuter: MacAudioOutputMuter()"))
        XCTAssertLessThan(muteEvaluationRange.lowerBound, instantLockEvaluationRange.lowerBound)
        XCTAssertTrue(source.contains("muteOnLidCloseGuard.policy = muteOnLidCloseSettings.policy"))
        XCTAssertTrue(source.contains("guard activePowerOperation == nil, session.state != .stopped else"))
        XCTAssertTrue(source.contains("muteOnLidCloseGuard.reset()"))
        XCTAssertTrue(source.contains("Mute on Lid Close failed"))

        let muteFunctionRange = try XCTUnwrap(source.range(of: "private func evaluateMuteOnLidClose()"))
        let nextFunctionRange = try XCTUnwrap(source[muteFunctionRange.upperBound...].range(of: "private func batterySafetyShouldBlockStartingSession()"))
        let muteFunctionSource = source[muteFunctionRange.lowerBound..<nextFunctionRange.lowerBound]
        XCTAssertFalse(muteFunctionSource.contains("presentError"))
    }

    func testInstantLockDialogExplainsDelayTriggerAndOneShotShutdown() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("Only applies to Closed-Lid Mode. After the safety delay, reopening the lid or using the keyboard or mouse locks the screen and turns RoamVibing off. Normal Awake does not use this lock."))
        XCTAssertTrue(source.contains("Safety delay"))
        XCTAssertFalse(source.contains("The idle delay gives you time to start the RoamVibing session and close the lid without immediately locking the screen."))
        XCTAssertFalse(source.contains("After that delay, reopening the lid or using the keyboard or mouse locks the screen and turns \\(Brand.appName) off."))
        XCTAssertFalse(source.contains("This is a one-time safety lock for awake sessions."))
        XCTAssertFalse(source.contains("arms after the selected idle period"))
        XCTAssertFalse(source.contains("Arm after idle"))
    }

    func testReadmeDocumentsInstantLockFeature() throws {
        let readme = try readText("README.md")

        XCTAssertTrue(readme.contains("Instant Lock on Activity"))
        XCTAssertTrue(readme.contains("applies only to Closed-Lid Mode"))
        XCTAssertTrue(readme.contains("Normal Awake does not use this lock"))
        XCTAssertTrue(readme.contains("keyboard or mouse input"))
        XCTAssertTrue(readme.contains("lid opens"))
    }

    func testReadmeDocumentsSettingsAndMuteOnLidClose() throws {
        let readme = try readText("README.md")

        XCTAssertTrue(readme.contains("Settings"))
        XCTAssertTrue(readme.contains("Mute on Lid Close"))
        XCTAssertTrue(readme.contains("mutes active audio output devices"))
        XCTAssertTrue(readme.contains("default is on"))
    }

    func testReadmeDocumentsThermalSafety() throws {
        let readme = try readText("README.md")

        XCTAssertTrue(readme.contains("Thermal Safety"))
        XCTAssertTrue(readme.contains("serious or critical thermal pressure"))
        XCTAssertTrue(readme.contains("uses macOS thermal pressure instead of raw temperature"))
        XCTAssertTrue(readme.contains("`Thermal Safety`: stops the RoamVibing session when macOS reports serious or critical thermal pressure. The default is on."))
        XCTAssertTrue(readme.contains("releases wake blockers"))
    }

    private func readText(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
