import Foundation
import Photos

/// 推荐服务，负责为照片组生成分层推荐
class RecommendationService {
    private let photoAnalyzer = PhotoAnalyzer()

    // MARK: - 推荐配置

    struct RecommendationConfig {
        var primaryCount: Int = 1 // 主推荐数量
        var suggestedKeepRange: ClosedRange<Int> = 1...3 // 建议保留数量范围
        var duplicateThreshold: Float = 0.9 // 高度重复阈值
        var minScoreDifference: Float = 0.1 // 主推荐需超过第二名的分数差

        static let `default` = RecommendationConfig()
    }

    // MARK: - 主推荐方法

    /// 为照片组生成分层推荐
    func generateRecommendations(for group: PhotoGroup,
                                config: RecommendationConfig = .default) async -> (scores: [PhotoScore],
                                                                                 recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]]) {
        // 1. 计算组内所有照片的评分
        let scores = await photoAnalyzer.calculateScores(for: group.photos)

        // 2. 生成分层推荐
        let recommendations = categorizeScores(scores, config: config)

        return (scores, recommendations)
    }

    /// 为多个组批量生成推荐
    func generateRecommendations(for groups: [PhotoGroup],
                                config: RecommendationConfig = .default) async -> [PhotoGroup.ID: (scores: [PhotoScore],
                                                                                                recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]])] {
        var results: [PhotoGroup.ID: (scores: [PhotoScore],
                                     recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]])] = [:]

        // 并行处理每个组
        await withTaskGroup(of: (PhotoGroup.ID, (scores: [PhotoScore],
                                                recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]])).self) { group in
            for photoGroup in groups {
                group.addTask {
                    let result = await self.generateRecommendations(for: photoGroup, config: config)
                    return (photoGroup.id, result)
                }
            }

            for await (groupId, result) in group {
                results[groupId] = result
            }
        }

        return results
    }

    // MARK: - 推荐分类

    /// 将评分分类到不同层级
    private func categorizeScores(_ scores: [PhotoScore],
                                 config: RecommendationConfig) -> [PhotoScore.RecommendationLevel: [PhotoScore]] {
        guard !scores.isEmpty else {
            return [:]
        }

        // 按总分排序
        let sortedScores = scores.sorted { $0.totalScore > $1.totalScore }

        var recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]] = [
            .primary: [],
            .suggestedKeep: [],
            .optionalKeep: [],
            .suggestDelete: []
        ]

        // 1. 主推荐
        if let primaryCandidate = sortedScores.first {
            // 检查主推荐是否明显优于第二名
            var shouldBePrimary = true

            if sortedScores.count > 1 {
                let secondScore = sortedScores[1].totalScore
                if primaryCandidate.totalScore - secondScore < config.minScoreDifference {
                    // 分数差距太小，可能没有明显的最佳选择
                    shouldBePrimary = false
                }
            }

            if shouldBePrimary && primaryCandidate.duplicateScore < config.duplicateThreshold {
                recommendations[.primary] = [primaryCandidate]
            }
        }

        // 2. 建议保留
        var suggestedKeepCandidates = sortedScores
        // 移除已作为主推荐的照片
        if let primary = recommendations[.primary]?.first {
            suggestedKeepCandidates.removeAll { $0.id == primary.id }
        }

        let suggestedKeep = suggestedKeepCandidates
            .filter { $0.recommendationLevel == .suggestedKeep }
            .prefix(config.suggestedKeepRange.upperBound)

        recommendations[.suggestedKeep] = Array(suggestedKeep)

        // 3. 可选保留和建议删除（按推荐层级分类）
        for score in sortedScores {
            let level = score.recommendationLevel

            // 跳过已分类的照片
            if recommendations.values.flatMap({ $0 }).contains(where: { $0.id == score.id }) {
                continue
            }

            switch level {
            case .primary:
                // 主推荐已处理，这里应该不会出现
                continue
            case .suggestedKeep:
                // 建议保留已处理，这里应该不会出现
                continue
            case .optionalKeep:
                recommendations[.optionalKeep]?.append(score)
            case .suggestDelete:
                recommendations[.suggestDelete]?.append(score)
            }
        }

        return recommendations
    }

    // MARK: - 一键接受推荐

    /// 生成一键接受推荐的结果
    func generateAutoAcceptResult(for group: PhotoGroup,
                                  recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]]) -> AutoAcceptResult {
        let primaryPhotos = recommendations[.primary] ?? []
        let suggestedKeepPhotos = recommendations[.suggestedKeep] ?? []
        let optionalKeepPhotos = recommendations[.optionalKeep] ?? []
        let suggestDeletePhotos = recommendations[.suggestDelete] ?? []

        // 决定保留哪些照片
        var photosToKeep: [String] = []
        var photosToDelete: [String] = []

        // 1. 主推荐照片保留
        if let primaryPhoto = primaryPhotos.first {
            photosToKeep.append(primaryPhoto.id)
        } else if let suggestedPhoto = suggestedKeepPhotos.first {
            // 如果没有主推荐，保留第一个建议保留的照片
            photosToKeep.append(suggestedPhoto.id)
        }

        // 2. 建议保留的照片也保留（如果数量不多）
        let suggestedToKeep = suggestedKeepPhotos
            .filter { $0.id != photosToKeep.first }
            .prefix(2) // 最多再保留2张建议保留的

        photosToKeep.append(contentsOf: suggestedToKeep.map { $0.id })

        // 3. 可选保留和建议删除的照片都标记为删除
        let allPhotos = group.photos.map { $0.localIdentifier }
        photosToDelete = allPhotos.filter { !photosToKeep.contains($0) }

        return AutoAcceptResult(
            groupId: group.id,
            primaryPhotoId: photosToKeep.first,
            keptPhotoIds: photosToKeep,
            deletedPhotoIds: photosToDelete,
            recommendationSummary: generateRecommendationSummary(recommendations: recommendations)
        )
    }

    /// 生成推荐摘要
    private func generateRecommendationSummary(recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]]) -> String {
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

    // MARK: - 推荐理由生成

    /// 为推荐生成详细解释
    func generateDetailedExplanation(for score: PhotoScore,
                                    inGroup scores: [PhotoScore]) -> String {
        var explanation = ""

        // 1. 总分排名
        if let rank = scores.firstIndex(where: { $0.id == score.id }) {
            let totalCount = scores.count
            let percentile = Float(rank + 1) / Float(totalCount) * 100

            explanation += "在\(totalCount)张照片中排名第\(rank + 1)（前\(Int(percentile))%）\n\n"
        }

        // 2. 各维度得分
        explanation += "各维度评估：\n"
        explanation += "• 清晰度: \(Int(score.clarityScore * 100))%\n"
        explanation += "• 主体完整性: \(Int(score.subjectCompleteness * 100))%\n"

        if let eyesOpen = score.eyesOpenScore {
            explanation += "• 人物状态: \(Int(eyesOpen * 100))%\n"
        }

        explanation += "• 构图稳定性: \(Int(score.compositionStability * 100))%\n"

        if score.duplicateScore > 0.3 {
            explanation += "• 重复度: \(Int(score.duplicateScore * 100))%（与其他照片相似）\n"
        }

        // 3. 推荐理由
        let reasons = score.recommendationReasons
        if !reasons.isEmpty {
            explanation += "\n推荐理由：\n"
            for reason in reasons {
                explanation += "• \(reason)\n"
            }
        }

        // 4. 建议操作
        explanation += "\n建议：\(score.recommendationLevel.description)"

        return explanation
    }

    // MARK: - 批量处理支持

    /// 检查是否所有推荐都已完成
    func checkAllRecommendationsCompleted(for groups: [PhotoGroup],
                                         userSelections: [String: UserSelection]) -> Bool {
        for group in groups {
            if userSelections[group.id.uuidString] == nil {
                return false
            }
        }
        return true
    }

    /// 获取批量删除统计
    func getBatchDeleteStatistics(for groups: [PhotoGroup],
                                 userSelections: [String: UserSelection]) -> (totalToDelete: Int,
                                                                             spaceEstimate: String) {
        var totalToDelete = 0
        var totalSize: Int64 = 0

        for group in groups {
            if let selection = userSelections[group.id.uuidString] {
                totalToDelete += selection.deletedPhotoIds.count

                // 估算文件大小（简化：每张照片平均3MB）
                totalSize += Int64(selection.deletedPhotoIds.count) * 3 * 1024 * 1024
            }
        }

        let spaceEstimate: String
        if totalSize < 1024 * 1024 {
            spaceEstimate = "小于1MB"
        } else if totalSize < 1024 * 1024 * 1024 {
            spaceEstimate = "约\(totalSize / (1024 * 1024))MB"
        } else {
            spaceEstimate = "约\(String(format: "%.1f", Double(totalSize) / (1024 * 1024 * 1024)))GB"
        }

        return (totalToDelete, spaceEstimate)
    }
}

// MARK: - 数据结构

/// 一键接受推荐的结果
struct AutoAcceptResult {
    let groupId: UUID
    let primaryPhotoId: String?
    let keptPhotoIds: [String]
    let deletedPhotoIds: [String]
    let recommendationSummary: String

    /// 计算清理统计
    var cleanupStats: (kept: Int, deleted: Int, cleanupRate: Float) {
        let total = keptPhotoIds.count + deletedPhotoIds.count
        let cleanupRate = total > 0 ? Float(deletedPhotoIds.count) / Float(total) : 0
        return (keptPhotoIds.count, deletedPhotoIds.count, cleanupRate)
    }
}

// MARK: - 推荐质量评估

extension RecommendationService {
    /// 评估推荐质量（用于后续优化）
    func evaluateRecommendationQuality(for group: PhotoGroup,
                                      userSelection: UserSelection,
                                      recommendations: [PhotoScore.RecommendationLevel: [PhotoScore]]) -> RecommendationQuality {
        let primaryPhotos = recommendations[.primary] ?? []
        let suggestedKeepPhotos = recommendations[.suggestedKeep] ?? []

        var quality = RecommendationQuality()

        // 1. 检查用户是否接受了主推荐
        if let primaryPhoto = primaryPhotos.first,
           userSelection.keptPhotoIds.contains(primaryPhoto.id) {
            quality.primaryAccepted = true
        }

        // 2. 检查用户保留的照片是否多在建议保留中
        let recommendedPhotos = (primaryPhotos + suggestedKeepPhotos).map { $0.id }
        let keptRecommendedCount = userSelection.keptPhotoIds.filter { recommendedPhotos.contains($0) }.count
        quality.recommendationMatchRate = Float(keptRecommendedCount) / Float(userSelection.keptPhotoIds.count)

        // 3. 检查用户删除的照片是否多在建议删除中
        let suggestedDeletePhotos = recommendations[.suggestDelete] ?? []
        let deleteRecommendedCount = userSelection.deletedPhotoIds.filter { id in
            suggestedDeletePhotos.contains { $0.id == id }
        }.count
        quality.deleteMatchRate = Float(deleteRecommendedCount) / Float(userSelection.deletedPhotoIds.count)

        return quality
    }
}

/// 推荐质量评估结果
struct RecommendationQuality {
    var primaryAccepted: Bool = false
    var recommendationMatchRate: Float = 0 // 用户保留与推荐匹配率
    var deleteMatchRate: Float = 0 // 用户删除与建议删除匹配率
    var timestamp: Date = Date()
}