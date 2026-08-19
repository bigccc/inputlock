struct TemporaryInputSourcePolicy {
    static func shouldAllowTemporaryASCIILayout(
        currentIsKeyboardLayout: Bool,
        currentIsASCIICapable: Bool,
        lockedIsKeyboardLayout: Bool,
        isCapsLockEnabled: Bool
    ) -> Bool {
        currentIsKeyboardLayout
            && currentIsASCIICapable
            && !lockedIsKeyboardLayout
            && isCapsLockEnabled
    }
}
