import Carbon
import SwitchboardCore

/// Global shortcuts through Carbon's RegisterEventHotKey.
/// Unlike an event tap this needs no Accessibility permission.
final class HotKeyCenter {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    fileprivate static var actions: [UInt32: () -> Void] = [:]

    /// Registers `hotkey` under `slot` (replacing what was there).
    /// Returns false if macOS refused it (usually because another app holds it).
    @discardableResult
    func register(_ hotkey: Hotkey, slot: UInt32, action: @escaping () -> Void) -> Bool {
        unregister(slot)
        HotKeyCenter.actions[slot] = action
        installHandler()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5357_4244), id: slot) // "SWBD"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[slot] = ref; return true }
        return false
    }

    func unregister(_ slot: UInt32) {
        if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let slot = id.id
            DispatchQueue.main.async { HotKeyCenter.actions[slot]?() }
            return noErr
        }, 1, &type, nil, nil)
        handlerInstalled = true
    }
}
