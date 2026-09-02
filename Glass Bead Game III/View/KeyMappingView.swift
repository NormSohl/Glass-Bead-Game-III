//
//  KeyMappingView.swift
//  Glass Bead Game III
//
//  Lets Norm see and change which keys drive Drone/Portamento(toggle)/Portamento(hold)/
//  Pedal(hold) - see KeyMapping.swift for the persisted model this reads/writes, and
//  ContentView's KeyCommandMonitor for where the mapping actually gets applied live.
//

import SwiftUI
import AppKit

struct KeyMappingView: View {
    @ObservedObject var settings: AppSettings

    @State private var listeningFor: KeyAction?
    @State private var captureMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Mapping").font(.headline)
            Text("Click + on an action, then press the key (or hold a modifier alone, like Shift) you want. Binding a key that's already used somewhere else moves it here instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(KeyAction.allCases, id: \.self) { action in
                    actionRow(action)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Reset to Defaults") {
                    stopListening()
                    settings.keyMapping = .defaultMapping
                }
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 360, idealWidth: 380, minHeight: 300)
        // Belt-and-suspenders alongside stopListening()'s own reset of isCapturingKeyBinding -
        // the popover closing is exactly the kind of dismissal that wouldn't otherwise clear it,
        // and a stuck true here would silence the main key monitor permanently.
        .onDisappear { stopListening() }
    }

    @ViewBuilder
    private func actionRow(_ action: KeyAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(action.displayName).font(.subheadline).bold()
            HStack(spacing: 6) {
                let tokens = settings.keyMapping.tokens(for: action).sorted()
                ForEach(tokens, id: \.self) { token in
                    keyChip(token, action: action)
                }

                Button {
                    if listeningFor == action {
                        stopListening()
                    } else {
                        startListening(for: action)
                    }
                } label: {
                    if listeningFor == action {
                        Label("Press a key…", systemImage: "ellipsis")
                    } else {
                        Image(systemName: "plus.circle")
                    }
                }
                .tint(listeningFor == action ? TetradView.uiAccentColor : nil)
            }
        }
    }

    private func keyChip(_ token: KeyToken, action: KeyAction) -> some View {
        HStack(spacing: 4) {
            Text(displayLabel(forKeyToken: token))
                .font(.caption)
            Button {
                settings.keyMapping.unbind(token, from: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
    }

    private func startListening(for action: KeyAction) {
        stopListening()
        listeningFor = action
        settings.isCapturingKeyBinding = true
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            switch event.type {
            case .keyDown:
                // Same Space special-case as ContentView's own KeyCommandMonitor - key code 49
                // rather than relying on charactersIgnoringModifiers for it.
                let token: KeyToken = event.keyCode == 49 ? " " : (event.charactersIgnoringModifiers?.lowercased() ?? "")
                if !token.isEmpty {
                    settings.keyMapping.bind(token, to: action)
                    stopListening()
                }
                return nil // swallow unconditionally while capturing - nothing else should react
            case .flagsChanged:
                // Bind on whichever modifier was the one that just became newly held - a bare
                // modifier press alone is a valid binding (this is how Portamento's own hold
                // works by default), captured the same way a regular key would be.
                for token in modifierKeyTokens {
                    let flag: NSEvent.ModifierFlags = {
                        switch token {
                        case "shift": return .shift
                        case "option": return .option
                        case "control": return .control
                        case "command": return .command
                        default: return []
                        }
                    }()
                    if event.modifierFlags.contains(flag) {
                        settings.keyMapping.bind(token, to: action)
                        stopListening()
                        break
                    }
                }
                return event
            default:
                return event
            }
        }
    }

    private func stopListening() {
        if let captureMonitor { NSEvent.removeMonitor(captureMonitor) }
        captureMonitor = nil
        listeningFor = nil
        settings.isCapturingKeyBinding = false
    }
}
