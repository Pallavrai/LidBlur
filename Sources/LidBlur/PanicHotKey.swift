import Carbon.HIToolbox

/// Control-Option-Command-B: force-quits LidBlur so the overlay can never trap the user. Carbon hotkeys need no permission prompt.
@MainActor
final class PanicHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void
    private(set) var registrationError: OSStatus = noErr

    init(action: @escaping @MainActor () -> Void) { self.action = action }

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            MainActor.assumeIsolated { Unmanaged<PanicHotKey>.fromOpaque(ctx!).takeUnretainedValue().action() }
            return noErr
        }, 1, &spec, ctx, &handler)
        let id = EventHotKeyID(signature: OSType(0x4C424C52), id: 1)   // 'LBLR'
        registrationError = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | optionKey | controlKey),
                                                id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
