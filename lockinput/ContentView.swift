//
//  ContentView.swift
//  lockinput
//
//  Created by dave on 2025/12/19.
//

import SwiftUI
import Carbon
import ServiceManagement

struct ContentView: View {
    @ObservedObject var inputManager = InputMethodManager.shared
    @ObservedObject var languageManager = LanguageManager.shared
    @AppStorage("launchAtLogin") var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            inputSourceList

            Divider()

            footerView
        }
        .frame(width: 280)
    }

    var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: inputManager.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 24))
                    .foregroundColor(inputManager.isLocked ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(inputManager.isLocked
                         ? "status.locked".localized(with: languageManager)
                         : "status.unlocked".localized(with: languageManager))
                        .font(.headline)

                    Text(inputManager.currentInputSourceName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if inputManager.didFailStartupLockRestore {
                        Text("status.restoreUnavailable".localized(with: languageManager))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                Button(action: {
                    inputManager.toggle()
                }) {
                    Text(inputManager.isLocked
                         ? "button.unlock".localized(with: languageManager)
                         : "button.lock".localized(with: languageManager))
                        .frame(width: 60)
                }
                .buttonStyle(.borderedProminent)
                .tint(inputManager.isLocked ? .orange : .blue)
            }
        }
        .padding()
    }

    var inputSourceList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(inputManager.availableInputSources, id: \.self) { source in
                    InputSourceRow(
                        source: source,
                        isSelected: isCurrentSource(source),
                        isLocked: isLockedSource(source)
                    ) {
                        inputManager.lockInputSource(source)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 180)
    }

    var footerView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("settings.language".localized(with: languageManager))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Picker("", selection: $languageManager.currentLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .scaleEffect(0.85)
            }

            HStack {
                Toggle(isOn: Binding(
                    get: { inputManager.isRestoreOnLaunchEnabled },
                    set: { inputManager.setRestoreOnLaunchEnabled($0) }
                )) {
                    Label("settings.restoreLockOnLaunch".localized(with: languageManager), systemImage: "lock.rotation")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                Spacer()
            }

            HStack {
                Toggle(isOn: $launchAtLogin) {
                    Label("settings.launchAtLogin".localized(with: languageManager), systemImage: "power")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { newValue in
                    setLaunchAtLogin(newValue)
                }

                Spacer()

                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Label("button.quit".localized(with: languageManager), systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    func isCurrentSource(_ source: TISInputSource) -> Bool {
        guard let current = inputManager.getCurrentInputSource() else { return false }
        return inputManager.getInputSourceID(source) == inputManager.getInputSourceID(current)
    }

    func isLockedSource(_ source: TISInputSource) -> Bool {
        inputManager.getInputSourceID(source) == inputManager.lockedInputSourceID
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
}

struct InputSourceRow: View {
    let source: TISInputSource
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    @ObservedObject var inputManager = InputMethodManager.shared

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isLocked ? "lock.fill" : "keyboard")
                    .foregroundColor(isLocked ? .green : .secondary)
                    .frame(width: 20)

                Text(inputManager.getInputSourceName(source))
                    .foregroundColor(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    ContentView()
}
#endif
