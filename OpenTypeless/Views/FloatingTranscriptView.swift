import SwiftUI
import AppKit

/// Floating window that shows recording status and transcription
class FloatingPanelController: NSObject, ObservableObject {
    static let shared = FloatingPanelController()

    private var panel: NSPanel?
    @Published var isVisible: Bool = false
    @Published var transcription: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var statusMessage: String = "准备就绪"
    @Published var providerName: String = ""
    @Published var fallbackWarning: String? = nil

    /// Called when the user taps the close/cancel button
    var onCancel: (() -> Void)?

    private let log = Logger.shared

    override init() {
        super.init()
        log.debug("Initialized", tag: "FloatingPanel")
    }

    func showPanel() {
        log.debug("Showing panel...", tag: "FloatingPanel")

        DispatchQueue.main.async {
            if self.panel == nil {
                self.createPanel()
            }

            self.isVisible = true
            self.isRecording = true
            self.isProcessing = false
            self.statusMessage = "正在录音..."
            self.transcription = ""
            // fallbackWarning is preserved across sessions; set by AppDelegate

            self.panel?.orderFront(nil)
            self.panel?.makeKey()

            self.log.debug("Panel is now visible", tag: "FloatingPanel")
        }
    }

    func hidePanel() {
        log.debug("Hiding panel...", tag: "FloatingPanel")

        DispatchQueue.main.async {
            self.isVisible = false
            self.isRecording = false
            self.isProcessing = false
            self.panel?.orderOut(nil)
            self.log.debug("Panel hidden", tag: "FloatingPanel")
        }
    }

    func updateTranscription(_ text: String) {
        DispatchQueue.main.async {
            self.transcription = text
            self.statusMessage = text.isEmpty ? "正在听..." : "识别中..."
            self.log.debug("Transcription updated: \(text)", tag: "FloatingPanel")
        }
    }

    /// Show processing state while waiting for model response
    func showProcessing(originalText: String, statusMessage: String = "录音已结束，正在等待模型返回结果...") {
        DispatchQueue.main.async {
            self.transcription = originalText
            self.isRecording = false
            self.isProcessing = true
            self.statusMessage = statusMessage
            self.log.info("Processing: \(statusMessage)", tag: "FloatingPanel")
        }
    }

    func showResult(_ text: String) {
        DispatchQueue.main.async {
            self.transcription = text
            self.statusMessage = "完成"
            self.isRecording = false
            self.isProcessing = false

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
            self.isProcessing = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.hidePanel()
            }
        }
    }

    /// Called when user clicks the close button
    func cancelByUser() {
        log.info("User requested cancel", tag: "FloatingPanel")
        onCancel?()
    }

    private func createPanel() {
        log.debug("Creating panel window...", tag: "FloatingPanel")

        let contentView = FloatingTranscriptView()
            .environmentObject(self)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 200)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
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
        log.debug("Panel created", tag: "FloatingPanel")
    }
}

struct FloatingTranscriptView: View {
    @EnvironmentObject var controller: FloatingPanelController

    var body: some View {
        VStack(spacing: 12) {
            // Top bar: status indicator + close button
            HStack(spacing: 10) {
                // Westie dog icon (left side)
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .foregroundColor(controller.isRecording ? .red : (controller.isProcessing ? .orange : .white))

                if controller.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
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
                } else if controller.isProcessing {
                    // Processing indicator - spinning
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(0.8)

                    Text(controller.statusMessage)
                        .font(.headline)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(controller.statusMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Spacer()

                // Provider name badge
                if !controller.providerName.isEmpty {
                    Text(controller.providerName)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(4)
                }

                // Close button
                Button(action: {
                    controller.cancelByUser()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("关闭并取消")
            }

            // Fallback warning
            if let warning = controller.fallbackWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text(warning)
                        .font(.caption2)
                        .foregroundColor(.yellow.opacity(0.9))
                    Spacer()
                }
            }

            // Transcription text - full width with word wrap
            if !controller.transcription.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(controller.transcription)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 8)
                }
                .frame(minHeight: 60, maxHeight: 120)
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.9))
        )
        .frame(width: 500, height: 180)
    }
}

#Preview {
    FloatingTranscriptView()
        .environmentObject(FloatingPanelController.shared)
        .padding()
        .background(Color.gray)
}
