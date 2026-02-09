import SwiftUI

struct MenuBarView: View {
    @State private var selectedTab: Tab = .home

    enum Tab {
        case home
        case history
        case dictionary
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
                    SidebarButton(icon: "book", title: "词典", isSelected: selectedTab == .dictionary) {
                        selectedTab = .dictionary
                    }

                    Spacer()

                    Divider()

                    // Settings button
                    Button(action: openSettings) {
                        HStack {
                            Image(systemName: "gear")
                            Text("设置")
                        }
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
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
                    case .dictionary:
                        DictionaryTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 320, height: 400)
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
    var body: some View {
        VStack {
            HStack {
                Text("历史记录")
                    .font(.headline)
                Spacer()
            }
            .padding()

            if true { // Replace with actual history check
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无历史记录")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DictionaryTabView: View {
    var body: some View {
        VStack {
            HStack {
                Text("个人词典")
                    .font(.headline)
                Spacer()
                Button(action: {}) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding()

            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "book")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("词典为空")
                    .foregroundColor(.secondary)
                Text("说话时纠正的词汇会自动添加")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MenuBarView()
}
