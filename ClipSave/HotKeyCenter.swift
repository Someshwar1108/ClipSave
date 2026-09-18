import AppKit
import Carbon.HIToolbox

/// Registry for ClipSave's global hotkeys.
///
/// One shared Carbon event handler dispatches to the right action by hotkey
/// ID. This matters: the handler is invoked for *every* registered hotkey, so
/// installing a separate handler per hotkey — as ClipSave did when there was
/// only one — would make every action fire on every press once there is more
/// than one binding.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// Identifies a binding. Raw values are the Carbon hotkey IDs and are
    /// persisted only in memory, so they're free to change.
    enum Action: UInt32, CaseIterable {
        case openPanel = 1
        case pasteLastClip = 2
        case openPermanent = 3
        case togglePause = 4
    }

    private static let signature: OSType = 0x434C5053 // "CLPS"

    private var handlerRef: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    /// The combo currently bound to each action, so a rejected change can be
    /// rolled back to what was working.
    private var boundCombos: [UInt32: KeyCombo] = [:]

    private init() {}

    /// Changes the key bound to an action whose handler is already registered.
    ///
    /// This is what Settings calls. Going through the singleton rather than
    /// `AppDelegate.shared` matters: the delegate reference proved unreliable
    /// under SwiftUI's `@NSApplicationDelegateAdaptor`, and a shortcut editor
    /// that silently does nothing is worse than one that doesn't exist.
    @discardableResult
    func rebind(_ action: Action, to combo: KeyCombo?) -> String? {
        guard let handler = actions[action.rawValue] else {
            return "That action isn't available yet."
        }
        return register(action, combo: combo, handler: handler)
    }

    func combo(for action: Action) -> KeyCombo? {
        boundCombos[action.rawValue]
    }

    /// Binds `combo` to `action`, replacing any existing binding.
    ///
    /// Returns `nil` on success, or a message when the combination can't be
    /// claimed. `RegisterEventHotKey` refusing *is* the conflict check — it
    /// rejects combinations already held by another app or by the system, which
    /// is far more reliable than trying to enumerate system shortcuts.
    ///
    /// Passing a `nil` combo leaves the action unbound, which is how the
    /// optional shortcuts stay off until someone assigns them.
    @discardableResult
    func register(_ action: Action,
                  combo: KeyCombo?,
                  handler: @escaping () -> Void) -> String? {
        installHandlerIfNeeded()
        actions[action.rawValue] = handler

        guard let combo else {
            unregister(action)
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        // The old binding has to go before we try the new one, because
        // RegisterEventHotKey refuses a duplicate of our *own* registration —
        // which would make re-recording the same combination look like a
        // conflict. The previous combo is remembered so a genuine failure can
        // be rolled back.
        let previousCombo = boundCombos[action.rawValue]
        unregister(action)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            registrations[action.rawValue] = ref
            boundCombos[action.rawValue] = combo
            return nil
        }

        // Put the working binding back, so a rejected change never leaves the
        // action unreachable.
        if let previousCombo {
            var restored: EventHotKeyRef?
            if RegisterEventHotKey(previousCombo.keyCode,
                                   previousCombo.carbonModifiers,
                                   hotKeyID,
                                   GetApplicationEventTarget(),
                                   0,
                                   &restored) == noErr, let restored {
                registrations[action.rawValue] = restored
                boundCombos[action.rawValue] = previousCombo
            }
        }
        return "\(combo.display) is already in use."
    }

    func unregister(_ action: Action) {
        boundCombos[action.rawValue] = nil
        guard let ref = registrations.removeValue(forKey: action.rawValue) else { return }
        UnregisterEventHotKey(ref)
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                // A C callback can't capture context, so read the ID out of the
                // event and look the action up on the shared instance.
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return noErr }

                let id = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        HotKeyCenter.shared.fire(id)
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &handlerRef
        )
    }
}
