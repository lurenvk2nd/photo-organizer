import Foundation
import Photos
import Combine

/// 推荐视图模型，管理照片推荐的状态和逻辑
@MainActor
class RecommendationViewModel: ObservableObject {
    // MARK: - 发布属性

    @Published var currentGroup: PhotoGroup?
    @Published var photoScores: [PhotoScore] = []
    @Published var recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]] = [:]
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    @Published var userSelection: UserSelectionState = .init()
    @Published var showExplanation: Bool = false
    @Published var selectedPhotoId: String?

    // MARK: - 私有属性

    private let recommendationService = RecommendationService()
    private let photoAnalyzer = PhotoAnalyzer()
    private var cancellables = Set<AnyCancellable>()
    private var allRecommendations: [UUID: (scores: [PhotoScore],
                                          recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]])] = [:]

    // MARK: - 初始化

    init() {
        setupBindings()
    }

    // MARK: - 公共方法

    /// 为指定组生成推荐
    func generateRecommendations(for group: PhotoGroup) async {
        guard !isLoading else { return }

        currentGroup = group
        isLoading = true
        errorMessage = nil
        progress = 0
        photoScores = []
        recommendations = [:]
        userSelection = .init()

        do {
            // 1. 检查是否已有缓存结果
            progress = 0.1
            if let cached = allRecommendations[group.id] {
                photoScores = cached.scores
                recommendations = cached.recommendations
                progress = 1.0
            } else {
                // 2. 生成新推荐
                progress = 0.3
                let result = await recommendationService.generateRecommendations(for: group)
                photoScores = result.scores
                recommendations = result.recommendations

                // 3. 缓存结果
                allRecommendations[group.id] = result
                progress = 1.0
            }

            // 4. 初始化用户选择状态
            initializeUserSelection()

        } catch {
            errorMessage = "生成推荐失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// 一键接受推荐
    func acceptRecommendation() {
        guard let group = currentGroup,
              let autoAcceptResult = recommendationService.generateAutoAcceptResult(
                for: group,
                recommendations: recommendations
              ) else {
            return
        }

        // 更新用户选择
        userSelection.keptPhotoIds = Set(autoAcceptResult.keptPhotoIds)
        userSelection.deletedPhotoIds = Set(autoAcceptResult.deletedPhotoIds)
        userSelection.isAutoAccepted = true
        userSelection.primaryPhotoId = autoAcceptResult.primaryPhotoId

        // 发送通知
        NotificationCenter.default.post(
            name: .recommendationAccepted,
            object: autoAcceptResult
        )
    }

    /// 手动选择照片
    func selectPhoto(_ photoId: String, for action: SelectionAction) {
        switch action {
        case .keep:
            userSelection.keptPhotoIds.insert(photoId)
            userSelection.deletedPhotoIds.remove(photoId)
        case .delete:
            userSelection.deletedPhotoIds.insert(photoId)
            userSelection.keptPhotoIds.remove(photoId)
        case .toggle:
            if userSelection.keptPhotoIds.contains(photoId) {
                userSelection.keptPhotoIds.remove(photoId)
                userSelection.deletedPhotoIds.insert(photoId)
            } else if userSelection.deletedPhotoIds.contains(photoId) {
                userSelection.deletedPhotoIds.remove(photoId)
            } else {
                // 默认标记为保留
                userSelection.keptPhotoIds.insert(photoId)
            }
        }

        // 如果自动接受状态被修改，清除标志
        if action != .toggle || !userSelection.isAutoAccepted {
            userSelection.isAutoAccepted = false
        }
    }

    /// 批量选择
    func batchSelect(photoIds: [String], for action: SelectionAction) {
        for photoId in photoIds {
            selectPhoto(photoId, for: action)
        }
    }

    /// 选择整个层级
    func selectLevel(_ level: PhotoScore.RecommendationLevel, for action: SelectionAction) {
        guard let photosInLevel = recommendations[level] else {
            return
        }

        let photoIds = photosInLevel.map { $0.id }
        batchSelect(photoIds: photoIds, for: action)
    }

    /// 确认选择并处理
    func confirmSelection() -> UserSelectionResult? {
        guard let group = currentGroup else {
            return nil
        }

        // 确保所有照片都有选择状态
        let allPhotoIds = Set(group.photos.map { $0.localIdentifier })
        let unselectedIds = allPhotoIds.subtracting(userSelection.keptPhotoIds)
                                        .subtracting(userSelection.deletedPhotoIds)

        // 未选择的照片默认标记为删除
        userSelection.deletedPhotoIds.formUnion(unselectedIds)

        // 构建结果
        let result = UserSelectionResult(
            groupId: group.id,
            primaryPhotoId: getPrimaryPhotoId(),
            keptPhotoIds: Array(userSelection.keptPhotoIds),
            deletedPhotoIds: Array(userSelection.deletedPhotoIds),
            isAutoAccepted: userSelection.isAutoAccepted,
            selectionDate: Date()
        )

        // 发送通知
        NotificationCenter.default.post(
            name: .selectionConfirmed,
            object: result
        )

        // 重置状态
        resetForNextGroup()

        return result
    }

    /// 获取照片的推荐解释
    func getExplanation(for photoId: String) -> String {
        guard let score = photoScores.first(where: { $0.id == photoId }) else {
            return "未找到照片信息"
        }

        return recommendationService.generateDetailedExplanation(
            for: score,
            inGroup: photoScores
        )
    }

    /// 获取选择统计
    func getSelectionStatistics() -> SelectionStatistics {
        guard let group = currentGroup else {
            return .init()
        }

        let total = group.photos.count
        let kept = userSelection.keptPhotoIds.count
        let deleted = userSelection.deletedPhotoIds.count
        let unselected = total - kept - deleted

        let spaceSaved = estimateSpaceSaved(deletedCount: deleted)

        return SelectionStatistics(
            totalPhotos: total,
            keptCount: kept,
            deletedCount: deleted,
            unselectedCount: unselected,
            spaceSaved: spaceSaved,
            cleanupRate: total > 0 ? Double(deleted) / Double(total) : 0
        )
    }

    /// 检查选择是否有效
    var isSelectionValid: Bool {
        guard let group = currentGroup else {
            return false
        }

        let total = group.photos.count
        let selected = userSelection.keptPhotoIds.count + userSelection.deletedPhotoIds.count

        // 至少需要处理一定比例的照片
        return selected >= min(3, total) || selected == total
    }

    // MARK: - 私有方法

    private func setupBindings() {
        // 监听当前组变化
        $currentGroup
            .sink { [weak self] group in
                if group == nil {
                    self?.resetState()
                }
            }
            .store(in: &cancellables)
    }

    private func initializeUserSelection() {
        userSelection = .init()

        // 默认选择：主推荐和建议保留的照片标记为保留
        if let primary = recommendations[.primary]?.first {
            userSelection.keptPhotoIds.insert(primary.id)
            userSelection.primaryPhotoId = primary.id
        }

        if let suggested = recommendations[.suggestedKeep] {
            for score in suggested {
                userSelection.keptPhotoIds.insert(score.id)
            }
        }

        // 建议删除的照片标记为删除
        if let toDelete = recommendations[.suggestDelete] {
            for score in toDelete {
                userSelection.deletedPhotoIds.insert(score.id)
            }
        }
    }

    private func getPrimaryPhotoId() -> String? {
        // 如果有明确的主推荐照片，使用它
        if let primary = recommendations[.primary]?.first {
            return primary.id
        }

        // 否则选择保留的照片中总分最高的
        let keptScores = photoScores.filter { userSelection.keptPhotoIds.contains($0.id) }
        return keptScores.max(by: { $0.totalScore < $1.totalScore })?.id
    }

    private func estimateSpaceSaved(deletedCount: Int) -> String {
        // 简化估算：每张照片平均3MB
        let totalBytes = Int64(deletedCount) * 3 * 1024 * 1024

        if totalBytes < 1024 * 1024 {
            return "小于1MB"
        } else if totalBytes < 1024 * 1024 * 1024 {
            return "约\(totalBytes / (1024 * 1024))MB"
        } else {
            let gb = Double(totalBytes) / (1024 * 1024 * 1024)
            return String(format: "约%.1fGB", gb)
        }
    }

    private func resetState() {
        photoScores = []
        recommendations = [:]
        userSelection = .init()
        selectedPhotoId = nil
        showExplanation = false
    }

    private func resetForNextGroup() {
        currentGroup = nil
        resetState()
    }

    // MARK: - 批量处理支持

    /// 为多个组预生成推荐（提高性能）
    func pregenerateRecommendations(for groups: [PhotoGroup]) async {
        guard !groups.isEmpty else { return }

        isLoading = true
        progress = 0

        let batchResults = await recommendationService.generateRecommendations(
            for: groups,
            config: .default
        )

        allRecommendations.merge(batchResults) { (_, new) in new }

        isLoading = false
        progress = 1.0
    }

    /// 检查是否已有推荐缓存
    func hasCachedRecommendations(for groupId: UUID) -> Bool {
        return allRecommendations[groupId] != nil
    }

    /// 清空缓存
    func clearCache() {
        allRecommendations.removeAll()
        photoAnalyzer.clearCache()
    }
}

// MARK: - 数据结构

/// 用户选择状态
struct UserSelectionState {
    var keptPhotoIds: Set<String> = []
    var deletedPhotoIds: Set<String> = []
    var isAutoAccepted: Bool = false
    var primaryPhotoId: String?

    /// 检查照片的选择状态
    func selectionStatus(for photoId: String) -> SelectionStatus {
        if keptPhotoIds.contains(photoId) {
            return .kept
        } else if deletedPhotoIds.contains(photoId) {
            return .deleted
        } else {
            return .unselected
        }
    }

    /// 检查是否所有照片都已选择
    func isComplete(for totalCount: Int) -> Bool {
        return keptPhotoIds.count + deletedPhotoIds.count == totalCount
    }
}

/// 选择操作
enum SelectionAction {
    case keep
    case delete
    case toggle
}

/// 选择状态
enum SelectionStatus {
    case kept
    case deleted
    case unselected

    var color: String {
        switch self {
        case .kept: return "#4CAF50" // 绿色
        case .deleted: return "#F44336" // 红色
        case .unselected: return "#9E9E9E" // 灰色
        }
    }

    var icon: String {
        switch self {
        case .kept: return "checkmark.circle.fill"
        case .deleted: return "trash.circle.fill"
        case .unselected: return "circle"
        }
    }
}

/// 用户选择结果
struct UserSelectionResult {
    let groupId: UUID
    let primaryPhotoId: String?
    let keptPhotoIds: [String]
    let deletedPhotoIds: [String]
    let isAutoAccepted: Bool
    let selectionDate: Date

    /// 计算清理统计
    var cleanupStats: (kept: Int, deleted: Int, cleanupRate: Double) {
        let total = keptPhotoIds.count + deletedPhotoIds.count
        let cleanupRate = total > 0 ? Double(deletedPhotoIds.count) / Double(total) : 0
        return (keptPhotoIds.count, deletedPhotoIds.count, cleanupRate)
    }
}

/// 选择统计
struct SelectionStatistics {
    var totalPhotos: Int = 0
    var keptCount: Int = 0
    var deletedCount: Int = 0
    var unselectedCount: Int = 0
    var spaceSaved: String = ""
    var cleanupRate: Double = 0

    /// 获取统计摘要
    var summary: String {
        var parts: [String] = []

        if totalPhotos > 0 {
            parts.append("总计: \(totalPhotos)")
        }

        if keptCount > 0 {
            parts.append("保留: \(keptCount)")
        }

        if deletedCount > 0 {
            parts.append("删除: \(deletedCount)")
            if !spaceSaved.isEmpty {
                parts.append("节省: \(spaceSaved)")
            }
        }

        if unselectedCount > 0 {
            parts.append("未选: \(unselectedCount)")
        }

        return parts.joined(separator: " · ")
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    static let recommendationAccepted = Notification.Name("recommendationAccepted")
    static let selectionConfirmed = Notification.Name("selectionConfirmed")
}

// MARK: - 扩展

extension RecommendationViewModel {
    /// 获取推荐进度描述
    var progressDescription: String {
        if isLoading {
            let percent = Int(progress * 100)
            return "正在分析照片质量... \(percent)%"
        } else if !photoScores.isEmpty {
            return "分析完成，开始选择"
        } else {
            return "准备分析照片质量"
        }
    }

    /// 获取推荐摘要
    var recommendationSummary: String {
        var parts: [String] = []

        if let primary = recommendations[.primary], !primary.isEmpty {
            parts.append("主推荐: \(primary.count)张")
        }

        if let suggested = recommendations[.suggestedKeep], !suggested.isEmpty {
            parts.append("建议保留: \(suggested.count)张")
        }

        if let optional = recommendations[.optionalKeep], !optional.isEmpty {
            parts.append("可选保留: \(optional.count)张")
        }

        if let toDelete = recommendations[.suggestDelete], !toDelete.isEmpty {
            parts.append("建议删除: \(toDelete.count)张")
        }

        return parts.joined(separator: " · ")
    }

    /// 获取照片的推荐层级
    func getRecommendationLevel(for photoId: String) -> PhotoScore.RecommendationLevel? {
        for (level, photos) in recommendations {
            if photos.contains(where: { $0.id == photoId }) {
                return level
            }
        }
        return nil
    }

    /// 获取照片的推荐理由
    func getRecommendationReasons(for photoId: String) -> [String] {
        guard let score = photoScores.first(where: { $0.id == photoId }) else {
            return []
        }
        return score.recommendationReasons
    }

    /// 检查一键接受推荐是否可用
    var isAutoAcceptAvailable: Bool {
        return recommendations[.primary]?.first != nil
    }

    /// 获取一键接受的预估结果
    var autoAcceptPreview: AutoAcceptPreview? {
        guard let group = currentGroup,
              let result = recommendationService.generateAutoAcceptResult(
                for: group,
                recommendations: recommendations
              ) else {
            return nil
        }

        let stats = result.cleanupStats
        return AutoAcceptPreview(
            keptCount: stats.kept,
            deletedCount: stats.deleted,
            cleanupRate: stats.cleanupRate,
            spaceEstimate: estimateSpaceSaved(deletedCount: stats.deleted)
        )
    }
}

/// 一键接受预览
struct AutoAcceptPreview {
    let keptCount: Int
    let deletedCount: Int
    let cleanupRate: Float
    let spaceEstimate: String

    var summary: String {
        return "保留\(keptCount)张，删除\(deletedCount)张，清理\(Int(cleanupRate * 100))%，节省\(spaceEstimate)"
    }
}