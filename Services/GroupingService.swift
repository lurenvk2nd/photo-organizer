import Foundation
import Photos
import CoreLocation

/// 分组服务，负责将照片按场景自动分组
class GroupingService {
    private let locationHelper = LocationHelper()
    private let photoAnalyzer = PhotoAnalyzer()

    // MARK: - 分组配置

    struct GroupingConfig {
        var timeThreshold: TimeInterval = 30 // 30秒内视为同一时间组
        var distanceThreshold: CLLocationDistance = 50 // 50米内视为同一地点
        var visualSimilarityThreshold: Float = 0.85 // 视觉相似度阈值
        var maxGroupSize: Int = 20 // 最大组大小（避免超大组）
        var minGroupSize: Int = 2 // 最小组大小（单人照不分组）

        static let `default` = GroupingConfig()
    }

    // MARK: - 主分组方法

    /// 自动分组照片
    func autoGroup(photos: [PHAsset], config: GroupingConfig = .default) async -> [PhotoGroup] {
        guard photos.count >= config.minGroupSize else {
            return []
        }

        // 1. 过滤已处理照片（可选）
        let unprocessedPhotos = photos // 这里可以过滤掉已处理照片

        // 2. 按时间窗口初步分组
        print("开始时间分组...")
        let timeGroups = groupByTime(unprocessedPhotos, threshold: config.timeThreshold)

        // 3. 在时间组内按地点细分
        print("开始地点分组...")
        var locationGroups: [PhotoGroup] = []
        for group in timeGroups {
            let subgroups = groupByLocation(group.photos, threshold: config.distanceThreshold)
            locationGroups.append(contentsOf: subgroups)
        }

        // 4. 在位置组内按视觉相似度最终分组
        print("开始视觉相似度分组...")
        var finalGroups: [PhotoGroup] = []
        for group in locationGroups {
            if group.photos.count <= config.minGroupSize {
                // 如果组太小，直接作为最终组
                finalGroups.append(group)
                continue
            }

            let subgroups = await groupByVisualSimilarity(group.photos,
                                                         threshold: config.visualSimilarityThreshold,
                                                         maxSize: config.maxGroupSize)
            finalGroups.append(contentsOf: subgroups)
        }

        // 5. 过滤掉太小的组
        finalGroups = finalGroups.filter { $0.photos.count >= config.minGroupSize }

        // 6. 添加分组元数据
        finalGroups = finalGroups.map { group in
            var updatedGroup = group
            updatedGroup.creationDate = group.photos.compactMap { $0.creationDate }.min()
            updatedGroup.location = group.centerLocation
            return updatedGroup
        }

        print("分组完成: 原始照片 \(photos.count)张 -> 最终分组 \(finalGroups.count)个")
        return finalGroups
    }

    // MARK: - 时间分组

    /// 按时间接近性分组
    private func groupByTime(_ photos: [PHAsset], threshold: TimeInterval) -> [PhotoGroup] {
        guard !photos.isEmpty else { return [] }

        // 按创建时间排序
        let sortedPhotos = photos.sorted { asset1, asset2 in
            guard let date1 = asset1.creationDate, let date2 = asset2.creationDate else {
                return false
            }
            return date1 < date2
        }

        var groups: [PhotoGroup] = []
        var currentGroup: [PHAsset] = []
        var previousDate: Date?

        for photo in sortedPhotos {
            guard let currentDate = photo.creationDate else {
                continue
            }

            if let prevDate = previousDate {
                let timeDiff = currentDate.timeIntervalSince(prevDate)

                if timeDiff <= threshold {
                    // 时间接近，加入当前组
                    currentGroup.append(photo)
                } else {
                    // 时间间隔大，结束当前组，开始新组
                    if currentGroup.count >= 2 {
                        groups.append(PhotoGroup(photos: currentGroup,
                                                groupReason: .timeProximity(threshold: threshold)))
                    }
                    currentGroup = [photo]
                }
            } else {
                // 第一个照片
                currentGroup.append(photo)
            }

            previousDate = currentDate
        }

        // 添加最后一组
        if currentGroup.count >= 2 {
            groups.append(PhotoGroup(photos: currentGroup,
                                    groupReason: .timeProximity(threshold: threshold)))
        }

        return groups
    }

    // MARK: - 地点分组

    /// 按地点接近性分组
    private func groupByLocation(_ photos: [PHAsset], threshold: CLLocationDistance) -> [PhotoGroup] {
        guard !photos.isEmpty else { return [] }

        // 过滤有位置信息的照片
        let photosWithLocation = photos.filter { $0.location != nil }

        if photosWithLocation.isEmpty {
            // 如果没有位置信息，返回原始组
            return [PhotoGroup(photos: photos, groupReason: .locationProximity(threshold: threshold))]
        }

        // 使用DBSCAN简单实现进行位置聚类
        let clusters = locationHelper.dbscanClustering(assets: photosWithLocation,
                                                      epsilon: threshold,
                                                      minPoints: 2)

        var groups: [PhotoGroup] = []

        // 为每个聚类创建组
        for cluster in clusters {
            // 找出这个聚类中的所有照片（包括可能没有位置信息的照片）
            let clusterCenter = locationHelper.centerOfLocations(cluster.compactMap { $0.location })
            let clusterDate = cluster.compactMap { $0.creationDate }.min()

            // 找出时间相近且可能在同一地点的其他照片
            var allPhotosInCluster = cluster

            // 可以添加逻辑：将没有位置信息但时间相近的照片也加入组
            let photosWithoutLocation = photos.filter { $0.location == nil }
            for photo in photosWithoutLocation {
                if let photoDate = photo.creationDate,
                   let clusterDate = clusterDate,
                   abs(photoDate.timeIntervalSince(clusterDate)) <= 300 { // 5分钟内
                    allPhotosInCluster.append(photo)
                }
            }

            if allPhotosInCluster.count >= 2 {
                groups.append(PhotoGroup(photos: allPhotosInCluster,
                                        creationDate: clusterDate,
                                        location: clusterCenter,
                                        groupReason: .locationProximity(threshold: threshold)))
            }
        }

        // 处理没有分组的照片（如果还有的话）
        let groupedPhotos = Set(groups.flatMap { $0.photos })
        let ungroupedPhotos = photos.filter { !groupedPhotos.contains($0) }

        if ungroupedPhotos.count >= 2 {
            groups.append(PhotoGroup(photos: ungroupedPhotos,
                                    groupReason: .locationProximity(threshold: threshold)))
        }

        return groups
    }

    // MARK: - 视觉相似度分组

    /// 按视觉相似度分组
    private func groupByVisualSimilarity(_ photos: [PHAsset],
                                        threshold: Float,
                                        maxSize: Int) async -> [PhotoGroup] {
        guard photos.count >= 2 else {
            return [PhotoGroup(photos: photos, groupReason: .visualSimilarity(threshold: threshold))]
        }

        // 提取特征向量
        let features = await photoAnalyzer.extractFeatureVectors(for: photos)

        // 构建相似度矩阵
        let similarityMatrix = buildSimilarityMatrix(photos: photos, features: features)

        // 使用层次聚类
        let clusters = hierarchicalClustering(photos: photos,
                                            similarityMatrix: similarityMatrix,
                                            threshold: threshold,
                                            maxSize: maxSize)

        // 创建分组
        var groups: [PhotoGroup] = []
        for cluster in clusters {
            if cluster.count >= 2 {
                groups.append(PhotoGroup(photos: cluster,
                                        groupReason: .visualSimilarity(threshold: threshold)))
            }
        }

        return groups
    }

    /// 构建相似度矩阵
    private func buildSimilarityMatrix(photos: [PHAsset],
                                      features: [String: VNFeaturePrintObservation]) -> [[Float]] {
        let count = photos.count
        var matrix = Array(repeating: Array(repeating: Float(0), count: count), count: count)

        for i in 0..<count {
            for j in i..<count {
                if i == j {
                    matrix[i][j] = 1.0
                    continue
                }

                let asset1 = photos[i]
                let asset2 = photos[j]

                if let feature1 = features[asset1.localIdentifier],
                   let feature2 = features[asset2.localIdentifier] {
                    do {
                        let similarity = try photoAnalyzer.calculateVisualSimilarity(feature1: feature1,
                                                                                    feature2: feature2)
                        matrix[i][j] = similarity
                        matrix[j][i] = similarity
                    } catch {
                        matrix[i][j] = 0
                        matrix[j][i] = 0
                    }
                } else {
                    matrix[i][j] = 0
                    matrix[j][i] = 0
                }
            }
        }

        return matrix
    }

    /// 层次聚类
    private func hierarchicalClustering(photos: [PHAsset],
                                      similarityMatrix: [[Float]],
                                      threshold: Float,
                                      maxSize: Int) -> [[PHAsset]] {
        let count = photos.count
        guard count > 0 else { return [] }

        // 初始化每个照片为一个单独的簇
        var clusters: [[PHAsset]] = photos.map { [$0] }
        var clusterSimilarities: [[Float]] = similarityMatrix

        // 重复合并最相似的簇，直到没有足够相似的簇
        while clusters.count > 1 {
            // 找到最相似的两个簇
            var maxSimilarity: Float = -1
            var bestPair: (Int, Int)?

            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    // 计算簇间平均相似度
                    let similarity = averageSimilarity(cluster1Index: i,
                                                      cluster2Index: j,
                                                      clusters: clusters,
                                                      similarityMatrix: similarityMatrix,
                                                      photoIndices: photos.indices.map { $0 })

                    if similarity > maxSimilarity {
                        maxSimilarity = similarity
                        bestPair = (i, j)
                    }
                }
            }

            // 如果最相似度低于阈值或合并后簇太大，停止合并
            guard let (i, j) = bestPair,
                  maxSimilarity >= threshold,
                  clusters[i].count + clusters[j].count <= maxSize else {
                break
            }

            // 合并簇
            let mergedCluster = clusters[i] + clusters[j]
            clusters[i] = mergedCluster
            clusters.remove(at: j)

            // 更新簇相似度矩阵（简化：删除被合并的簇）
            // 实际实现应该重新计算簇间相似度
        }

        return clusters
    }

    /// 计算两个簇之间的平均相似度
    private func averageSimilarity(cluster1Index: Int,
                                  cluster2Index: Int,
                                  clusters: [[PHAsset]],
                                  similarityMatrix: [[Float]],
                                  photoIndices: [Int]) -> Float {
        let cluster1 = clusters[cluster1Index]
        let cluster2 = clusters[cluster2Index]

        var totalSimilarity: Float = 0
        var pairCount = 0

        // 找到照片在原始数组中的索引
        for photo1 in cluster1 {
            for photo2 in cluster2 {
                if let index1 = photoIndices.first(where: { photos[$0] == photo1 }),
                   let index2 = photoIndices.first(where: { photos[$0] == photo2 }) {
                    totalSimilarity += similarityMatrix[index1][index2]
                    pairCount += 1
                }
            }
        }

        return pairCount > 0 ? totalSimilarity / Float(pairCount) : 0
    }

    // MARK: - 工具方法

    /// 获取建议的分组配置（基于照片数量和设备性能）
    func suggestedConfig(for photoCount: Int) -> GroupingConfig {
        var config = GroupingConfig.default

        // 根据照片数量调整参数
        if photoCount > 1000 {
            config.timeThreshold = 60 // 更多照片时放宽时间阈值
            config.distanceThreshold = 100
            config.visualSimilarityThreshold = 0.9 // 提高相似度阈值减少计算
        } else if photoCount > 5000 {
            config.timeThreshold = 120
            config.distanceThreshold = 200
            config.maxGroupSize = 10 // 减少最大组大小
        }

        return config
    }

    /// 重新分组指定照片（当用户修改选择后）
    func regroup(photos: [PHAsset], existingGroups: [PhotoGroup]) async -> [PhotoGroup] {
        // 从现有组中移除这些照片
        var updatedGroups = existingGroups.map { group in
            var updatedGroup = group
            updatedGroup.photos = group.photos.filter { !photos.contains($0) }
            return updatedGroup
        }

        // 移除空组
        updatedGroups = updatedGroups.filter { !$0.photos.isEmpty }

        // 对新照片进行分组
        let newGroups = await autoGroup(photos: photos)

        // 合并并返回
        return updatedGroups + newGroups
    }
}

// MARK: - PHAsset相等性扩展（简化实现）

extension PHAsset {
    static func == (lhs: PHAsset, rhs: PHAsset) -> Bool {
        return lhs.localIdentifier == rhs.localIdentifier
    }
}