import Foundation
import Carbon
import Cocoa

/// Manages global hotkey detection for configurable key combinations.
///
/// Supports three actions:
/// - Voice input (hold-to-talk): key down starts recording, key up stops
/// - Hands-free mode (toggle): single press toggles on/off
/// - Translate mode (single press): triggers translation of selected text
///
/// Reads shortcut configurations from AppSettings and monitors for both
/// modifier-only shortcuts (e.g., fn alone) and modifier+key combinations
/// (e.g., Cmd+Shift+R).
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var isFnKeyPressed: Bool = false
    @Published var isRecording: Bool = false
    @Published var isHandsFreeActive: Bool = false

    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    // Resolved shortcut combinations (read from settings)
    private var voiceInputCombo: KeyCombination = .defaultVoiceInput
    private var handsFreeCombo: KeyCombination = .defaultHandsFree
    private var translateCombo: KeyCombination = .defaultTranslate

    // Track which modifier-only shortcut is currently held (for hold-to-talk)
    private var voiceInputModifierHeld: Bool = false
    // Track which key-based shortcut is currently held (for hold-to-talk)
    private var voiceInputKeyHeld: Bool = false

    private let log = Logger.shared

    // Callbacks for voice input (hold-to-talk)
    var onVoiceInputDown: (() -> Void)?
    var onVoiceInputUp: (() -> Void)?

    // Callbacks for hands-free mode (toggle)
    var onHandsFreeToggle: ((_ isActive: Bool) -> Void)?

    // Callback for translate mode (single press)
    var onTranslate: (() -> Void)?

    // Legacy aliases for backward compatibility
    var onFnKeyDown: (() -> Void)? {
        get { return onVoiceInputDown }
        set { onVoiceInputDown = newValue }
    }
    var onFnKeyUp: (() -> Void)? {
        get { return onVoiceInputUp }
        set { onVoiceInputUp = newValue }
    }

    private init() {
        log.info("Initializing...", tag: "HotkeyManager")
        reloadShortcuts()
    }

    // MARK: - Configuration

    /// Reload shortcut configurations from AppSettings.
    func reloadShortcuts() {
        let settings = AppSettings.shared
        voiceInputCombo = settings.getVoiceInputShortcut()
        handsFreeCombo = settings.getHandsFreeShortcut()
        translateCombo = settings.getTranslateShortcut()

        log.info("Shortcuts loaded:", tag: "HotkeyManager")
        log.info("  Voice Input: \(voiceInputCombo.displayString)", tag: "HotkeyManager")
        log.info("  Hands-Free:  \(handsFreeCombo.displayString)", tag: "HotkeyManager")
        log.info("  Translate:   \(translateCombo.displayString)", tag: "HotkeyManager")
    }

    // MARK: - Monitoring

    func startMonitoring() {
        log.info("Starting hotkey monitoring...", tag: "HotkeyManager")
        reloadShortcuts()

        // Monitor for flags changed events (modifier keys including fn)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also add local monitor for when app is in focus
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Monitor for key events to detect key combinations (global - works when app not focused)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local key monitor for when app is in focus
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }

        log.info("Monitoring started", tag: "HotkeyManager")
        log.info("Listening for shortcuts...", tag: "HotkeyManager")
    }

    func stopMonitoring() {
        log.info("Stopping hotkey monitoring...", tag: "HotkeyManager")

        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }

        log.info("Monitoring stopped", tag: "HotkeyManager")
    }

    // MARK: - Event Handling

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags

        // --- Voice Input (modifier-only, hold-to-talk) ---
        if voiceInputCombo.isModifierOnly {
            let matched = voiceInputCombo.matchesModifierFlags(flags)

            if matched && !voiceInputModifierHeld {
                // Modifier combo just pressed
                voiceInputModifierHeld = true
                log.debug("Voice input shortcut DOWN (\(voiceInputCombo.displayString))", tag: "HotkeyManager")
                DispatchQueue.main.async {
                    self.isFnKeyPressed = true
                    self.isRecording = true
                    self.onVoiceInputDown?()
                }
            } else if !matched && voiceInputModifierHeld {
                // Modifier combo just released
                voiceInputModifierHeld = false
                log.debug("Voice input shortcut UP (\(voiceInputCombo.displayString))", tag: "HotkeyManager")
                DispatchQueue.main.async {
                    self.isFnKeyPressed = false
                    self.isRecording = false
                    self.onVoiceInputUp?()
                }
            }
        }

        // --- Hands-Free (modifier-only, toggle) ---
        if handsFreeCombo.isModifierOnly {
            let matched = handsFreeCombo.matchesModifierFlags(flags)
            handleHandsFreeModifierToggle(matched: matched)
        }

        // --- Translate (modifier-only, single press) ---
        if translateCombo.isModifierOnly {
            handleTranslateModifierPress(matched: translateCombo.matchesModifierFlags(flags))
        }
    }

    // Tracking state for modifier-only toggle/press detection
    private var handsFreeModifierWasMatched = false
    private var translateModifierWasMatched = false

    private func handleHandsFreeModifierToggle(matched: Bool) {
        if matched && !handsFreeModifierWasMatched {
            // Transition to matched: trigger toggle
            handsFreeModifierWasMatched = true
            log.debug("Hands-free toggle (\(handsFreeCombo.displayString))", tag: "HotkeyManager")
            DispatchQueue.main.async {
                self.isHandsFreeActive.toggle()
                self.onHandsFreeToggle?(self.isHandsFreeActive)
            }
        } else if !matched {
            handsFreeModifierWasMatched = false
        }
    }

    private func handleTranslateModifierPress(matched: Bool) {
        if matched && !translateModifierWasMatched {
            translateModifierWasMatched = true
            log.debug("Translate triggered (\(translateCombo.displayString))", tag: "HotkeyManager")
            DispatchQueue.main.async {
                self.onTranslate?()
            }
        } else if !matched {
            translateModifierWasMatched = false
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let isKeyDown = event.type == .keyDown
        let isKeyUp = event.type == .keyUp

        // --- Voice Input (key-based, hold-to-talk) ---
        if !voiceInputCombo.isModifierOnly {
            if isKeyDown && voiceInputCombo.matchesKeyEvent(event) && !voiceInputKeyHeld {
                voiceInputKeyHeld = true
                log.debug("Voice input shortcut DOWN (\(voiceInputCombo.displayString))", tag: "HotkeyManager")
                DispatchQueue.main.async {
                    self.isFnKeyPressed = true
                    self.isRecording = true
                    self.onVoiceInputDown?()
                }
            } else if isKeyUp && voiceInputKeyHeld && event.keyCode == voiceInputCombo.keyCode {
                voiceInputKeyHeld = false
                log.debug("Voice input shortcut UP (\(voiceInputCombo.displayString))", tag: "HotkeyManager")
                DispatchQueue.main.async {
                    self.isFnKeyPressed = false
                    self.isRecording = false
                    self.onVoiceInputUp?()
                }
            }
        }

        // --- Hands-Free (key-based, toggle on keyDown) ---
        if !handsFreeCombo.isModifierOnly {
            if isKeyDown && handsFreeCombo.matchesKeyEvent(event) && !event.isARepeat {
                log.debug("Hands-free toggle (\(handsFreeCombo.displayString))", tag: "HotkeyManager")
                DispatchQueue.main.async {
                    self.isHandsFreeActive.toggle()
                    self.onHandsFreeToggle?(self.isHandsFreeActive)
                }
            }
        }

        // --- Translate (key-based, single press on keyDown) ---
        if !translateCombo.isModifierOnly {
            if isKeyDown && translateCombo.matchesKeyEvent(event) && !event.isARepeat {
                log.debug("Translate triggered (\(translateCombo.displayString))", tag: "HotkeyManager")
                DispatchQueue.main.async {
                    self.onTranslate?()
                }
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
