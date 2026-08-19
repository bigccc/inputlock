enum StartupLockRestoreAction: Equatable {
    case restored
    case retry
    case unavailable
}

struct StartupLockRestoreRetryState {
    private var retriesRemaining: Int = 15

    mutating func action(afterInputSourceSelectionSucceeded succeeded: Bool) -> StartupLockRestoreAction {
        guard !succeeded else { return .restored }
        guard retriesRemaining > 0 else { return .unavailable }
        retriesRemaining -= 1
        return .retry
    }
}
