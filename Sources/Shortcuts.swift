import Carbon.HIToolbox
import Cocoa

final class HotKey {
    private var reference: EventHotKeyRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            Unmanaged<HotKey>.fromOpaque(context!).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: HOTKEY_SIGNATURE, id: 1),
                            GetApplicationEventTarget(), 0, &reference)
    }
}

// MARK: - Double-tap trigger

// Fires when the modifier is tapped twice on its own; any key, click or other modifier in between cancels it.
final class DoubleTap {
    private let modifier: NSEvent.ModifierFlags
    private let action: () -> Void
    private var monitors: [Any] = []
    private var pressedAt: Date?
    private var lastTapAt: Date?

    init(modifier: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.modifier = modifier
        self.action = action
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in self?.handle($0) },
            NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.reset()
            },
        ].compactMap { $0 }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(TRACKED_MODIFIERS)
        if flags == modifier {
            pressedAt = Date()
        } else if flags.isEmpty, let pressedAt, Date().timeIntervalSince(pressedAt) < TAP_MAX_DURATION {
            registerTap()
        } else {
            reset()
        }
    }

    private func registerTap() {
        pressedAt = nil
        let now = Date()
        if let lastTapAt, now.timeIntervalSince(lastTapAt) < DOUBLE_TAP_INTERVAL {
            self.lastTapAt = nil
            action()
        } else {
            lastTapAt = now
        }
    }

    private func reset() {
        pressedAt = nil
        lastTapAt = nil
    }
}
