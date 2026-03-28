import Foundation
import CoreLocation
import Photos

/// 地理位置助手，用于处理照片的地理位置信息
class LocationHelper {

    // MARK: - 距离计算

    /// 计算两个地理位置之间的距离（米）
    func distanceBetween(_ location1: CLLocation?, _ location2: CLLocation?) -> CLLocationDistance {
        guard let loc1 = location1, let loc2 = location2 else {
            return Double.greatestFiniteMagnitude // 如果任一位置为空，返回极大值
        }

        return loc1.distance(from: loc2)
    }

    /// 计算多个位置的中心点
    func centerOfLocations(_ locations: [CLLocation]) -> CLLocation? {
        guard !locations.isEmpty else { return nil }

        if locations.count == 1 {
            return locations.first
        }

        var totalLat: Double = 0
        var totalLon: Double = 0

        for location in locations {
            totalLat += location.coordinate.latitude
            totalLon += location.coordinate.longitude
        }

        let center = CLLocation(latitude: totalLat / Double(locations.count),
                               longitude: totalLon / Double(locations.count))
        return center
    }

    /// 计算位置组的半径（最远点到中心的距离）
    func radiusOfLocations(_ locations: [CLLocation], center: CLLocation? = nil) -> CLLocationDistance {
        guard !locations.isEmpty else { return 0 }

        let calculatedCenter = center ?? centerOfLocations(locations) ?? locations.first!
        var maxDistance: CLLocationDistance = 0

        for location in locations {
            let distance = location.distance(from: calculatedCenter)
            maxDistance = max(maxDistance, distance)
        }

        return maxDistance
    }

    // MARK: - 聚类算法

    /// DBSCAN聚类算法实现
    func dbscanClustering(assets: [PHAsset],
                         epsilon: CLLocationDistance,
                         minPoints: Int) -> [[PHAsset]] {
        guard !assets.isEmpty else { return [] }

        var clusters: [[PHAsset]] = []
        var visited = Set<String>()
        var noise = Set<String>()

        // 过滤有位置信息的资产
        let assetsWithLocation = assets.filter { $0.location != nil }

        for asset in assetsWithLocation {
            let assetId = asset.localIdentifier

            if visited.contains(assetId) {
                continue
            }

            visited.insert(assetId)

            // 查找邻居
            let neighbors = regionQuery(assets: assetsWithLocation,
                                       centerAsset: asset,
                                       epsilon: epsilon)

            if neighbors.count < minPoints {
                // 标记为噪声点
                noise.insert(assetId)
            } else {
                // 创建新簇
                var cluster: [PHAsset] = [asset]

                // 扩展簇
                var neighborQueue = neighbors
                while !neighborQueue.isEmpty {
                    let neighborAsset = neighborQueue.removeFirst()
                    let neighborId = neighborAsset.localIdentifier

                    if !visited.contains(neighborId) {
                        visited.insert(neighborId)

                        let neighborNeighbors = regionQuery(assets: assetsWithLocation,
                                                           centerAsset: neighborAsset,
                                                           epsilon: epsilon)

                        if neighborNeighbors.count >= minPoints {
                            neighborQueue.append(contentsOf: neighborNeighbors)
                        }
                    }

                    // 如果邻居不在任何簇中且不是噪声点，加入当前簇
                    if !clusters.contains(where: { $0.contains { $0.localIdentifier == neighborId } }) &&
                       !noise.contains(neighborId) {
                        cluster.append(neighborAsset)
                    }
                }

                if cluster.count >= minPoints {
                    clusters.append(cluster)
                }
            }
        }

        return clusters
    }

    /// 区域查询：查找给定中心点epsilon距离内的所有资产
    private func regionQuery(assets: [PHAsset],
                            centerAsset: PHAsset,
                            epsilon: CLLocationDistance) -> [PHAsset] {
        guard let centerLocation = centerAsset.location else { return [] }

        return assets.filter { otherAsset in
            guard let otherLocation = otherAsset.location,
                  otherAsset.localIdentifier != centerAsset.localIdentifier else {
                return false
            }

            return centerLocation.distance(from: otherLocation) <= epsilon
        }
    }

    /// 层次聚类算法（简化版）
    func hierarchicalClustering(assets: [PHAsset],
                               distanceThreshold: CLLocationDistance) -> [[PHAsset]] {
        guard !assets.isEmpty else { return [] }

        let assetsWithLocation = assets.filter { $0.location != nil }

        if assetsWithLocation.isEmpty {
            // 如果没有位置信息，每个资产单独成簇
            return assets.map { [$0] }
        }

        // 初始化每个资产为一个单独的簇
        var clusters: [[PHAsset]] = assetsWithLocation.map { [$0] }

        // 计算初始距离矩阵
        var distanceMatrix = computeDistanceMatrix(assets: assetsWithLocation)

        // 合并簇直到最小距离超过阈值
        while clusters.count > 1 {
            // 找到距离最小的两个簇
            var minDistance = Double.greatestFiniteMagnitude
            var minPair: (Int, Int)?

            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let distance = clusterDistance(cluster1: clusters[i],
                                                  cluster2: clusters[j],
                                                  distanceMatrix: distanceMatrix,
                                                  allAssets: assetsWithLocation)

                    if distance < minDistance {
                        minDistance = distance
                        minPair = (i, j)
                    }
                }
            }

            guard let (i, j) = minPair, minDistance <= distanceThreshold else {
                break
            }

            // 合并两个簇
            let mergedCluster = clusters[i] + clusters[j]
            clusters[i] = mergedCluster
            clusters.remove(at: j)

            // 更新距离矩阵（简化：删除被合并的簇对应的行和列）
            // 实际实现应该重新计算簇间距离
        }

        // 将没有位置信息的资产作为单独簇添加
        let assetsWithoutLocation = assets.filter { $0.location == nil }
        for asset in assetsWithoutLocation {
            clusters.append([asset])
        }

        return clusters
    }

    /// 计算资产间的距离矩阵
    private func computeDistanceMatrix(assets: [PHAsset]) -> [[CLLocationDistance]] {
        let count = assets.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count)

        for i in 0..<count {
            for j in 0..<count {
                if i == j {
                    matrix[i][j] = 0
                } else if i < j {
                    let distance = distanceBetween(assets[i].location, assets[j].location)
                    matrix[i][j] = distance
                    matrix[j][i] = distance
                }
            }
        }

        return matrix
    }

    /// 计算两个簇之间的距离（使用平均链接法）
    private func clusterDistance(cluster1: [PHAsset],
                                cluster2: [PHAsset],
                                distanceMatrix: [[CLLocationDistance]],
                                allAssets: [PHAsset]) -> CLLocationDistance {
        var totalDistance: CLLocationDistance = 0
        var pairCount = 0

        // 找到资产在原始数组中的索引
        for asset1 in cluster1 {
            for asset2 in cluster2 {
                if let index1 = allAssets.firstIndex(where: { $0.localIdentifier == asset1.localIdentifier }),
                   let index2 = allAssets.firstIndex(where: { $0.localIdentifier == asset2.localIdentifier }) {
                    totalDistance += distanceMatrix[index1][index2]
                    pairCount += 1
                }
            }
        }

        return pairCount > 0 ? totalDistance / CLLocationDistance(pairCount) : Double.greatestFiniteMagnitude
    }

    // MARK: - 地理位置格式化

    /// 格式化距离显示
    func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1 {
            return "小于1米"
        } else if distance < 1000 {
            return "\(Int(distance))米"
        } else {
            let kilometers = distance / 1000
            if kilometers < 10 {
                return String(format: "%.1f公里", kilometers)
            } else {
                return "\(Int(kilometers))公里"
            }
        }
    }

    /// 格式化位置信息
    func formatLocation(_ location: CLLocation?) -> String {
        guard let location = location else {
            return "位置未知"
        }

        let coordinate = location.coordinate
        return String(format: "%.4f°N, %.4f°E", coordinate.latitude, coordinate.longitude)
    }

    /// 获取位置的地址信息（简化版，实际应该使用CLGeocoder）
    func getLocationDescription(_ location: CLLocation) async -> String {
        // 注意：实际使用中应该使用CLGeocoder，但需要处理网络请求和错误
        // 这里返回坐标作为简化实现
        return formatLocation(location)
    }

    // MARK: - 时间-地点关联分析

    /// 分析时间和地点的关联性
    func analyzeSpatioTemporalPattern(assets: [PHAsset]) -> SpatioTemporalAnalysis {
        var analysis = SpatioTemporalAnalysis()

        // 过滤有时间和位置信息的资产
        let validAssets = assets.filter { $0.creationDate != nil && $0.location != nil }

        guard validAssets.count >= 2 else {
            return analysis
        }

        // 按时间排序
        let sortedAssets = validAssets.sorted { ($0.creationDate ?? Date()) < ($1.creationDate ?? Date()) }

        // 分析移动模式
        var totalDistance: CLLocationDistance = 0
        var totalTime: TimeInterval = 0
        var locationChanges = 0

        for i in 0..<(sortedAssets.count - 1) {
            guard let date1 = sortedAssets[i].creationDate,
                  let date2 = sortedAssets[i + 1].creationDate,
                  let loc1 = sortedAssets[i].location,
                  let loc2 = sortedAssets[i + 1].location else {
                continue
            }

            let distance = loc1.distance(from: loc2)
            let timeDiff = date2.timeIntervalSince(date1)

            if distance > 50 { // 移动超过50米算作位置变化
                totalDistance += distance
                totalTime += timeDiff
                locationChanges += 1
            }
        }

        if locationChanges > 0 {
            analysis.averageSpeed = totalDistance / totalTime // 米/秒
            analysis.isStationary = analysis.averageSpeed < 1.0 // 速度小于1米/秒视为静止
            analysis.locationChangeCount = locationChanges
        }

        return analysis
    }
}

// MARK: - 数据结构

/// 时空分析结果
struct SpatioTemporalAnalysis {
    var averageSpeed: CLLocationDistance = 0 // 平均速度（米/秒）
    var isStationary: Bool = true // 是否基本静止
    var locationChangeCount: Int = 0 // 位置变化次数

    /// 获取移动状态描述
    var movementDescription: String {
        if locationChangeCount == 0 {
            return "基本静止"
        } else if isStationary {
            return "缓慢移动"
        } else {
            let speedKmh = averageSpeed * 3.6 // 转换为公里/小时
            if speedKmh < 5 {
                return "步行速度"
            } else if speedKmh < 20 {
                return "自行车速度"
            } else {
                return "交通工具移动"
            }
        }
    }
}

// MARK: - 扩展

extension PHAsset {
    /// 获取照片的地理位置描述（如果有）
    var locationDescription: String {
        guard let location = location else {
            return "无位置信息"
        }

        let coordinate = location.coordinate
        return String(format: "%.4f°, %.4f°", coordinate.latitude, coordinate.longitude)
    }

    /// 检查照片是否有有效的地理位置
    var hasValidLocation: Bool {
        guard let location = location else { return false }

        // 检查坐标是否有效（不在0,0附近）
        let coordinate = location.coordinate
        return abs(coordinate.latitude) > 0.001 || abs(coordinate.longitude) > 0.001
    }
}