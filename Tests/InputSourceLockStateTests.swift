import Foundation
import XCTest

@testable import lockinput

final class InputSourceLockStateTests: XCTestCase {
    func testLockState() {
        var state = InputSourceLockState()

        XCTAssertFalse(state.isLocked)
        XCTAssertFalse(state.matchesLockedInputSourceID("com.apple.keylayout.ABC"))

        state.lock(inputSourceID: "com.apple.keylayout.ABC")
        XCTAssertTrue(state.isLocked)
        XCTAssertTrue(state.matchesLockedInputSourceID("com.apple.keylayout.ABC"))
        XCTAssertFalse(state.matchesLockedInputSourceID("com.apple.inputmethod.SCIM.ITABC"))

        state.unlock()
        XCTAssertFalse(state.isLocked)
        XCTAssertFalse(state.matchesLockedInputSourceID("com.apple.keylayout.ABC"))
    }

    func testStartupLockPreferenceDefaultsToEnabledAndPersistsLockedSource() {
        let defaults = makeDefaults()
        let preferences = StartupLockPreferences(defaults: defaults)

        XCTAssertTrue(preferences.isRestoreOnLaunchEnabled)

        preferences.saveLockedInputSourceID("com.apple.keylayout.ABC")

        XCTAssertEqual(preferences.restoreCandidateInputSourceID, "com.apple.keylayout.ABC")
    }

    func testDisablingStartupLockPreferenceClearsSavedSource() {
        let defaults = makeDefaults()
        let preferences = StartupLockPreferences(defaults: defaults)
        preferences.saveLockedInputSourceID("com.apple.inputmethod.SCIM.ITABC")

        preferences.isRestoreOnLaunchEnabled = false
        preferences.saveLockedInputSourceID("com.apple.keylayout.ABC")

        XCTAssertNil(preferences.restoreCandidateInputSourceID)
    }

    func testClearingStartupLockPreferenceRemovesSavedSource() {
        let defaults = makeDefaults()
        let preferences = StartupLockPreferences(defaults: defaults)
        preferences.saveLockedInputSourceID("com.apple.keylayout.ABC")

        preferences.clearSavedLockedInputSource()

        XCTAssertNil(preferences.restoreCandidateInputSourceID)
    }

    func testStartupLockRestoreMarksSuccessfulSelectionAsRestored() {
        var retryState = StartupLockRestoreRetryState()

        XCTAssertEqual(
            retryState.action(afterInputSourceSelectionSucceeded: true),
            .restored
        )
    }

    func testStartupLockRestoreStopsAfterFifteenFailedSelections() {
        var retryState = StartupLockRestoreRetryState()

        for _ in 0..<15 {
            XCTAssertEqual(
                retryState.action(afterInputSourceSelectionSucceeded: false),
                .retry
            )
        }

        XCTAssertEqual(
            retryState.action(afterInputSourceSelectionSucceeded: false),
            .unavailable
        )
    }

    func testTemporaryASCIIInputIsRejectedWhenCapsLockIsOff() {
        XCTAssertFalse(
            TemporaryInputSourcePolicy.shouldAllowTemporaryASCIILayout(
                currentIsKeyboardLayout: true,
                currentIsASCIICapable: true,
                lockedIsKeyboardLayout: false,
                isCapsLockEnabled: false
            )
        )
    }

    func testTemporaryASCIIInputIsAllowedOnlyWhileCapsLockIsOn() {
        XCTAssertTrue(
            TemporaryInputSourcePolicy.shouldAllowTemporaryASCIILayout(
                currentIsKeyboardLayout: true,
                currentIsASCIICapable: true,
                lockedIsKeyboardLayout: false,
                isCapsLockEnabled: true
            )
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "InputSourceLockStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
