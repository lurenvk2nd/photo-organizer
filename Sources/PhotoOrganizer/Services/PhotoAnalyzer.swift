import Foundation
import Photos
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// 照片分析服务，负责提取照片特征和计算得分
class PhotoAnalyzer {
    private let imageManager = PHImageManager.default()
    private let visionQueue = DispatchQueue(label: "com.photoanalyzer.vision", qos: .userInitiated)
    private var featureCache: [String: VNFeaturePrintObservation] = [:] // 特征向量缓存

    // MARK: - 特征提取

    /// 提取照片的特征向量
    func extractFeatureVector(for asset: PHAsset) async throws -> VNFeaturePrintObservation? {
        // 检查缓存
        if let cached = featureCache[asset.localIdentifier] {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            // 请求中等尺寸图像进行分析
            let targetSize = CGSize(width: 1024, height: 1024)

            imageManager.requestImage(for: asset,
                                     targetSize: targetSize,
                                     contentMode: .aspectFit,
                                     options: options) { image, info in
                guard let cgImage = image?.cgImage else {
                    continuation.resume(throwing: AnalysisError.imageLoadFailed)
                    return
                }

                // 在后台队列执行Vision分析
                self.visionQueue.async {
                    do {
                        let request = VNGenerateImageFeaturePrintRequest()
                        request.revision = VNGenerateImageFeaturePrintRequestRevision1

                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try handler.perform([request])

                        if let observation = request.results?.first as? VNFeaturePrintObservation {
                            // 缓存结果
                            self.featureCache[asset.localIdentifier] = observation
                            continuation.resume(returning: observation)
                        } else {
                            continuation.resume(throwing: AnalysisError.featureExtractionFailed)
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// 批量提取特征向量（优化性能）
    func extractFeatureVectors(for assets: [PHAsset]) async -> [String: VNFeaturePrintObservation] {
        var results: [String: VNFeaturePrintObservation] = [:]

        // 分批处理，避免内存压力
        let batchSize = 5
        for batch in assets.chunked(into: batchSize) {
            await withTaskGroup(of: (String, VNFeaturePrintObservation?).self) { group in
                for asset in batch {
                    group.addTask {
                        do {
                            if let feature = try await self.extractFeatureVector(for: asset) {
                                return (asset.localIdentifier, feature)
                            }
                        } catch {
                            print("提取特征失败 for \(asset.localIdentifier): \(error)")
                        }
                        return (asset.localIdentifier, nil)
                    }
                }

                for await (id, feature) in group {
                    if let feature = feature {
                        results[id] = feature
                    }
                }
            }
        }

        return results
    }

    // MARK: - 清晰度分析

    /// 分析照片清晰度（使用拉普拉斯方差）
    func analyzeClarity(for asset: PHAsset) async throws -> Float {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true

            let targetSize = CGSize(width: 512, height: 512)

            imageManager.requestImage(for: asset,
                                     targetSize: targetSize,
                                     contentMode: .aspectFit,
                                     options: options) { image, info in
                guard let cgImage = image?.cgImage else {
                    continuation.resume(returning: 0.5) // 默认值
                    return
                }

                let variance = self.calculateLaplacianVariance(cgImage: cgImage)
                // 归一化到0-1范围（经验值：方差>300为清晰，<100为模糊）
                let normalized = min(max((variance - 50) / 500, 0), 1)
                continuation.resume(returning: normalized)
            }
        }
    }

    private func calculateLaplacianVariance(cgImage: CGImage) -> Float {
        // 转换为CIImage
        let ciImage = CIImage(cgImage: cgImage)

        // 应用拉普拉斯滤波器
        let laplacianFilter = CIFilter.laplacian()
        laplacianFilter.inputImage = ciImage

        guard let outputImage = laplacianFilter.outputImage else {
            return 0
        }

        // 计算方差
        let extent = outputImage.extent
        let context = CIContext()

        guard let cgOutput = context.createCGImage(outputImage, from: extent) else {
            return 0
        }

        // 计算像素值的方差
        let width = cgOutput.width
        let height = cgOutput.height
        let bytesPerRow = cgOutput.bytesPerRow
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return 0
        }

        context.draw(cgOutput, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return 0
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        // 计算均值和方差
        var sum: Int = 0
        var count: Int = 0

        for i in 0..<width * height {
            sum += Int(pixels[i])
            count += 1
        }

        if count == 0 { return 0 }
        let mean = Float(sum) / Float(count)

        var varianceSum: Float = 0
        for i in 0..<width * height {
            let diff = Float(pixels[i]) - mean
            varianceSum += diff * diff
        }

        return varianceSum / Float(count)
    }

    // MARK: - 主体完整性分析

    /// 分析主体完整性
    func analyzeSubjectCompleteness(for asset: PHAsset) async throws -> Float {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true

            let targetSize = CGSize(width: 512, height: 512)

            imageManager.requestImage(for: asset,
                                     targetSize: targetSize,
                                     contentMode: .aspectFit,
                                     options: options) { image, info in
                guard let cgImage = image?.cgImage else {
                    continuation.resume(returning: 0.5) // 默认值
                    return
                }

                self.visionQueue.async {
                    do {
                        // 使用Vision检测主体
                        let request = VNGenerateAttentionBasedSaliencyImageRequest()
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try handler.perform([request])

                        if let result = request.results?.first as? VNSaliencyImageObservation {
                            // 计算主体区域覆盖率
                            let coverage = self.calculateSaliencyCoverage(saliencyObservation: result)
                            continuation.resume(returning: coverage)
                        } else {
                            continuation.resume(returning: 0.5)
                        }
                    } catch {
                        continuation.resume(returning: 0.5)
                    }
                }
            }
        }
    }

    private func calculateSaliencyCoverage(saliencyObservation: VNSaliencyImageObservation) -> Float {
        guard let salientObjects = saliencyObservation.salientObjects else {
            return 0.5
        }

        var totalArea: Float = 0
        for object in salientObjects {
            totalArea += object.boundingBox.width * object.boundingBox.height
        }

        // 如果主体区域覆盖图像面积较大，说明主体完整
        return min(totalArea * 2, 1.0) // 乘以2是因为saliency检测通常较保守
    }

    // MARK: - 人脸分析

    /// 分析人脸状态（眼睛是否睁开）
    func analyzeFace(for asset: PHAsset) async throws -> (eyesOpenScore: Float?, faceCount: Int) {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true

            let targetSize = CGSize(width: 512, height: 512)

            imageManager.requestImage(for: asset,
                                     targetSize: targetSize,
                                     contentMode: .aspectFit,
                                     options: options) { image, info in
                guard let cgImage = image?.cgImage else {
                    continuation.resume(returning: (nil, 0))
                    return
                }

                self.visionQueue.async {
                    do {
                        let request = VNDetectFaceRectanglesRequest()
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try handler.perform([request])

                        let faceCount = request.results?.count ?? 0

                        if faceCount == 0 {
                            continuation.resume(returning: (nil, 0))
                            return
                        }

                        // 如果有多个脸，取平均分数
                        var totalEyesOpenScore: Float = 0
                        var analyzedFaces = 0

                        for face in request.results ?? [] {
                            if let faceObservation = face as? VNFaceObservation {
                                // 这里简化处理，实际应该用VNDetectFaceLandmarksRequest
                                // 但为了性能，我们假设有脸的照片质量更好
                                totalEyesOpenScore += 0.8 // 假设眼睛睁开
                                analyzedFaces += 1
                            }
                        }

                        let averageScore = analyzedFaces > 0 ? totalEyesOpenScore / Float(analyzedFaces) : nil
                        continuation.resume(returning: (averageScore, faceCount))
                    } catch {
                        continuation.resume(returning: (nil, 0))
                    }
                }
            }
        }
    }

    // MARK: - 构图稳定性分析

    /// 分析构图稳定性
    func analyzeComposition(for asset: PHAsset) async throws -> Float {
        // 简化实现：检查水平线是否水平和主体是否居中
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true

            let targetSize = CGSize(width: 512, height: 512)

            imageManager.requestImage(for: asset,
                                     targetSize: targetSize,
                                     contentMode: .aspectFit,
                                     options: options) { image, info in
                // 这里简化返回一个基础分数
                // 实际实现应该分析水平线、三分法、对称性等
                continuation.resume(returning: 0.6) // 默认中等分数
            }
        }
    }

    // MARK: - 视觉相似度计算

    /// 计算两张照片的视觉相似度
    func calculateVisualSimilarity(feature1: VNFeaturePrintObservation,
                                  feature2: VNFeaturePrintObservation) throws -> Float {
        var distance: Float = 0
        try feature1.computeDistance(&distance, to: feature2)

        // 距离越小越相似，转换为相似度分数（0-1）
        let similarity = 1.0 / (1.0 + distance)
        return similarity
    }

    /// 计算照片与组内其他照片的平均相似度
    func calculateDuplicateScore(for assetId: String,
                                inGroup assetIds: [String],
                                features: [String: VNFeaturePrintObservation]) -> Float {
        guard let targetFeature = features[assetId] else {
            return 0
        }

        var totalSimilarity: Float = 0
        var count = 0

        for otherId in assetIds where otherId != assetId {
            if let otherFeature = features[otherId] {
                do {
                    let similarity = try calculateVisualSimilarity(feature1: targetFeature,
                                                                  feature2: otherFeature)
                    totalSimilarity += similarity
                    count += 1
                } catch {
                    continue
                }
            }
        }

        return count > 0 ? totalSimilarity / Float(count) : 0
    }

    // MARK: - 综合评分

    /// 为单张照片计算综合评分
    func calculateScore(for asset: PHAsset) async -> PhotoScore {
        var score = PhotoScore(id: asset.localIdentifier, asset: asset)

        // 并行计算各个维度
        async let clarity = analyzeClarity(for: asset)
        async let subjectCompleteness = analyzeSubjectCompleteness(for: asset)
        async let faceAnalysis = analyzeFace(for: asset)
        async let composition = analyzeComposition(for: asset)

        do {
            score.clarityScore = try await clarity
            score.subjectCompleteness = try await subjectCompleteness

            let faceResult = try await faceAnalysis
            score.eyesOpenScore = faceResult.eyesOpenScore

            score.compositionStability = try await composition
        } catch {
            print("计算照片评分失败: \(error)")
        }

        return score
    }

    /// 为组内所有照片计算评分（包含重复度计算）
    func calculateScores(for assets: [PHAsset]) async -> [PhotoScore] {
        // 提取特征向量（用于重复度计算）
        let features = await extractFeatureVectors(for: assets)
        let assetIds = assets.map { $0.localIdentifier }

        // 并行计算每张照片的评分
        var scores: [PhotoScore] = []
        await withTaskGroup(of: PhotoScore.self) { group in
            for asset in assets {
                group.addTask {
                    var score = await self.calculateScore(for: asset)

                    // 计算重复度
                    score.duplicateScore = self.calculateDuplicateScore(for: asset.localIdentifier,
                                                                       inGroup: assetIds,
                                                                       features: features)
                    return score
                }
            }

            for await score in group {
                scores.append(score)
            }
        }

        // 按总分排序
        return scores.sorted { $0.totalScore > $1.totalScore }
    }

    // MARK: - 工具方法

    /// 清空缓存
    func clearCache() {
        featureCache.removeAll()
    }
}

// MARK: - 错误类型

enum AnalysisError: Error {
    case imageLoadFailed
    case featureExtractionFailed
    case visionRequestFailed
}

// MARK: - 扩展

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}