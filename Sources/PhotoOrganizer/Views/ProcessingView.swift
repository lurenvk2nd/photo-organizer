import SwiftUI
import Photos

/// 处理视图，批量处理用户选择
struct ProcessingView: View {
    @ObservedObject var groupingViewModel: GroupingViewModel
    @ObservedObject var recommendationViewModel: RecommendationViewModel
    @State private var showingDeleteConfirmation = false
    @State private var showingClearConfirmation = false
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var processingStage: ProcessingStage = .idle
    @State private var processingError: String?
    @State private var processingResult: ProcessingResult?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 处理统计
                    ProcessingStatsView(groupingViewModel: groupingViewModel)

                    // 待处理列表
                    if hasPendingSelections {
                        PendingGroupsView(groupingViewModel: groupingViewModel,
                                         recommendationViewModel: recommendationViewModel)
                    }

                    // 处理控制
                    ProcessingControlsView(
                        hasPendingSelections: hasPendingSelections,
                        isProcessing: isProcessing,
                        processingStage: processingStage,
                        onDelete: { showingDeleteConfirmation = true },
                        onClear: { showingClearConfirmation = true },
                        onProcess: { startProcessing() }
                    )

                    // 处理进度
                    if isProcessing {
                        ProcessingProgressView(
                            progress: progress,
                            stage: processingStage,
                            error: processingError
                        )
                    }

                    // 处理结果
                    if let result = processingResult {
                        ProcessingResultView(result: result)
                    }

                    // 使用说明
                    ProcessingInstructionsView()
                }
                .padding()
            }
            .navigationTitle("批量处理")
            .alert("确认删除", isPresented: $showingDeleteConfirmation) {
                Button("取消", role: .cancel) { }
                Button("确认删除", role: .destructive) {
                    performDeletion()
                }
            } message: {
                Text("将删除所有标记为删除的照片，此操作不可撤销。")
            }
            .alert("清空选择", isPresented: $showingClearConfirmation) {
                Button("取消", role: .cancel) { }
                Button("确认清空", role: .destructive) {
                    clearAllSelections()
                }
            } message: {
                Text("将清空所有选择记录，此操作不可撤销。")
            }
            .alert("处理错误", isPresented: .constant(processingError != nil)) {
                Button("确定") {
                    processingError = nil
                }
            } message: {
                Text(processingError ?? "")
            }
        }
    }

    // MARK: - 计算属性

    private var hasPendingSelections: Bool {
        return groupingViewModel.photoGroups.count > 0
    }

    // MARK: - 处理方法

    private func startProcessing() {
        guard !isProcessing else { return }

        isProcessing = true
        progress = 0
        processingStage = .preparing
        processingError = nil
        processingResult = nil

        Task {
            await performProcessing()
        }
    }

    private func performProcessing() async {
        // 模拟处理过程
        for stage in ProcessingStage.allCases.dropFirst() { // 跳过.idle
            await updateProcessingStage(stage)

            // 模拟处理时间
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒

            if stage == .completed {
                await completeProcessing()
                break
            }
        }
    }

    @MainActor
    private func updateProcessingStage(_ stage: ProcessingStage) {
        processingStage = stage
        progress = stage.progress
    }

    @MainActor
    private func completeProcessing() {
        isProcessing = false

        // 创建处理结果
        let stats = groupingViewModel.statistics
        processingResult = ProcessingResult(
            totalProcessed: stats.photosInGroups,
            keptCount: 0, // 实际应该从UserSelection中获取
            deletedCount: 0,
            spaceSaved: "约100MB",
            processingTime: "1分钟",
            completedDate: Date()
        )

        // 清空分组（模拟处理完成）
        groupingViewModel.clearAllGroups()
    }

    private func performDeletion() {
        // 这里应该实际执行删除操作
        // 注意：删除照片是敏感操作，需要明确提示用户
        print("执行删除操作")

        // 模拟删除
        groupingViewModel.clearAllGroups()
    }

    private func clearAllSelections() {
        groupingViewModel.clearAllGroups()
        recommendationViewModel.clearCache()
    }
}

// MARK: - 处理统计视图

struct ProcessingStatsView: View {
    @ObservedObject var groupingViewModel: GroupingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("处理统计")
                .font(.headline)

            if groupingViewModel.photoGroups.isEmpty {
                EmptyStatsView()
            } else {
                GroupStatsView(statistics: groupingViewModel.statistics)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EmptyStatsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("所有照片已处理完成")
                .font(.headline)

            Text("没有待处理的照片分组")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct GroupStatsView: View {
    let statistics: GroupingStatistics

    var body: some View {
        HStack(spacing: 0) {
            StatItemView(
                value: "\(statistics.groupCount)",
                label: "待处理分组",
                icon: "square.grid.2x2",
                color: .blue
            )

            Divider()
                .frame(height: 40)

            StatItemView(
                value: "\(statistics.photosInGroups)",
                label: "待处理照片",
                icon: "photo",
                color: .green
            )

            Divider()
                .frame(height: 40)

            StatItemView(
                value: "\(Int(statistics.coverageRate * 100))%",
                label: "覆盖率",
                icon: "chart.pie",
                color: .orange
            )
        }
    }
}

struct StatItemView: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(color)

                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 待处理分组视图

struct PendingGroupsView: View {
    @ObservedObject var groupingViewModel: GroupingViewModel
    @ObservedObject var recommendationViewModel: RecommendationViewModel
    @State private var expandedGroupId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("待处理分组")
                .font(.headline)

            ForEach(groupingViewModel.photoGroups.prefix(5)) { group in
                PendingGroupRow(
                    group: group,
                    isExpanded: expandedGroupId == group.id,
                    onTap: {
                        withAnimation {
                            expandedGroupId = expandedGroupId == group.id ? nil : group.id
                        }
                    }
                )
            }

            if groupingViewModel.photoGroups.count > 5 {
                Text("还有 \(groupingViewModel.photoGroups.count - 5) 个分组...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PendingGroupRow: View {
    let group: PhotoGroup
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // 分组信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.description)
                        .font(.subheadline)
                        .lineLimit(1)

                    Text("\(group.photos.count)张照片")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 展开箭头
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .padding(.vertical, 8)

            // 展开内容
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("照片预览")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 照片预览网格
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(group.photos.prefix(10), id: \.localIdentifier) { asset in
                                Rectangle()
                                    .fill(photoColor(for: asset))
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(4)
                            }

                            if group.photos.count > 10 {
                                Text("+\(group.photos.count - 10)")
                                    .font(.caption2)
                                    .frame(width: 40, height: 40)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func photoColor(for asset: PHAsset) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple]
        let index = abs(asset.localIdentifier.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - 处理控制视图

struct ProcessingControlsView: View {
    let hasPendingSelections: Bool
    let isProcessing: Bool
    let processingStage: ProcessingStage
    let onDelete: () -> Void
    let onClear: () -> Void
    let onProcess: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if hasPendingSelections {
                // 处理按钮
                Button(action: onProcess) {
                    Label(
                        isProcessing ? "正在处理..." : "开始处理",
                        systemImage: isProcessing ? "gear" : "play.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isProcessing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isProcessing)
            }

            HStack(spacing: 12) {
                // 删除按钮
                Button(action: onDelete) {
                    Label("删除照片", systemImage: "trash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }

                // 清空按钮
                Button(action: onClear) {
                    Label("清空选择", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - 处理进度视图

struct ProcessingProgressView: View {
    let progress: Double
    let stage: ProcessingStage
    let error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("处理进度")
                .font(.headline)

            VStack(spacing: 12) {
                // 进度条
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)

                // 阶段信息
                HStack {
                    Text(stage.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                // 错误信息
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 处理结果视图

struct ProcessingResultView: View {
    let result: ProcessingResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("处理完成")
                .font(.headline)

            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    ResultItemView(
                        value: "\(result.totalProcessed)",
                        label: "处理照片",
                        icon: "photo",
                        color: .blue
                    )

                    Divider()
                        .frame(height: 40)

                    ResultItemView(
                        value: "\(result.keptCount)",
                        label: "保留照片",
                        icon: "checkmark.circle",
                        color: .green
                    )

                    Divider()
                        .frame(height: 40)

                    ResultItemView(
                        value: "\(result.deletedCount)",
                        label: "删除照片",
                        icon: "trash",
                        color: .red
                    )
                }

                // 空间节省
                HStack {
                    Image(systemName: "externaldrive")
                        .foregroundColor(.orange)

                    Text("节省空间: \(result.spaceSaved)")
                        .font(.subheadline)

                    Spacer()

                    Text("处理时间: \(result.processingTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green, lineWidth: 1)
        )
    }
}

struct ResultItemView: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)

                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 使用说明视图

struct ProcessingInstructionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用说明")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                InstructionItemView(
                    icon: "1.circle",
                    title: "选择照片",
                    description: "在推荐页面为每张照片选择保留或删除"
                )

                InstructionItemView(
                    icon: "2.circle",
                    title: "批量处理",
                    description: "在此页面查看所有待处理的分组"
                )

                InstructionItemView(
                    icon: "3.circle",
                    title: "执行操作",
                    description: "确认无误后执行删除操作"
                )

                InstructionItemView(
                    icon: "4.circle",
                    title: "查看结果",
                    description: "处理完成后查看清理统计"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct InstructionItemView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 数据结构

enum ProcessingStage: CaseIterable {
    case idle
    case preparing
    case analyzing
    case processing
    case cleaning
    case completed

    var description: String {
        switch self {
        case .idle: return "准备中"
        case .preparing: return "准备处理"
        case .analyzing: return "分析选择"
        case .processing: return "处理照片"
        case .cleaning: return "清理数据"
        case .completed: return "处理完成"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0
        case .preparing: return 0.1
        case .analyzing: return 0.3
        case .processing: return 0.6
        case .cleaning: return 0.9
        case .completed: return 1.0
        }
    }
}

struct ProcessingResult {
    let totalProcessed: Int
    let keptCount: Int
    let deletedCount: Int
    let spaceSaved: String
    let processingTime: String
    let completedDate: Date
}

// MARK: - 预览

struct ProcessingView_Previews: PreviewProvider {
    static var previews: some View {
        let groupingViewModel = GroupingViewModel()
        let recommendationViewModel = RecommendationViewModel()

        return ProcessingView(
            groupingViewModel: groupingViewModel,
            recommendationViewModel: recommendationViewModel
        )
    }
}