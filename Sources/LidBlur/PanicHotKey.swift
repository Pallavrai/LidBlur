import Carbon.HIToolbox

/// Control-Option-Command-B quits LidBlur immediately, so the overlay can never trap the user.
/// The window server removes a dead app's windows. Carbon hotkeys need no permission prompt.
@MainActor
final class PanicHotKey {
    private var ref: EventHotKeyRef?
    private(set) var registrationError: OSStatus = noErr

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in exit(0) }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4C424C52), id: 1)   // 'LBLR'
        registrationError = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | optionKey | controlKey),
                                                id, GetApplicationEventTarget(), 0, &ref)
    }
}
