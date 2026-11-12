import Carbon
import SwitchboardCore

/// Registers one global shortcut with Carbon's RegisterEventHotKey.
/// Unlike an event tap this needs no Accessibility permission.
final class HotKeyCenter {
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    fileprivate static var action: (() -> Void)?

    /// Returns false if macOS refused the shortcut (usually because another app holds it).
    @discardableResult
    func register(_ hotkey: Hotkey, action: @escaping () -> Void) -> Bool {
        unregister()
        HotKeyCenter.action = action

        if !handlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyCenter.action?() }
                return noErr
            }, 1, &type, nil, nil)
            handlerInstalled = true
        }

        let id = EventHotKeyID(signature: OSType(0x5357_4244), id: 1) // "SWBD"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
