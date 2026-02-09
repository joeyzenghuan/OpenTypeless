import SwiftUI
import AppKit

/// Floating window that shows recording status and transcription
class FloatingPanelController: NSObject, ObservableObject {
    static let shared = FloatingPanelController()

    private var panel: NSPanel?
    @Published var isVisible: Bool = false
    @Published var transcription: String = ""
    @Published var isRecording: Bool = false
    @Published var statusMessage: String = "准备就绪"

    override init() {
        super.init()
        print("[FloatingPanel] Initialized")
    }

    func showPanel() {
        print("[FloatingPanel] Showing panel...")

        DispatchQueue.main.async {
            if self.panel == nil {
                self.createPanel()
            }

            self.isVisible = true
            self.isRecording = true
            self.statusMessage = "正在录音..."
            self.transcription = ""

            self.panel?.orderFront(nil)
            self.panel?.makeKey()

            print("[FloatingPanel] ✅ Panel is now visible")
        }
    }

    func hidePanel() {
        print("[FloatingPanel] Hiding panel...")

        DispatchQueue.main.async {
            self.isVisible = false
            self.isRecording = false
            self.panel?.orderOut(nil)
            print("[FloatingPanel] ✅ Panel hidden")
        }
    }

    func updateTranscription(_ text: String) {
        DispatchQueue.main.async {
            self.transcription = text
            self.statusMessage = text.isEmpty ? "正在听..." : "识别中..."
            print("[FloatingPanel] Transcription updated: \(text)")
        }
    }

    func showResult(_ text: String) {
        DispatchQueue.main.async {
            self.transcription = text
            self.statusMessage = "完成"
            self.isRecording = false

            // Auto-hide after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.hidePanel()
            }
        }
    }

    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessage = "错误: \(message)"
            self.isRecording = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.hidePanel()
            }
        }
    }

    private func createPanel() {
        print("[FloatingPanel] Creating panel window...")

        let contentView = FloatingTranscriptView()
            .environmentObject(self)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 150)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 150),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.minY + 80 // Near bottom of screen
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        print("[FloatingPanel] ✅ Panel created")
    }
}

struct FloatingTranscriptView: View {
    @EnvironmentObject var controller: FloatingPanelController

    var body: some View {
        VStack(spacing: 12) {
            // Recording indicator
            HStack(spacing: 8) {
                if controller.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(controller.isRecording ? 1 : 0)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: controller.isRecording)
                        )

                    Text(controller.statusMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(controller.statusMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Spacer()

                Image(systemName: "mic.fill")
                    .foregroundColor(controller.isRecording ? .red : .gray)
            }

            // Transcription text - full width with word wrap
            if !controller.transcription.isEmpty {
                ScrollView {
                    Text(controller.transcription)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            } else if controller.isRecording {
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .offset(y: controller.isRecording ? -5 : 0)
                            .animation(
                                .easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                                value: controller.isRecording
                            )
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .frame(width: 480)
    }
}

#Preview {
    FloatingTranscriptView()
        .environmentObject(FloatingPanelController.shared)
        .padding()
        .background(Color.gray)
}
