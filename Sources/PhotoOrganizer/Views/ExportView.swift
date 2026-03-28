import SwiftUI
import Photos

/// 导出视图，支持导出分组结果和统计信息
struct ExportView: View {
    let groups: [PhotoGroup]
    let statistics: GroupingStatistics
    @Environment(\.dismiss) private var dismiss
    @State private var exportFormat: ExportFormat = .json
    @State private var includePhotos: Bool = false
    @State private var compressionQuality: Double = 0.8
    @State private var isExporting: Bool = false
    @State private var exportProgress: Double = 0
    @State private var exportError: String?
    @State private var exportResult: ExportResult?
    @State private var showingShareSheet: Bool = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationView {
            Form {
                // 导出统计
                exportStatsSection

                // 导出设置
                exportSettingsSection

                // 导出操作
                exportActionsSection

                // 导出结果
                if let result = exportResult {
                    exportResultSection(result: result)
                }
            }
            .navigationTitle("导出分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("导出错误", isPresented: .constant(exportError != nil)) {
                Button("确定") {
                    exportError = nil
                }
            } message: {
                Text(exportError ?? "")
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    // MARK: - 导出统计

    private var exportStatsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("导出统计")
                    .font(.headline)

                HStack(spacing: 16) {
                    StatItemView(
                        value: "\(statistics.groupCount)",
                        label: "分组数量",
                        icon: "square.grid.2x2"
                    )

                    StatItemView(
                        value: "\(statistics.photosInGroups)",
                        label: "照片数量",
                        icon: "photo"
                    )

                    StatItemView(
                        value: "\(Int(statistics.coverageRate * 100))%",
                        label: "覆盖率",
                        icon: "chart.pie"
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 导出设置

    private var exportSettingsSection: some View {
        Section {
            // 导出格式
            Picker("导出格式", selection: $exportFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }

            // 包含照片
            Toggle("包含照片", isOn: $includePhotos)
                .disabled(exportFormat == .json)

            if includePhotos && exportFormat != .json {
                // 压缩质量
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("压缩质量")
                        Spacer()
                        Text("\(Int(compressionQuality * 100))%")
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $compressionQuality, in: 0.3...1.0, step: 0.1) {
                        Text("压缩质量")
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("导出设置")
        } footer: {
            Text(exportFormat.description)
        }
    }

    // MARK: - 导出操作

    private var exportActionsSection: some View {
        Section {
            if isExporting {
                // 导出进度
                VStack(alignment: .leading, spacing: 12) {
                    Text("正在导出...")
                        .font(.headline)

                    ProgressView(value: exportProgress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(exportStageDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(exportProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .padding(.vertical, 4)
            } else {
                // 导出按钮
                Button(action: startExport) {
                    Label("开始导出", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(groups.isEmpty)
            }
        } footer: {
            if groups.isEmpty {
                Text("没有可导出的分组数据")
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - 导出结果

    private func exportResultSection(result: ExportResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("导出完成")
                    .font(.headline)

                ResultItemView(
                    icon: "checkmark.circle.fill",
                    title: "导出成功",
                    value: result.fileName,
                    color: .green
                )

                ResultItemView(
                    icon: "doc",
                    title: "文件大小",
                    value: result.fileSize,
                    color: .blue
                )

                ResultItemView(
                    icon: "clock",
                    title: "导出时间",
                    value: result.exportTime,
                    color: .orange
                )

                HStack(spacing: 12) {
                    // 分享按钮
                    Button(action: {
                        exportURL = result.fileURL
                        showingShareSheet = true
                    }) {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }

                    // 重新导出按钮
                    Button(action: {
                        exportResult = nil
                    }) {
                        Label("重新导出", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 导出阶段描述

    private var exportStageDescription: String {
        let progress = exportProgress
        if progress < 0.2 {
            return "准备数据..."
        } else if progress < 0.5 {
            return "处理分组信息..."
        } else if progress < 0.8 {
            return "生成导出文件..."
        } else if progress < 1.0 {
            return "保存文件..."
        } else {
            return "导出完成"
        }
    }

    // MARK: - 导出方法

    private func startExport() {
        guard !groups.isEmpty else { return }

        isExporting = true
        exportProgress = 0
        exportError = nil
        exportResult = nil

        Task {
            await performExport()
        }
    }

    private func performExport() async {
        // 模拟导出过程
        let totalStages = 5
        for stage in 1...totalStages {
            await updateExportProgress(Double(stage) / Double(totalStages))

            // 模拟处理时间
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

            if stage == totalStages {
                await completeExport()
            }
        }
    }

    @MainActor
    private func updateExportProgress(_ progress: Double) {
        exportProgress = progress
    }

    @MainActor
    private func completeExport() {
        isExporting = false

        // 创建导出结果
        let fileName = "照片分组_\(Date().formatted(date: .numeric, time: .shortened)).\(exportFormat.fileExtension)"
        let fileSize = estimateFileSize()

        exportResult = ExportResult(
            fileName: fileName,
            fileSize: fileSize,
            fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"), // 临时URL
            exportFormat: exportFormat,
            exportTime: Date().formatted(date: .omitted, time: .shortened),
            includedPhotos: includePhotos,
            groupCount: groups.count,
            photoCount: statistics.photosInGroups
        )
    }

    private func estimateFileSize() -> String {
        let baseSize = Double(groups.count) * 2.0 // 每组约2KB元数据
        var totalSize = baseSize

        if includePhotos {
            // 假设每张照片压缩后平均200KB
            totalSize += Double(statistics.photosInGroups) * 200.0
        }

        if totalSize < 1024 {
            return "\(Int(totalSize)) KB"
        } else {
            let mb = totalSize / 1024
            return String(format: "%.1f MB", mb)
        }
    }
}

// MARK: - 统计项视图

struct StatItemView: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.blue)

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

// MARK: - 结果项视图

struct ResultItemView: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
            }

            Spacer()
        }
    }
}

// MARK: - 导出格式

enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case csv = "CSV"
    case plist = "Property List"

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        case .plist: return "plist"
        }
    }

    var description: String {
        switch self {
        case .json:
            return "JSON格式，适合程序读取和交换数据"
        case .csv:
            return "CSV格式，适合在表格软件中查看"
        case .plist:
            return "Property List格式，适合macOS/iOS应用"
        }
    }
}

// MARK: - 导出结果

struct ExportResult {
    let fileName: String
    let fileSize: String
    let fileURL: URL
    let exportFormat: ExportFormat
    let exportTime: String
    let includedPhotos: Bool
    let groupCount: Int
    let photoCount: Int

    var summary: String {
        var parts = ["\(groupCount)个分组", "\(photoCount)张照片"]
        if includedPhotos {
            parts.append("包含照片")
        }
        parts.append(fileSize)
        return parts.joined(separator: " · ")
    }
}

// MARK: - 分享Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 不需要更新
    }
}

// MARK: - 导出数据结构

struct GroupingExportData: Codable {
    let groups: [ExportPhotoGroup]
    let statistics: ExportStatistics
    let exportDate: Date
    let exportFormat: String

    struct ExportPhotoGroup: Codable {
        let id: String
        let photoCount: Int
        let creationDate: Date?
        let location: ExportLocation?
        let groupReason: String
        let timeRange: TimeInterval?
        let description: String

        struct ExportLocation: Codable {
            let latitude: Double
            let longitude: Double
        }
    }

    struct ExportStatistics: Codable {
        let totalPhotos: Int
        let groupCount: Int
        let photosInGroups: Int
        let averageGroupSize: Double
        let coverageRate: Double
    }

    /// 转换为JSON字符串
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// 转换为CSV字符串
    func toCSVString() -> String {
        var csv = "分组ID,照片数量,创建时间,位置,分组原因,时间范围,描述\n"

        for group in groups {
            let dateString = group.creationDate?.formatted(date: .numeric, time: .shortened) ?? ""
            let locationString = group.location != nil ? "有位置" : "无位置"
            let timeRangeString = group.timeRange != nil ? "\(Int(group.timeRange!))秒" : ""

            csv += "\"\(group.id)\","
            csv += "\(group.photoCount),"
            csv += "\"\(dateString)\","
            csv += "\"\(locationString)\","
            csv += "\"\(group.groupReason)\","
            csv += "\"\(timeRangeString)\","
            csv += "\"\(group.description)\"\n"
        }

        return csv
    }
}

// MARK: - 预览

struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        let groups: [PhotoGroup] = []
        let statistics = GroupingStatistics()

        return ExportView(groups: groups, statistics: statistics)
    }
}