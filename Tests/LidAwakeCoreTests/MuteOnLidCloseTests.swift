import XCTest
@testable import LidAwakeCore

final class MuteOnLidCloseTests: XCTestCase {
    func testDefaultPolicyIsEnabled() {
        XCTAssertEqual(MuteOnLidClosePolicy.default, MuteOnLidClosePolicy(isEnabled: true))
        XCTAssertTrue(MuteOnLidClosePolicy.default.isEnabled)
    }

    func testMutesOnceWhenLidTransitionsFromOpenToClosed() throws {
        let lid = RecordingMuteLidStateReader(state: .open)
        let muter = RecordingAudioOutputMuter()
        let guardrail = MuteOnLidCloseGuard(
            lidStateReader: lid,
            audioOutputMuter: muter,
            policy: .default
        )

        XCTAssertEqual(try guardrail.evaluate(), .noAction)

        lid.state = .closed
        XCTAssertEqual(try guardrail.evaluate(), .muted)
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        XCTAssertEqual(muter.muteCount, 1)
    }

    func testOpenLidResetsSoNextCloseMutesAgain() throws {
        let lid = RecordingMuteLidStateReader(state: .closed)
        let muter = RecordingAudioOutputMuter()
        let guardrail = MuteOnLidCloseGuard(
            lidStateReader: lid,
            audioOutputMuter: muter,
            policy: .default
        )

        XCTAssertEqual(try guardrail.evaluate(), .muted)
        XCTAssertEqual(try guardrail.evaluate(), .noAction)

        lid.state = .open
        XCTAssertEqual(try guardrail.evaluate(), .noAction)

        lid.state = .closed
        XCTAssertEqual(try guardrail.evaluate(), .muted)
        XCTAssertEqual(muter.muteCount, 2)
    }

    func testDisabledPolicyNeverMutesAndResetsCurrentClosure() throws {
        let lid = RecordingMuteLidStateReader(state: .closed)
        let muter = RecordingAudioOutputMuter()
        let guardrail = MuteOnLidCloseGuard(
            lidStateReader: lid,
            audioOutputMuter: muter,
            policy: .default
        )

        XCTAssertEqual(try guardrail.evaluate(), .muted)
        guardrail.policy = MuteOnLidClosePolicy(isEnabled: false)
        XCTAssertEqual(try guardrail.evaluate(), .noAction)

        lid.state = .open
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        lid.state = .closed
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        XCTAssertEqual(muter.muteCount, 1)

        guardrail.policy = .default
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        XCTAssertEqual(muter.muteCount, 1)

        lid.state = .open
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        lid.state = .closed
        XCTAssertEqual(try guardrail.evaluate(), .muted)
        XCTAssertEqual(muter.muteCount, 2)
    }

    func testReEnablingAfterUnevaluatedCloseBaselinesWithoutMuting() throws {
        let lid = RecordingMuteLidStateReader(state: .open)
        let muter = RecordingAudioOutputMuter()
        let guardrail = MuteOnLidCloseGuard(
            lidStateReader: lid,
            audioOutputMuter: muter,
            policy: .default
        )

        XCTAssertEqual(try guardrail.evaluate(), .noAction)

        guardrail.policy = MuteOnLidClosePolicy(isEnabled: false)
        lid.state = .closed
        guardrail.policy = .default

        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        XCTAssertEqual(muter.muteCount, 0)

        lid.state = .open
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        lid.state = .closed
        XCTAssertEqual(try guardrail.evaluate(), .muted)
        XCTAssertEqual(muter.muteCount, 1)
    }

    func testUnknownLidStateDoesNotMute() throws {
        let lid = RecordingMuteLidStateReader(state: .unknown)
        let muter = RecordingAudioOutputMuter()
        let guardrail = MuteOnLidCloseGuard(
            lidStateReader: lid,
            audioOutputMuter: muter,
            policy: .default
        )

        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        XCTAssertEqual(muter.muteCount, 0)
    }

    func testMuteFailureIsThrown() {
        let lid = RecordingMuteLidStateReader(state: .closed)
        let muter = RecordingAudioOutputMuter(errorToThrow: RecordingAudioOutputMuterError.expected)
        let guardrail = MuteOnLidCloseGuard(
            lidStateReader: lid,
            audioOutputMuter: muter,
            policy: .default
        )

        XCTAssertThrowsError(try guardrail.evaluate()) { error in
            XCTAssertEqual(error as? RecordingAudioOutputMuterError, .expected)
        }
        XCTAssertEqual(muter.muteCount, 1)
    }

    func testMuteFailureIsReportedOncePerClosure() {
        let lid = RecordingMuteLidStateReader(state: .closed)
        let muter = RecordingAudioOutputMuter(errorToThrow: RecordingAudioOutputMuterError.expected)
        let guardrail = MuteOnLidCloseGuard(
            lidStateReader: lid,
            audioOutputMuter: muter,
            policy: .default
        )

        XCTAssertThrowsError(try guardrail.evaluate())
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        XCTAssertEqual(muter.muteCount, 1)

        lid.state = .open
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        lid.state = .closed
        XCTAssertThrowsError(try guardrail.evaluate())
        XCTAssertEqual(muter.muteCount, 2)
    }
}

private final class RecordingMuteLidStateReader: LidStateProviding {
    var state: LidState

    init(state: LidState) {
        self.state = state
    }

    func currentLidState() -> LidState {
        state
    }
}

private final class RecordingAudioOutputMuter: AudioOutputMuting {
    private(set) var muteCount = 0
    private let errorToThrow: Error?

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func muteActiveOutputDevices() throws {
        muteCount += 1

        if let errorToThrow {
            throw errorToThrow
        }
    }
}

private enum RecordingAudioOutputMuterError: Error {
    case expected
}
