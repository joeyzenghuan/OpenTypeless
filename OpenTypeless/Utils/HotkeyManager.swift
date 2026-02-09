import Foundation
import Carbon
import Cocoa

/// Manages global hotkey detection, specifically for the fn key
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var isFnKeyPressed: Bool = false
    @Published var isRecording: Bool = false

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var flagsMonitor: Any?

    // Callbacks
    var onFnKeyDown: (() -> Void)?
    var onFnKeyUp: (() -> Void)?

    private init() {
        print("[HotkeyManager] Initializing...")
    }

    func startMonitoring() {
        print("[HotkeyManager] Starting hotkey monitoring...")

        // Monitor for flags changed events (modifier keys including fn)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also add local monitor for when app is in focus
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Monitor for key events to detect fn key combinations
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        print("[HotkeyManager] ✅ Monitoring started")
        print("[HotkeyManager] Listening for fn key press...")
    }

    func stopMonitoring() {
        print("[HotkeyManager] Stopping hotkey monitoring...")

        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        print("[HotkeyManager] ✅ Monitoring stopped")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags

        // Check for fn key - it's represented by the function key flag
        let fnPressed = flags.contains(.function)

        // Debug: print all modifier flags
        print("[HotkeyManager] Flags changed: fn=\(fnPressed), flags=\(flags.rawValue)")

        if fnPressed && !isFnKeyPressed {
            // fn key just pressed
            print("[HotkeyManager] 🎤 fn key DOWN - Starting recording...")
            DispatchQueue.main.async {
                self.isFnKeyPressed = true
                self.isRecording = true
                self.onFnKeyDown?()
            }
        } else if !fnPressed && isFnKeyPressed {
            // fn key just released
            print("[HotkeyManager] 🛑 fn key UP - Stopping recording...")
            DispatchQueue.main.async {
                self.isFnKeyPressed = false
                self.isRecording = false
                self.onFnKeyUp?()
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Log key events for debugging
        if event.modifierFlags.contains(.function) {
            print("[HotkeyManager] Key event with fn: keyCode=\(event.keyCode), type=\(event.type.rawValue)")
        }
    }

    deinit {
        stopMonitoring()
    }
}
