import Foundation

final class StartupLockPreferences {
    private enum Key {
        static let restoreOnLaunch = "restoreLockOnLaunch"
        static let lockedInputSourceID = "savedLockedInputSourceID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isRestoreOnLaunchEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.restoreOnLaunch) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.restoreOnLaunch)
        }
        set {
            defaults.set(newValue, forKey: Key.restoreOnLaunch)
            if !newValue {
                clearSavedLockedInputSource()
            }
        }
    }

    var restoreCandidateInputSourceID: String? {
        guard isRestoreOnLaunchEnabled else { return nil }
        return defaults.string(forKey: Key.lockedInputSourceID)
    }

    func saveLockedInputSourceID(_ inputSourceID: String) {
        guard isRestoreOnLaunchEnabled else { return }
        defaults.set(inputSourceID, forKey: Key.lockedInputSourceID)
    }

    func clearSavedLockedInputSource() {
        defaults.removeObject(forKey: Key.lockedInputSourceID)
    }
}
