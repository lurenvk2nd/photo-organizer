import SwiftUI
import Photos

/// 分组列表视图，显示所有照片分组
struct GroupListView: View {
    @ObservedObject var viewModel: GroupingViewModel
    @ObservedObject var recommendationViewModel: RecommendationViewModel
    @State private var selectedGroup: PhotoGroup?
    @State private var showingGroupDetail = false
    @State private var showingFilterOptions = false
    @State private var filterOption: GroupFilterOption = .all

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.photoGroups.isEmpty {
                    emptyView
                } else {
                    groupListView
                }
            }
            .navigationTitle("照片分组")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    filterButton
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.photoGroups.isEmpty {
                        statsButton
                    }
                }
            }
            .sheet(isPresented: $showingGroupDetail) {
                if let group = selectedGroup {
                    GroupDetailView(group: group,
                                  viewModel: recommendationViewModel)
                }
            }
            .sheet(isPresented: $showingFilterOptions) {
                FilterOptionsView(selectedOption: $filterOption)
            }
        }
    }

    // MARK: - 子视图

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text(viewModel.progressDescription)
                    .font(.headline)

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            VStack(spacing: 12) {
                Text("还没有照片分组")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("点击下方按钮开始分析照片")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    await viewModel.startGrouping()
                }
            }) {
                Label("开始分析照片", systemImage: "magnifyingglass")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 20)

            Text("系统会自动按时间、地点和画面相似度将照片分组")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var groupListView: some View {
        List {
            // 统计摘要
            if !viewModel.photoGroups.isEmpty {
                Section {
                    StatsSummaryView(statistics: viewModel.statistics)
                }
            }

            // 分组列表
            ForEach(filteredGroups) { group in
                GroupRowView(group: group,
                            priority: viewModel.getProcessingPriority(for: group))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedGroup = group
                        showingGroupDetail = true
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                viewModel.removePhotosFromGroup(group.photos, from: group.id)
                            }
                        } label: {
                            Label("删除组", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .refreshable {
            await viewModel.startGrouping()
        }
    }

    private var filterButton: some View {
        Button(action: { showingFilterOptions = true }) {
            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var statsButton: some View {
        NavigationLink(destination: GroupStatsView(viewModel: viewModel)) {
            Label("统计", systemImage: "chart.bar")
        }
    }

    // MARK: - 计算属性

    private var filteredGroups: [PhotoGroup] {
        switch filterOption {
        case .all:
            return viewModel.photoGroups
        case .smallGroups:
            return viewModel.photoGroups.filter { $0.photos.count <= 5 }
        case .largeGroups:
            return viewModel.photoGroups.filter { $0.photos.count > 5 }
        case .recent:
            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return viewModel.photoGroups.filter { group in
                guard let date = group.creationDate else { return false }
                return date > oneWeekAgo
            }
        }
    }
}

// MARK: - 分组行视图

struct GroupRowView: View {
    let group: PhotoGroup
    let priority: GroupingViewModel.ProcessingPriority

    var body: some View {
        HStack(spacing: 12) {
            // 预览图（显示前3张照片）
            GroupPreviewView(photos: group.photos.prefix(3).map { $0 })

            VStack(alignment: .leading, spacing: 4) {
                // 分组标题
                Text(group.description)
                    .font(.headline)
                    .lineLimit(1)

                // 照片数量
                Label("\(group.photos.count)张照片", systemImage: "photo")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // 时间范围
                if let timeRange = group.timeRange, timeRange > 0 {
                    Text("时间范围: \(formatTimeRange(timeRange))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // 优先级标签
                priorityTag
            }

            Spacer()

            // 右侧箭头
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }

    private var priorityTag: some View {
        Text(priority.description)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: priority.color))
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private func formatTimeRange(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))秒"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))分钟"
        } else {
            return "\(Int(seconds / 3600))小时"
        }
    }
}

// MARK: - 分组预览视图

struct GroupPreviewView: View {
    let photos: [PHAsset]
    let size: CGFloat = 60

    var body: some View {
        ZStack {
            // 背景
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(width: size, height: size)

            // 照片堆叠效果
            if photos.count >= 1 {
                photoView(index: 0, offset: 0, rotation: -5)
            }
            if photos.count >= 2 {
                photoView(index: 1, offset: 4, rotation: 0)
            }
            if photos.count >= 3 {
                photoView(index: 2, offset: 8, rotation: 5)
            }

            // 照片数量角标
            if photos.count > 3 {
                Text("+\(photos.count - 3)")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .offset(x: size / 2 - 8, y: size / 2 - 8)
            }
        }
    }

    private func photoView(index: Int, offset: CGFloat, rotation: Double) -> some View {
        Rectangle()
            .fill(photoColor(for: index))
            .frame(width: size - offset * 2, height: size - offset * 2)
            .cornerRadius(6)
            .rotationEffect(.degrees(rotation))
            .offset(x: offset, y: -offset)
    }

    private func photoColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .pink, .purple]
        return colors[index % colors.count]
    }
}

// MARK: - 统计摘要视图

struct StatsSummaryView: View {
    let statistics: GroupingStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分组统计")
                .font(.headline)

            HStack(spacing: 20) {
                StatItemView(value: "\(statistics.groupCount)",
                            label: "分组",
                            icon: "square.grid.2x2")

                Divider()
                    .frame(height: 40)

                StatItemView(value: "\(statistics.photosInGroups)",
                            label: "已分组",
                            icon: "photo")

                Divider()
                    .frame(height: 40)

                StatItemView(value: "\(Int(statistics.coverageRate * 100))%",
                            label: "覆盖率",
                            icon: "chart.pie")
            }
            .frame(maxWidth: .infinity)

            if statistics.largestGroupSize > 0 {
                Text("最大分组: \(statistics.largestGroupSize)张照片")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatItemView: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 筛选选项

enum GroupFilterOption: String, CaseIterable {
    case all = "全部"
    case smallGroups = "小组 (≤5张)"
    case largeGroups = "大组 (>5张)"
    case recent = "最近7天"
}

struct FilterOptionsView: View {
    @Binding var selectedOption: GroupFilterOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(GroupFilterOption.allCases, id: \.self) { option in
                HStack {
                    Text(option.rawValue)
                    Spacer()
                    if option == selectedOption {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedOption = option
                    dismiss()
                }
            }
            .navigationTitle("筛选分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 颜色扩展

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - 预览

struct GroupListView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = GroupingViewModel()
        let recommendationViewModel = RecommendationViewModel()

        return GroupListView(viewModel: viewModel,
                           recommendationViewModel: recommendationViewModel)
    }
}