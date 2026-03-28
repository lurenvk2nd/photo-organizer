import Foundation
import Photos

/// 照片评分模型，用于分层推荐
struct PhotoScore: Identifiable, Equatable {
    let id: String // 对应PHAsset的localIdentifier
    let asset: PHAsset

    // 各维度得分（0-1，越高越好）
    var clarityScore: Float = 0.5      // 清晰度
    var subjectCompleteness: Float = 0.5 // 主体完整性
    var eyesOpenScore: Float?          // 眼睛睁开分数（可选，无人物则为nil）
    var compositionStability: Float = 0.5 // 构图稳定性
    var duplicateScore: Float = 0      // 重复度（越高表示越重复，与其他照片相似）

    // 计算总分
    var totalScore: Float {
        let baseScore = clarityScore * 0.25 +
                       subjectCompleteness * 0.2 +
                       (eyesOpenScore ?? 0.5) * 0.15 +
                       compositionStability * 0.15

        // 重复度越高，总分越低
        return baseScore * (1.0 - duplicateScore * 0.25)
    }

    /// 推荐层级
    var recommendationLevel: RecommendationLevel {
        let score = totalScore

        if score >= 0.8 && duplicateScore < 0.3 {
            return .primary
        } else if score >= 0.7 && duplicateScore < 0.5 {
            return .suggestedKeep
        } else if score >= 0.5 && duplicateScore < 0.8 {
            return .optionalKeep
        } else {
            return .suggestDelete
        }
    }

    /// 推荐理由
    var recommendationReasons: [String] {
        var reasons: [String] = []

        if clarityScore > 0.8 {
            reasons.append("最清晰")
        } else if clarityScore > 0.6 {
            reasons.append("较清晰")
        }

        if subjectCompleteness > 0.7 {
            reasons.append("主体更完整")
        }

        if let eyesOpen = eyesOpenScore, eyesOpen > 0.8 {
            reasons.append("人物睁眼")
        } else if let eyesOpen = eyesOpenScore, eyesOpen < 0.3 {
            reasons.append("人物闭眼")
        }

        if compositionStability > 0.6 {
            reasons.append("构图更稳定")
        }

        if duplicateScore > 0.9 {
            reasons.append("与其他照片高度重复（相似度\(Int(duplicateScore * 100))%）")
        } else if duplicateScore > 0.7 {
            reasons.append("与其他照片较相似（相似度\(Int(duplicateScore * 100))%）")
        }

        // 如果没有理由，添加默认理由
        if reasons.isEmpty {
            switch recommendationLevel {
            case .primary:
                reasons.append("综合表现最佳")
            case .suggestedKeep:
                reasons.append("值得保留")
            case .optionalKeep:
                reasons.append("可考虑保留")
            case .suggestDelete:
                reasons.append("建议清理")
            }
        }

        return reasons
    }

    /// 推荐层级枚举
    enum RecommendationLevel: String, CaseIterable {
        case primary = "主推荐"
        case suggestedKeep = "建议保留"
        case optionalKeep = "可选保留"
        case suggestDelete = "建议删除"

        var colorHex: String {
            switch self {
            case .primary: return "#4CAF50" // 绿色
            case .suggestedKeep: return "#2196F3" // 蓝色
            case .optionalKeep: return "#FF9800" // 橙色
            case .suggestDelete: return "#F44336" // 红色
            }
        }

        var description: String {
            switch self {
            case .primary:
                return "最佳选择，建议优先保留"
            case .suggestedKeep:
                return "质量不错，建议保留"
            case .optionalKeep:
                return "可根据需要选择保留"
            case .suggestDelete:
                return "可考虑删除以节省空间"
            }
        }
    }

    init(id: String, asset: PHAsset) {
        self.id = id
        self.asset = asset
    }

    static func == (lhs: PhotoScore, rhs: PhotoScore) -> Bool {
        lhs.id == rhs.id
    }

    /// 根据得分获取推荐理由的简短描述
    func briefReason() -> String {
        if let topReason = recommendationReasons.first {
            return topReason
        }
        return recommendationLevel.description
    }
}