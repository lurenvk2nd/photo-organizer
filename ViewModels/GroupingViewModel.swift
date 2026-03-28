import Foundation
import Photos
import Combine

/// 分组视图模型，管理照片分组的状态和逻辑
@MainActor
class GroupingViewModel: ObservableObject {
    // MARK: - 发布属性

    @Published var photoGroups: [PhotoGroup] = []
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    @Published var selectedGroup: PhotoGroup?
    @Published var statistics: GroupingStatistics = .init()

    // MARK: - 私有属性

    private let groupingService = GroupingService()
    private let photoAnalyzer = PhotoAnalyzer()
    private var cancellables = Set<AnyCancellable>()
    private var allPhotos: [PHAsset] = []
    private var processedPhotoIds: Set<String> = []

    // MARK: - 初始化

    init() {
        setupBindings()
    }

    // MARK: - 公共方法

    /// 开始照片分组
    func startGrouping() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        progress = 0

        do {
            // 1. 请求照片库权限
            try await requestPhotoLibraryAuthorization()

            // 2. 加载照片
            progress = 0.1
            allPhotos = try await loadPhotos()
            statistics.totalPhotos = allPhotos.count

            // 3. 过滤已处理照片
            progress = 0.2
            let unprocessedPhotos = filterUnprocessedPhotos(allPhotos)
            statistics.processedPhotos = allPhotos.count - unprocessedPhotos.count

            guard !unprocessedPhotos.isEmpty else {
                errorMessage = "所有照片都已处理完成"
                isLoading = false
                return
            }

            // 4. 计算分组配置
            progress = 0.3
            let config = groupingService.suggestedConfig(for: unprocessedPhotos.count)

            // 5. 执行分组
            progress = 0.4
            let groups = await groupingService.autoGroup(photos: unprocessedPhotos, config: config)
            photoGroups = groups

            // 6. 更新统计信息
            updateStatistics(groups: groups)
            progress = 1.0

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 重新分组指定照片
    func regroup(photos: [PHAsset]) async {
        guard !isLoading else { return }

        isLoading = true

        do {
            let updatedGroups = await groupingService.regroup(photos: photos, existingGroups: photoGroups)
            photoGroups = updatedGroups
            updateStatistics(groups: updatedGroups)
        } catch {
            errorMessage = "重新分组失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// 从组中移除照片
    func removePhotosFromGroup(_ photos: [PHAsset], from groupId: UUID) {
        guard let groupIndex = photoGroups.firstIndex(where: { $0.id == groupId }) else {
            return
        }

        var updatedGroup = photoGroups[groupIndex]
        updatedGroup.photos = updatedGroup.photos.filter { !photos.contains($0) }

        if updatedGroup.photos.isEmpty {
            // 如果组为空，删除整个组
            photoGroups.remove(at: groupIndex)
        } else {
            // 否则更新组
            photoGroups[groupIndex] = updatedGroup
        }

        updateStatistics(groups: photoGroups)
    }

    /// 清空所有分组
    func clearAllGroups() {
        photoGroups.removeAll()
        statistics = .init()
    }

    /// 获取组内的照片数量分布
    func getGroupSizeDistribution() -> [Int: Int] {
        var distribution: [Int: Int] = [:]

        for group in photoGroups {
            let size = group.photos.count
            distribution[size, default: 0] += 1
        }

        return distribution
    }

    /// 导出分组结果
    func exportGroupingResults() -> GroupingExportData {
        return GroupingExportData(
            groups: photoGroups,
            statistics: statistics,
            exportDate: Date()
        )
    }

    // MARK: - 私有方法

    private func setupBindings() {
        // 监听照片组变化，更新选中状态
        $photoGroups
            .sink { [weak self] groups in
                if let selectedGroup = self?.selectedGroup,
                   !groups.contains(where: { $0.id == selectedGroup.id }) {
                    // 如果选中的组被删除，清空选中状态
                    self?.selectedGroup = nil
                }
            }
            .store(in: &cancellables)
    }

    private func requestPhotoLibraryAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if newStatus != .authorized && newStatus != .limited {
                throw GroupingError.authorizationDenied
            }
        case .denied, .restricted:
            throw GroupingError.authorizationDenied
        @unknown default:
            throw GroupingError.unknownAuthorizationStatus
        }
    }

    private func loadPhotos() async throws -> [PHAsset] {
        return try await withCheckedThrowingContinuation { continuation in
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            var assets: [PHAsset] = []

            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            continuation.resume(returning: assets)
        }
    }

    private func filterUnprocessedPhotos(_ photos: [PHAsset]) -> [PHAsset] {
        // 这里应该从Core Data加载已处理照片的ID
        // 简化实现：返回所有照片
        return photos.filter { !processedPhotoIds.contains($0.localIdentifier) }
    }

    private func updateStatistics(groups: [PhotoGroup]) {
        statistics.groupCount = groups.count
        statistics.photosInGroups = groups.reduce(0) { $0 + $1.photos.count }

        // 计算平均组大小
        if !groups.isEmpty {
            statistics.averageGroupSize = Double(statistics.photosInGroups) / Double(groups.count)
        }

        // 计算分组覆盖率
        if statistics.totalPhotos > 0 {
            statistics.coverageRate = Double(statistics.photosInGroups) / Double(statistics.totalPhotos)
        }

        // 找出最大的组
        if let largestGroup = groups.max(by: { $0.photos.count < $1.photos.count }) {
            statistics.largestGroupSize = largestGroup.photos.count
        }

        // 计算时间范围
        let allDates = groups.flatMap { $0.photos }.compactMap { $0.creationDate }
        if let earliest = allDates.min(), let latest = allDates.max() {
            statistics.timeRange = latest.timeIntervalSince(earliest)
        }
    }

    // MARK: - 用户操作处理

    /// 处理用户选择（照片被保留或删除）
    func handleUserSelection(groupId: UUID, keptPhotoIds: [String], deletedPhotoIds: [String]) {
        // 1. 更新已处理照片记录
        processedPhotoIds.formUnion(keptPhotoIds)
        processedPhotoIds.formUnion(deletedPhotoIds)

        // 2. 从分组中移除这些照片
        if let groupIndex = photoGroups.firstIndex(where: { $0.id == groupId }) {
            var updatedGroup = photoGroups[groupIndex]
            updatedGroup.photos = updatedGroup.photos.filter { asset in
                !keptPhotoIds.contains(asset.localIdentifier) &&
                !deletedPhotoIds.contains(asset.localIdentifier)
            }

            if updatedGroup.photos.isEmpty {
                photoGroups.remove(at: groupIndex)
            } else {
                photoGroups[groupIndex] = updatedGroup
            }
        }

        // 3. 更新统计
        updateStatistics(groups: photoGroups)
    }

    /// 批量处理多个组
    func batchProcessGroups(groupIds: [UUID], keepAll: Bool = false) {
        for groupId in groupIds {
            guard let group = photoGroups.first(where: { $0.id == groupId }) else {
                continue
            }

            if keepAll {
                // 保留所有照片
                let keptIds = group.photos.map { $0.localIdentifier }
                handleUserSelection(groupId: groupId,
                                  keptPhotoIds: keptIds,
                                  deletedPhotoIds: [])
            } else {
                // 删除所有照片
                let deletedIds = group.photos.map { $0.localIdentifier }
                handleUserSelection(groupId: groupId,
                                  keptPhotoIds: [],
                                  deletedPhotoIds: deletedIds)
            }
        }
    }
}

// MARK: - 数据结构

/// 分组统计信息
struct GroupingStatistics {
    var totalPhotos: Int = 0
    var processedPhotos: Int = 0
    var groupCount: Int = 0
    var photosInGroups: Int = 0
    var averageGroupSize: Double = 0
    var largestGroupSize: Int = 0
    var coverageRate: Double = 0 // 分组覆盖率
    var timeRange: TimeInterval = 0 // 时间范围（秒）

    /// 获取统计摘要
    var summary: String {
        var parts: [String] = []

        if totalPhotos > 0 {
            parts.append("总照片: \(totalPhotos)")
        }

        if groupCount > 0 {
            parts.append("分组: \(groupCount)")
            parts.append("平均大小: \(String(format: "%.1f", averageGroupSize))")
        }

        if photosInGroups > 0 {
            let coveragePercent = Int(coverageRate * 100)
            parts.append("覆盖率: \(coveragePercent)%")
        }

        return parts.joined(separator: " · ")
    }
}

/// 分组导出数据
struct GroupingExportData {
    let groups: [PhotoGroup]
    let statistics: GroupingStatistics
    let exportDate: Date

    /// 转换为JSON字符串
    func toJSON() -> String? {
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
}

// MARK: - 错误类型

enum GroupingError: LocalizedError {
    case authorizationDenied
    case photoLoadFailed
    case groupingFailed
    case unknownAuthorizationStatus

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "需要照片库访问权限"
        case .photoLoadFailed:
            return "加载照片失败"
        case .groupingFailed:
            return "照片分组失败"
        case .unknownAuthorizationStatus:
            return "未知的权限状态"
        }
    }
}

// MARK: - 扩展

extension GroupingViewModel {
    /// 获取分组进度描述
    var progressDescription: String {
        if isLoading {
            let percent = Int(progress * 100)
            return "正在分析照片... \(percent)%"
        } else if !photoGroups.isEmpty {
            return "发现 \(photoGroups.count) 个相似场景"
        } else {
            return "准备分析照片"
        }
    }

    /// 检查是否可以开始分组
    var canStartGrouping: Bool {
        return !isLoading
    }

    /// 获取推荐的处理优先级（基于组大小和重复度）
    func getProcessingPriority(for group: PhotoGroup) -> ProcessingPriority {
        let size = group.photos.count

        if size >= 10 {
            return .high // 大组优先处理
        } else if size >= 5 {
            return .medium
        } else {
            return .low
        }
    }

    enum ProcessingPriority {
        case high
        case medium
        case low

        var color: String {
            switch self {
            case .high: return "#FF5252" // 红色
            case .medium: return "#FF9800" // 橙色
            case .low: return "#4CAF50" // 绿色
            }
        }

        var description: String {
            switch self {
            case .high: return "高优先级"
            case .medium: return "中优先级"
            case .low: return "低优先级"
            }
        }
    }
}