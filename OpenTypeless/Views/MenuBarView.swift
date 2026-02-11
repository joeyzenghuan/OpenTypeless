import SwiftUI
import AVFoundation

struct MenuBarView: View {
    @State private var selectedTab: Tab = .home

    enum Tab {
        case home
        case history
        case settings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.blue)
                Text("OpenTypeless")
                    .font(.headline)
                Spacer()
                Text("Pro Trial")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Sidebar + Content
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 4) {
                    SidebarButton(icon: "house", title: "首页", isSelected: selectedTab == .home) {
                        selectedTab = .home
                    }
                    SidebarButton(icon: "clock", title: "历史记录", isSelected: selectedTab == .history) {
                        selectedTab = .history
                    }
                    Spacer()

                    Divider()

                    SidebarButton(icon: "gear", title: "设置", isSelected: selectedTab == .settings) {
                        selectedTab = .settings
                    }
                }
                .frame(width: 100)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Main Content
                VStack {
                    switch selectedTab {
                    case .home:
                        HomeTabView()
                    case .history:
                        HistoryTabView()
                    case .settings:
                        SettingsTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .blue : .primary)
    }
}

// MARK: - Tab Views

struct HomeTabView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("按住 fn 键开始说话")
                .font(.headline)

            Text("释放后自动插入文字")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Status
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("就绪")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryTabView: View {
    @ObservedObject private var historyManager = HistoryManager.shared
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var searchText = ""
    @State private var showClearConfirmation = false

    private var displayedRecords: [TranscriptionRecord] {
        if searchText.isEmpty {
            return historyManager.records
        }
        return historyManager.search(query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("历史记录")
                    .font(.headline)
                Spacer()
                if !historyManager.records.isEmpty {
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清空所有记录")
                    .alert("确认删除", isPresented: $showClearConfirmation) {
                        Button("删除全部", role: .destructive) {
                            audioPlayer.stop()
                            historyManager.clearAllRecords()
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("确定要删除所有历史记录吗？此操作不可撤销。")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)

            if !historyManager.records.isEmpty {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if displayedRecords.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "暂无历史记录" : "无搜索结果")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(displayedRecords) { record in
                            HistoryRecordRow(record: record) {
                                historyManager.deleteRecord(record)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(audioPlayer)
    }
}

struct HistoryRecordRow: View {
    let record: TranscriptionRecord
    var onDelete: () -> Void
    @EnvironmentObject private var audioPlayer: AudioPlayerManager
    @State private var showOriginal = false

    private var isPlaying: Bool {
        audioPlayer.playingRecordId == record.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayText)
                .font(.system(size: 12))
                .lineLimit(3)

            if showOriginal, record.polishedText != nil {
                HStack(alignment: .top, spacing: 4) {
                    Text("原文")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                    Text(record.originalText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 6) {
                Text(record.formattedTime)
                Text("·")
                Text(record.sttProviderName)
                if record.polishedText != nil {
                    Text("·")
                    Button(action: {
                        showOriginal.toggle()
                    }) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundColor(showOriginal ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showOriginal ? "收起原文" : "对照原文")
                }
                Spacer()

                if record.audioFilePath != nil {
                    Button(action: {
                        if let path = record.audioFilePath {
                            audioPlayer.play(filePath: path, recordId: record.id)
                        }
                    }) {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                            .font(.system(size: 12))
                            .foregroundColor(isPlaying ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "停止播放" : "播放录音")
                }

                Button(action: {
                    if isPlaying { audioPlayer.stop() }
                    onDelete()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除此条记录")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Audio Player Manager

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingRecordId: UUID?
    private var audioPlayer: AVAudioPlayer?

    func play(filePath: String, recordId: UUID) {
        // If already playing this record, stop it
        if playingRecordId == recordId {
            stop()
            return
        }

        // Stop any current playback
        stop()

        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("[AudioPlayer] File not found: \(filePath)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            playingRecordId = recordId
        } catch {
            print("[AudioPlayer] Failed to play: \(error)")
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordId = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.playingRecordId = nil
        }
    }
}

#Preview {
    MenuBarView()
}
