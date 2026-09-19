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
    @Published var refinementEnabled = false
    @Published var showsRecognitionStages = false
    @Published var previewText = ""
    @Published var recognizedText = ""
    @Published var finalOutputText: String? = nil
    @Published var hasError = false
    @Published var refinementFallbackReason: String? = nil
    private var hideWorkItem: DispatchWorkItem?

    /// Called when the user taps the close/cancel button
    var onCancel: (() -> Void)?

    private let log = Logger.shared

    override init() {
        super.init()
        log.debug("Initialized", tag: "FloatingPanel")
    }

    func showPanel(refinementEnabled: Bool = false, showsRecognitionStages: Bool = false) {
        log.debug("Showing panel...", tag: "FloatingPanel")

        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.refinementEnabled = refinementEnabled
            self.showsRecognitionStages = showsRecognitionStages || refinementEnabled
            self.previewText = ""
            self.recognizedText = ""
            self.finalOutputText = nil
            self.hasError = false
            self.refinementFallbackReason = nil
            if self.panel == nil {
                self.createPanel()
            }
            self.panel?.setContentSize(NSSize(width: self.showsRecognitionStages ? 560 : 520, height: self.showsRecognitionStages ? 360 : 200))

            self.isVisible = true
            self.isRecording = true
            self.isProcessing = false
            self.statusMessage = "正在录音..."
            self.transcription = ""
            // fallbackWarning is preserved across sessions; set by AppDelegate

            self.panel?.orderFront(nil)

            self.log.debug("Panel is now visible", tag: "FloatingPanel")
        }
    }

    func hidePanel() {
        log.debug("Hiding panel...", tag: "FloatingPanel")

        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.isVisible = false
            self.isRecording = false
            self.isProcessing = false
            self.panel?.orderOut(nil)
            self.log.debug("Panel hidden", tag: "FloatingPanel")
        }
    }

    func updateTranscription(_ result: SpeechRecognitionResult) {
        DispatchQueue.main.async {
            guard self.isVisible, !self.hasError, self.finalOutputText == nil else { return }
            self.transcription = result.text
            if let stages = result.stages {
                self.previewText = stages.previewText
                self.recognizedText = stages.finalText
                self.refinementEnabled = stages.postRefinementEnabled
            }
            if self.isRecording {
                self.statusMessage = self.refinementEnabled ? "正在听 · 分段精修中" : "识别中..."
            }
        }
    }

    func showStatus(_ message: String) {
        DispatchQueue.main.async {
            guard !self.hasError, self.finalOutputText == nil else { return }
            self.statusMessage = message
            self.log.debug("Status updated: \(message)", tag: "FloatingPanel")
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

    func showResult(_ text: String, fallback: SpeechRefinementFallback? = nil, copiedOnly: Bool = false) {
        DispatchQueue.main.async {
            self.transcription = text
            self.finalOutputText = text
            self.refinementFallbackReason = fallback?.reason
            if let fallback { self.recognizedText = fallback.refinedText }
            self.hasError = false
            self.statusMessage = fallback != nil
                ? (copiedOnly ? "精修未完成 · 已复制，请手动粘贴" : "精修未完成 · 已使用识别文本")
                : (copiedOnly ? "已复制，请手动粘贴" : "完成")
            self.isRecording = false
            self.isProcessing = false

            // Auto-hide after a delay
            self.scheduleHide(after: 1.5)
        }
    }

    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.hasError = true
            self.statusMessage = "错误: \(message)"
            self.isRecording = false
            self.isProcessing = false

            self.scheduleHide(after: 2.0)
        }
    }

    func showRecognizedResult(_ text: String) {
        DispatchQueue.main.async { self.recognizedText = text }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hidePanel() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
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
                    Image(systemName: controller.hasError ? "exclamationmark.circle.fill" :
                            (controller.refinementFallbackReason != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                        .foregroundColor(controller.hasError ? .red : (controller.refinementFallbackReason != nil ? .orange : .green))
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
            if controller.showsRecognitionStages {
                recognitionComparison
            } else if !controller.transcription.isEmpty {
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
        .frame(width: controller.showsRecognitionStages ? 540 : 500, height: controller.showsRecognitionStages ? 340 : 180)
    }

    private var recognitionComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            transcriptSection(title: "实时预览 · 中间结果", text: controller.previewText,
                              placeholder: "说话时显示，文字可能变化", color: .white.opacity(0.6))
            Divider().overlay(Color.white.opacity(0.2))
            if controller.refinementFallbackReason != nil {
                transcriptSection(title: "本次输出 · 未完整精修", text: controller.finalOutputText ?? "",
                                  placeholder: "", color: .orange)
            } else {
                transcriptSection(title: controller.refinementEnabled ? "Azure 精修 · 最终结果" : "Azure 标准识别 · 最终结果",
                                  text: controller.recognizedText,
                                  placeholder: controller.hasError ? "未获得完整最终结果" :
                                    (controller.refinementEnabled ? "等待 Azure 返回精修结果…" : "等待 Azure 返回本段最终识别结果…"),
                                  color: .green)
            }
            if controller.refinementFallbackReason == nil, let output = controller.finalOutputText, output != controller.recognizedText {
                transcriptSection(title: "AI 润色 · 最终输出", text: output, placeholder: "", color: .orange)
            }
            Text(comparisonExplanation)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var comparisonExplanation: String {
        if let reason = controller.refinementFallbackReason {
            return "\(reason)；已保留可用识别文本，请检查内容是否完整。"
        }
        if controller.hasError { return "本次未输出识别文本" }
        if controller.finalOutputText == nil {
            return controller.refinementEnabled
                ? "分段精修；整次录音结束后粘贴，精修失败时使用已识别文本"
                : "每段结束后返回最终结果；整次录音结束后粘贴"
        }
        let stage = controller.refinementEnabled ? "精修完成" : "标准识别完成"
        return controller.previewText == controller.recognizedText
            ? "\(stage) · 与预览一致" : "\(stage) · 使用最终结果输出"
    }

    private func transcriptSection(title: String, text: String, placeholder: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: title.hasPrefix("实时") ? "waveform" : "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: 15))
                    .foregroundColor(text.isEmpty ? .white.opacity(0.4) : .white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 70)
        }
    }
}

#Preview {
    FloatingTranscriptView()
        .environmentObject(FloatingPanelController.shared)
        .padding()
        .background(Color.gray)
}
