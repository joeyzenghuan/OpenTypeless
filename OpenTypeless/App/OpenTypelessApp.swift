import SwiftUI
import AVFoundation
import ApplicationServices

@main
struct OpenTypelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        requestPermissions()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "OpenTypeless")
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func requestPermissions() {
        // Request microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("Microphone permission: \(granted)")
        }

        // Check accessibility permission with prompt
        // This will show a system dialog directing user to Settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            print("Accessibility permission: \(accessibilityEnabled)")

            if !accessibilityEnabled {
                print("⚠️ Accessibility permission required for text insertion.")
                print("   Please go to: System Settings → Privacy & Security → Accessibility")
                print("   Then add OpenTypeless (or Xcode if running from Xcode)")
            }
        }
    }

    // Check accessibility permission status
    static var isAccessibilityEnabled: Bool {
        return AXIsProcessTrusted()
    }
}
