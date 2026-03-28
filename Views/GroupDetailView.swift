import SwiftUI
import Photos

/// 分组详情视图，显示组内照片和推荐
struct GroupDetailView: View {
    let group: PhotoGroup
    @ObservedObject var viewModel: RecommendationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingRecommendationDetail = false
    @State private var selectedPhotoId: String?
    @State private var selectionMode: SelectionMode = .single
    @State private var selectedPhotoIds: Set<String> = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // 头部信息
                    GroupHeaderView(group: group)

                    // 推荐摘要
                    RecommendationSummaryView(viewModel: viewModel)
                        .padding(.horizontal)
                        .padding(.top)

                    // 照片网格
                    PhotoGridView(group: group,
                                viewModel: viewModel,
                                selectedPhotoId: $selectedPhotoId,
                                selectionMode: $selectionMode,
                                selectedPhotoIds: $selectedPhotoIds)
                        .padding(.horizontal)

                    // 选择统计
                    SelectionStatsView(viewModel: viewModel)
                        .padding()
                }
            }
            .navigationTitle("分组详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    selectionModeButton
                    recommendationButton
                }
            }
            .sheet(isPresented: $showingRecommendationDetail) {
                if let photoId = selectedPhotoId {
                    RecommendationDetailView(photoId: photoId,
                                           viewModel: viewModel)
                }
            }
            .onAppear {
                Task {
                    await viewModel.generateRecommendations(for: group)
                }
            }
            .onChange(of: selectedPhotoId) { newValue in
                if newValue != nil {
                    showingRecommendationDetail = true
                }
            }
        }
    }

    // MARK: - 工具栏按钮

    private var selectionModeButton: some View {
        Button(action: {
            withAnimation {
                selectionMode = selectionMode == .single ? .multiple : .single
                if selectionMode == .single {
                    selectedPhotoIds.removeAll()
                }
            }
        }) {
            Image(systemName: selectionMode.icon)
                .foregroundColor(selectionMode == .multiple ? .blue : .primary)
        }
    }

    private var recommendationButton: some View {
        Button(action: {
            if viewModel.isAutoAcceptAvailable {
                viewModel.acceptRecommendation()
            }
        }) {
            Image(systemName: "sparkles")
                .foregroundColor(viewModel.isAutoAcceptAvailable ? .blue : .gray)
        }
        .disabled(!viewModel.isAutoAcceptAvailable)
    }
}

// MARK: - 分组头部视图

struct GroupHeaderView: View {
    let group: PhotoGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分组描述
            Text(group.description)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.leading)

            // 分组信息
            HStack(spacing: 16) {
                InfoItemView(icon: "photo",
                            value: "\(group.photos.count)张",
                            label: "照片数量")

                if let timeRange = group.timeRange, timeRange > 0 {
                    InfoItemView(icon: "clock",
                                value: formatTimeRange(timeRange),
                                label: "时间范围")
                }

                if let location = group.location {
                    InfoItemView(icon: "location",
                                value: "有位置",
                                label: "地理位置")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }

    private func formatTimeRange(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))秒"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))分"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))小时"
        } else {
            return "\(Int(seconds / 86400))天"
        }
    }
}

struct InfoItemView: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 推荐摘要视图

struct RecommendationSummaryView: View {
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("智能推荐")
                .font(.headline)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if !viewModel.photoScores.isEmpty {
                // 推荐层级展示
                HStack(spacing: 12) {
                    ForEach(PhotoScore.RecommendationLevel.allCases, id: \.self) { level in
                        RecommendationLevelView(level: level,
                                              count: viewModel.recommendations[level]?.count ?? 0)
                    }
                }

                // 一键接受预览
                if let preview = viewModel.autoAcceptPreview {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("一键接受推荐")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(preview.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("正在分析照片质量...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecommendationLevelView: View {
    let level: PhotoScore.RecommendationLevel
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Color(hex: level.colorHex))
                .frame(width: 24, height: 24)
                .overlay(
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )

            Text(level.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 60)
    }
}

// MARK: - 照片网格视图

struct PhotoGridView: View {
    let group: PhotoGroup
    @ObservedObject var viewModel: RecommendationViewModel
    @Binding var selectedPhotoId: String?
    @Binding var selectionMode: SelectionMode
    @Binding var selectedPhotoIds: Set<String>

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(group.photos, id: \.localIdentifier) { asset in
                PhotoGridItemView(asset: asset,
                                viewModel: viewModel,
                                selectionMode: selectionMode,
                                isSelected: selectedPhotoIds.contains(asset.localIdentifier),
                                onTap: {
                    handlePhotoTap(asset.localIdentifier)
                })
                .id(asset.localIdentifier)
            }
        }
        .padding(.top)
    }

    private func handlePhotoTap(_ photoId: String) {
        if selectionMode == .single {
            selectedPhotoId = photoId
        } else {
            if selectedPhotoIds.contains(photoId) {
                selectedPhotoIds.remove(photoId)
            } else {
                selectedPhotoIds.insert(photoId)
            }
        }
    }
}

struct PhotoGridItemView: View {
    let asset: PHAsset
    @ObservedObject var viewModel: RecommendationViewModel
    let selectionMode: SelectionMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 照片缩略图
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fill)
                .overlay(
                    // 这里应该显示实际照片缩略图
                    // 简化实现：显示颜色块
                    photoColor
                )

            // 推荐层级标签
            if let level = viewModel.getRecommendationLevel(for: asset.localIdentifier) {
                LevelTagView(level: level)
                    .padding(4)
            }

            // 选择状态
            if selectionMode == .multiple {
                SelectionIndicator(isSelected: isSelected)
                    .padding(8)
            }

            // 选择状态指示器（单选模式）
            if selectionMode == .single {
                let status = viewModel.userSelection.selectionStatus(for: asset.localIdentifier)
                SelectionStatusIndicator(status: status)
                    .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private var photoColor: some View {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .pink]
        let index = Int(asset.localIdentifier.hashValue) % colors.count
        return colors[index]
            .opacity(0.7)
    }
}

struct LevelTagView: View {
    let level: PhotoScore.RecommendationLevel

    var body: some View {
        Text(level.rawValue.prefix(2))
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: level.colorHex))
            .foregroundColor(.white)
            .cornerRadius(4)
    }
}

struct SelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? Color.blue : Color.white.opacity(0.8))
            .frame(width: 24, height: 24)
            .overlay(
                Group {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            )
            .shadow(radius: 1)
    }
}

struct SelectionStatusIndicator: View {
    let status: SelectionStatus

    var body: some View {
        Circle()
            .fill(Color(hex: status.color))
            .frame(width: 16, height: 16)
            .overlay(
                Image(systemName: status.icon)
                    .font(.caption2)
                    .foregroundColor(.white)
            )
    }
}

// MARK: - 选择统计视图

struct SelectionStatsView: View {
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        VStack(spacing: 12) {
            let stats = viewModel.getSelectionStatistics()

            // 统计摘要
            HStack(spacing: 20) {
                StatItemView(value: "\(stats.keptCount)",
                            label: "保留",
                            color: .green)

                StatItemView(value: "\(stats.deletedCount)",
                            label: "删除",
                            color: .red)

                StatItemView(value: "\(Int(stats.cleanupRate * 100))%",
                            label: "清理率",
                            color: .blue)

                if !stats.spaceSaved.isEmpty {
                    StatItemView(value: stats.spaceSaved,
                                label: "节省空间",
                                color: .orange)
                }
            }

            // 确认按钮
            Button(action: {
                if let result = viewModel.confirmSelection() {
                    // 处理完成，可以关闭页面
                }
            }) {
                Text("确认选择")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(viewModel.isSelectionValid ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(!viewModel.isSelectionValid)
            .padding(.top, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StatItemView: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 选择模式

enum SelectionMode {
    case single
    case multiple

    var icon: String {
        switch self {
        case .single: return "checkmark.circle"
        case .multiple: return "checkmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .single: return "单选模式"
        case .multiple: return "多选模式"
        }
    }
}

// MARK: - 预览

struct GroupDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let group = PhotoGroup(
            photos: [],
            creationDate: Date(),
            location: nil,
            groupReason: .combined
        )
        let viewModel = RecommendationViewModel()

        return GroupDetailView(group: group, viewModel: viewModel)
    }
}