//
//  InputMethodManager.swift
//  lockinput
//
//  Created by dave on 2025/12/19.
//

import AppKit
import Carbon
import Combine

class InputMethodManager: ObservableObject {
    static let shared = InputMethodManager()

    @Published var isLocked = false
    @Published var lockedInputSource: TISInputSource?
    @Published var lockedInputSourceID: String?
    @Published var currentInputSourceName: String = ""
    @Published var availableInputSources: [TISInputSource] = []
    @Published var isRestoreOnLaunchEnabled: Bool
    @Published var didFailStartupLockRestore = false

    private var lockState = InputSourceLockState()
    private let startupLockPreferences: StartupLockPreferences
    private var notificationObservers: [NSObjectProtocol] = []
    private var enforcementTimer: Timer?
    private var startupRestoreTimer: Timer?
    private var startupRestoreRetryState = StartupLockRestoreRetryState()
    private var isEnforcingLockedSource = false

    init(startupLockPreferences: StartupLockPreferences = StartupLockPreferences()) {
        self.startupLockPreferences = startupLockPreferences
        self.isRestoreOnLaunchEnabled = startupLockPreferences.isRestoreOnLaunchEnabled
        loadAvailableInputSources()
        updateCurrentInputSourceName()
        setupInputSourceChangeObservers()
        restoreStartupLockIfNeeded()
    }

    deinit {
        for observer in notificationObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        enforcementTimer?.invalidate()
        startupRestoreTimer?.invalidate()
    }

    func loadAvailableInputSources() {
        let conditions = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue as Any
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        availableInputSources = sources.filter { source in
            if let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                return Unmanaged<CFBoolean>.fromOpaque(enabled).takeUnretainedValue() == kCFBooleanTrue
            }
            return false
        }
    }

    func getInputSourceName(_ source: TISInputSource) -> String {
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
        return "Unknown"
    }

    func getInputSourceID(_ source: TISInputSource) -> String {
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        }
        return ""
    }

    func getInputSourceType(_ source: TISInputSource) -> String {
        if let typePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) {
            return Unmanaged<CFString>.fromOpaque(typePtr).takeUnretainedValue() as String
        }
        return ""
    }

    func isASCIICapableInputSource(_ source: TISInputSource) -> Bool {
        guard let capablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else {
            return false
        }
        return Unmanaged<CFBoolean>.fromOpaque(capablePtr).takeUnretainedValue() == kCFBooleanTrue
    }

    func isKeyboardLayout(_ source: TISInputSource) -> Bool {
        getInputSourceType(source) == (kTISTypeKeyboardLayout as String)
    }

    func getCurrentInputSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    func updateCurrentInputSourceName() {
        if let current = getCurrentInputSource() {
            currentInputSourceName = getInputSourceName(current)
        } else {
            currentInputSourceName = "Unknown"
        }
    }

    @discardableResult
    func selectInputSource(_ source: TISInputSource) -> Bool {
        let result = TISSelectInputSource(source)
        updateCurrentInputSourceName()
        return result == noErr
    }

    func lockCurrentInputSource() {
        guard let current = getCurrentInputSource() else { return }
        lock(source: current)
        updateCurrentInputSourceName()
        enforceLockedInputSource()
    }

    func lockInputSource(_ source: TISInputSource) {
        selectInputSource(source)
        lock(source: source)
        updateCurrentInputSourceName()
        enforceLockedInputSource()
    }

    func unlock() {
        lockState.unlock()
        startupLockPreferences.clearSavedLockedInputSource()
        didFailStartupLockRestore = false
        stopStartupRestoreTimer()
        syncPublishedLockState()
        stopEnforcementTimer()
    }

    func setRestoreOnLaunchEnabled(_ enabled: Bool) {
        startupLockPreferences.isRestoreOnLaunchEnabled = enabled
        isRestoreOnLaunchEnabled = enabled
        if !enabled {
            didFailStartupLockRestore = false
            stopStartupRestoreTimer()
        }
    }

    func toggle() {
        if isLocked {
            unlock()
        } else {
            lockCurrentInputSource()
        }
    }

    private func setupInputSourceChangeObservers() {
        let distributedCenter = DistributedNotificationCenter.default()
        notificationObservers.append(distributedCenter.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleInputSourceChange()
        })

        notificationObservers.append(distributedCenter.addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadAvailableInputSources()
            self?.refreshLockedInputSource()
            self?.handleInputSourceChange()
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleInputSourceChange()
        })

        notificationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleInputSourceChange()
        })
    }

    private func handleInputSourceChange() {
        updateCurrentInputSourceName()
        enforceLockedInputSource()
    }

    private func lock(source: TISInputSource) {
        let sourceID = getInputSourceID(source)
        guard !sourceID.isEmpty else { return }

        lockState.lock(inputSourceID: sourceID)
        startupLockPreferences.saveLockedInputSourceID(sourceID)
        didFailStartupLockRestore = false
        stopStartupRestoreTimer()
        syncPublishedLockState()
        startEnforcementTimer()
    }

    private func restoreStartupLockIfNeeded() {
        guard startupLockPreferences.restoreCandidateInputSourceID != nil else { return }
        attemptStartupLockRestore()
    }

    private func attemptStartupLockRestore() {
        guard let inputSourceID = startupLockPreferences.restoreCandidateInputSourceID else {
            stopStartupRestoreTimer()
            return
        }

        let didSelectInputSource: Bool
        if let source = inputSource(withID: inputSourceID) {
            didSelectInputSource = restoreStartupInputSource(source)
        } else {
            didSelectInputSource = false
        }

        switch startupRestoreRetryState.action(afterInputSourceSelectionSucceeded: didSelectInputSource) {
        case .restored:
            stopStartupRestoreTimer()
        case .retry:
            scheduleStartupLockRestoreRetry()
        case .unavailable:
            didFailStartupLockRestore = true
            stopStartupRestoreTimer()
        }
    }

    private func scheduleStartupLockRestoreRetry() {
        guard startupRestoreTimer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.startupRestoreTimer = nil
            self.attemptStartupLockRestore()
        }
        startupRestoreTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopStartupRestoreTimer() {
        startupRestoreTimer?.invalidate()
        startupRestoreTimer = nil
    }

    private func restoreStartupInputSource(_ source: TISInputSource) -> Bool {
        guard selectInputSource(source) else { return false }
        lock(source: source)
        updateCurrentInputSourceName()
        enforceLockedInputSource()
        return true
    }

    private func syncPublishedLockState() {
        isLocked = lockState.isLocked
        lockedInputSourceID = lockState.lockedInputSourceID
        refreshLockedInputSource()
    }

    private func refreshLockedInputSource() {
        guard let lockedInputSourceID = lockState.lockedInputSourceID else {
            lockedInputSource = nil
            return
        }

        lockedInputSource = inputSource(withID: lockedInputSourceID)
    }

    private func inputSource(withID inputSourceID: String) -> TISInputSource? {
        if let source = availableInputSources.first(where: { getInputSourceID($0) == inputSourceID }) {
            return source
        }

        loadAvailableInputSources()
        return availableInputSources.first { getInputSourceID($0) == inputSourceID }
    }

    private func enforceLockedInputSource() {
        guard lockState.isLocked, !isEnforcingLockedSource else { return }
        guard let lockedInputSourceID = lockState.lockedInputSourceID else { return }
        guard let currentSource = getCurrentInputSource() else { return }
        let currentID = getInputSourceID(currentSource)
        guard currentID != lockedInputSourceID else { return }

        if shouldAllowTemporaryInputSource(currentSource, whileLockedTo: lockedInputSourceID) {
            refreshLockedInputSource()
            return
        }

        guard let lockedSource = inputSource(withID: lockedInputSourceID) else { return }

        isEnforcingLockedSource = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            guard self.lockState.matchesLockedInputSourceID(lockedInputSourceID) else {
                self.isEnforcingLockedSource = false
                return
            }

            if !self.selectInputSource(lockedSource),
               let refreshedSource = self.inputSource(withID: lockedInputSourceID) {
                _ = self.selectInputSource(refreshedSource)
            }
            self.refreshLockedInputSource()
            self.isEnforcingLockedSource = false
        }
    }

    private func shouldAllowTemporaryInputSource(_ source: TISInputSource, whileLockedTo lockedInputSourceID: String) -> Bool {
        guard let lockedSource = inputSource(withID: lockedInputSourceID) else { return false }

        return TemporaryInputSourcePolicy.shouldAllowTemporaryASCIILayout(
            currentIsKeyboardLayout: isKeyboardLayout(source),
            currentIsASCIICapable: isASCIICapableInputSource(source),
            lockedIsKeyboardLayout: isKeyboardLayout(lockedSource),
            isCapsLockEnabled: NSEvent.modifierFlags.contains(.capsLock)
        )
    }

    private func startEnforcementTimer() {
        guard enforcementTimer == nil else { return }

        enforcementTimer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.enforceLockedInputSource()
        }
        if let enforcementTimer {
            RunLoop.main.add(enforcementTimer, forMode: .common)
        }
    }

    private func stopEnforcementTimer() {
        enforcementTimer?.invalidate()
        enforcementTimer = nil
    }
}
