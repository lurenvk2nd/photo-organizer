import SwiftUI
import Photos

/// 推荐详情视图，显示单张照片的详细推荐信息
struct RecommendationDetailView: View {
    let photoId: String
    @ObservedObject var viewModel: RecommendationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingActionSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // 照片预览
                    PhotoPreviewView(photoId: photoId, viewModel: viewModel)
                        .frame(height: 300)

                    // 推荐信息
                    RecommendationInfoView(photoId: photoId, viewModel: viewModel)
                        .padding()

                    // 评分详情
                    ScoreDetailsView(photoId: photoId, viewModel: viewModel)
                        .padding(.horizontal)

                    // 操作按钮
                    ActionButtonsView(photoId: photoId, viewModel: viewModel)
                        .padding()
                }
            }
            .navigationTitle("推荐详情")
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

// MARK: - 照片预览

struct PhotoPreviewView: View {
    let photoId: String
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        ZStack {
            // 背景
            Color.black

            // 照片预览（简化实现）
            Rectangle()
                .fill(photoColor)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))

                        Text("照片预览")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 8)
                    }
                )

            // 推荐层级标签
            if let level = viewModel.getRecommendationLevel(for: photoId) {
                VStack {
                    RecommendationLevelBadge(level: level)
                        .padding(.top, 16)
                    Spacer()
                }
            }

            // 选择状态
            VStack {
                Spacer()
                SelectionStatusBadge(photoId: photoId, viewModel: viewModel)
                    .padding(.bottom, 16)
            }
        }
    }

    private var photoColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple]
        let index = abs(photoId.hashValue) % colors.count
        return colors[index]
    }
}

struct RecommendationLevelBadge: View {
    let level: PhotoScore.RecommendationLevel

    var body: some View {
        Text(level.rawValue)
            .font(.headline)
            .fontWeight(.bold)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(hex: level.colorHex).opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(20)
    }
}

struct SelectionStatusBadge: View {
    let photoId: String
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        let status = viewModel.userSelection.selectionStatus(for: photoId)

        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: status.color))
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(20)
    }

    private var statusText: String {
        let status = viewModel.userSelection.selectionStatus(for: photoId)
        switch status {
        case .kept:
            return "已标记为保留"
        case .deleted:
            return "已标记为删除"
        case .unselected:
            return "未选择"
        }
    }
}

// MARK: - 推荐信息

struct RecommendationInfoView: View {
    let photoId: String
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 推荐理由
            let reasons = viewModel.getRecommendationReasons(for: photoId)
            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("推荐理由")
                        .font(.headline)

                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)

                            Text(reason)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // 推荐层级说明
            if let level = viewModel.getRecommendationLevel(for: photoId) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("推荐层级")
                        .font(.headline)

                    Text(level.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, reasons.isEmpty ? 0 : 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 评分详情

struct ScoreDetailsView: View {
    let photoId: String
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("质量评估")
                .font(.headline)

            if let score = viewModel.photoScores.first(where: { $0.id == photoId }) {
                // 总分
                VStack(alignment: .leading, spacing: 8) {
                    Text("综合评分")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("\(Int(score.totalScore * 100))")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(scoreColor(score.totalScore))

                        Text("/100")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        Spacer()

                        // 总分进度条
                        ScoreProgressView(value: score.totalScore, color: scoreColor(score.totalScore))
                            .frame(width: 100)
                    }
                }

                // 各维度评分
                VStack(alignment: .leading, spacing: 12) {
                    Text("各维度评估")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScoreDimensionView(label: "清晰度",
                                      value: score.clarityScore,
                                      icon: "camera.aperture")

                    ScoreDimensionView(label: "主体完整性",
                                      value: score.subjectCompleteness,
                                      icon: "person.crop.rectangle")

                    if let eyesOpen = score.eyesOpenScore {
                        ScoreDimensionView(label: "人物状态",
                                          value: eyesOpen,
                                          icon: "eye")
                    }

                    ScoreDimensionView(label: "构图稳定性",
                                      value: score.compositionStability,
                                      icon: "square.grid.3x3")

                    if score.duplicateScore > 0.3 {
                        ScoreDimensionView(label: "重复度",
                                          value: score.duplicateScore,
                                          icon: "doc.on.doc",
                                          isReversed: true) // 重复度越低越好
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func scoreColor(_ score: Float) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .yellow
        } else if score >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

struct ScoreProgressView: View {
    let value: Float
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)

                // 进度
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(value),
                           height: 8)
            }
        }
        .frame(height: 8)
    }
}

struct ScoreDimensionView: View {
    let label: String
    let value: Float
    let icon: String
    var isReversed: Bool = false

    var body: some View {
        HStack {
            // 图标
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            // 标签
            Text(label)
                .font(.body)

            Spacer()

            // 分数
            Text("\(Int(value * 100))")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(scoreColor(value, isReversed: isReversed))
                .frame(width: 40, alignment: .trailing)

            // 进度条
            ScoreProgressView(value: value, color: scoreColor(value, isReversed: isReversed))
                .frame(width: 80)
        }
    }

    private func scoreColor(_ value: Float, isReversed: Bool = false) -> Color {
        let adjustedValue = isReversed ? 1.0 - value : value

        if adjustedValue >= 0.8 {
            return .green
        } else if adjustedValue >= 0.6 {
            return .yellow
        } else if adjustedValue >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - 操作按钮

struct ActionButtonsView: View {
    let photoId: String
    @ObservedObject var viewModel: RecommendationViewModel
    @State private var showingConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            // 当前状态
            let status = viewModel.userSelection.selectionStatus(for: photoId)

            HStack(spacing: 16) {
                // 保留按钮
                ActionButton(
                    title: "保留",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    isSelected: status == .kept,
                    action: { viewModel.selectPhoto(photoId, for: .keep) }
                )

                // 删除按钮
                ActionButton(
                    title: "删除",
                    icon: "trash.circle.fill",
                    color: .red,
                    isSelected: status == .deleted,
                    action: { viewModel.selectPhoto(photoId, for: .delete) }
                )
            }

            // 切换按钮
            Button(action: {
                viewModel.selectPhoto(photoId, for: .toggle)
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("切换选择")
                }
                .font(.subheadline)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .foregroundColor(.primary)
                .cornerRadius(8)
            }
            .padding(.top, 4)
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? color : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
            .cornerRadius(10)
        }
    }
}

// MARK: - 预览

struct RecommendationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = RecommendationViewModel()

        // 创建测试数据
        let testPhotoId = "test-photo-id"

        return RecommendationDetailView(photoId: testPhotoId, viewModel: viewModel)
    }
}