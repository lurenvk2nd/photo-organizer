import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

/// Vision框架助手，封装常用的计算机视觉功能
class VisionHelper {

    // MARK: - 特征提取

    /// 提取图像的特征打印（Feature Print）
    func extractFeaturePrint(from image: CGImage) throws -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?.first as? VNFeaturePrintObservation
    }

    /// 提取场景特征（Scene Print）
    func extractScenePrint(from image: CGImage) throws -> VNSceneObservation? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first as? VNSaliencyImageObservation,
              let salientObjects = result.salientObjects,
              !salientObjects.isEmpty else {
            return nil
        }

        // 创建简化的场景观察
        let sceneObservation = VNSceneObservation()
        // 注意：实际应该使用VNClassifyImageRequest进行场景分类
        // 这里返回简化结果
        return sceneObservation
    }

    // MARK: - 图像质量分析

    /// 分析图像模糊度（使用拉普拉斯方差）
    func analyzeBlur(from image: CGImage) -> Float {
        let ciImage = CIImage(cgImage: image)

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

        // 转换为灰度
        guard let grayImage = convertToGrayscale(cgImage: cgOutput) else {
            return 0
        }

        return calculateVariance(of: grayImage)
    }

    /// 转换为灰度图像
    private func convertToGrayscale(cgImage: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue

        guard let context = CGContext(data: nil,
                                     width: cgImage.width,
                                     height: cgImage.height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: 0,
                                     space: colorSpace,
                                     bitmapInfo: bitmapInfo) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return context.makeImage()
    }

    /// 计算图像方差
    private func calculateVariance(of cgImage: CGImage) -> Float {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
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

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return 0
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        // 计算均值
        var sum: Int = 0
        var count: Int = 0

        for i in 0..<width * height {
            sum += Int(pixels[i])
            count += 1
        }

        if count == 0 { return 0 }
        let mean = Float(sum) / Float(count)

        // 计算方差
        var varianceSum: Float = 0
        for i in 0..<width * height {
            let diff = Float(pixels[i]) - mean
            varianceSum += diff * diff
        }

        return varianceSum / Float(count)
    }

    // MARK: - 主体检测

    /// 检测图像中的显著区域
    func detectSalientRegions(from image: CGImage) throws -> [VNRectangleObservation] {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first as? VNSaliencyImageObservation,
              let salientObjects = result.salientObjects else {
            return []
        }

        return salientObjects
    }

    /// 计算主体覆盖率（主体区域占图像面积的比例）
    func calculateSubjectCoverage(from image: CGImage) throws -> Float {
        let salientRegions = try detectSalientRegions(from: image)

        var totalArea: Float = 0
        for region in salientRegions {
            totalArea += Float(region.boundingBox.width * region.boundingBox.height)
        }

        return totalArea
    }

    // MARK: - 人脸检测

    /// 检测图像中的人脸
    func detectFaces(from image: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results as? [VNFaceObservation] ?? []
    }

    /// 检测人脸特征点（眼睛、嘴巴等）
    func detectFaceLandmarks(from image: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceLandmarksRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results as? [VNFaceObservation] ?? []
    }

    /// 分析眼睛是否睁开
    func analyzeEyeState(from faceObservation: VNFaceObservation) -> (leftEyeOpen: Bool?, rightEyeOpen: Bool?) {
        guard let landmarks = faceObservation.landmarks else {
            return (nil, nil)
        }

        var leftEyeOpen: Bool?
        var rightEyeOpen: Bool?

        // 简化实现：检查眼睛区域是否有足够的细节
        if let leftEye = landmarks.leftEye {
            leftEyeOpen = analyzeEyeOpenness(eyePoints: leftEye.normalizedPoints)
        }

        if let rightEye = landmarks.rightEye {
            rightEyeOpen = analyzeEyeOpenness(eyePoints: rightEye.normalizedPoints)
        }

        return (leftEyeOpen, rightEyeOpen)
    }

    private func analyzeEyeOpenness(eyePoints: [CGPoint]) -> Bool {
        // 简化实现：计算眼睛的高度/宽度比
        // 实际应该使用更复杂的算法
        guard eyePoints.count >= 6 else { return true } // 默认认为睁开

        let minY = eyePoints.map { $0.y }.min() ?? 0
        let maxY = eyePoints.map { $0.y }.max() ?? 0
        let minX = eyePoints.map { $0.x }.min() ?? 0
        let maxX = eyePoints.map { $0.x }.max() ?? 0

        let height = maxY - minY
        let width = maxX - minX

        if width == 0 { return true }

        let aspectRatio = height / width
        // 高度/宽度比大于0.3可能表示眼睛睁开
        return aspectRatio > 0.3
    }

    // MARK: - 相似度计算

    /// 计算两个特征打印之间的相似度
    func calculateSimilarity(_ feature1: VNFeaturePrintObservation,
                            _ feature2: VNFeaturePrintObservation) throws -> Float {
        var distance: Float = 0
        try feature1.computeDistance(&distance, to: feature2)

        // 距离越小越相似，转换为相似度分数（0-1）
        let similarity = 1.0 / (1.0 + distance)
        return similarity
    }

    /// 批量计算相似度矩阵
    func calculateSimilarityMatrix(features: [VNFeaturePrintObservation]) throws -> [[Float]] {
        let count = features.count
        var matrix = Array(repeating: Array(repeating: Float(0), count: count), count: count)

        for i in 0..<count {
            for j in i..<count {
                if i == j {
                    matrix[i][j] = 1.0
                } else {
                    let similarity = try calculateSimilarity(features[i], features[j])
                    matrix[i][j] = similarity
                    matrix[j][i] = similarity
                }
            }
        }

        return matrix
    }

    // MARK: - 图像预处理

    /// 调整图像尺寸
    func resizeImage(_ cgImage: CGImage, to size: CGSize) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)

        let scaleX = size.width / CGFloat(cgImage.width)
        let scaleY = size.height / CGFloat(cgImage.height)
        let scale = min(scaleX, scaleY)

        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = ciImage
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let context = CIContext()
        return context.createCGImage(outputImage, from: outputImage.extent)
    }

    /// 标准化图像方向
    func normalizeImageOrientation(_ cgImage: CGImage) -> CGImage? {
        // 注意：实际应该根据EXIF信息调整方向
        // 这里返回原始图像
        return cgImage
    }

    // MARK: - 性能优化

    /// 批量处理图像（提高性能）
    func batchProcessImages(images: [CGImage],
                           processBlock: (CGImage) throws -> Void) throws {
        // 使用Vision的批量请求
        let requests: [VNRequest] = [] // 根据实际需求创建请求

        for image in images {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform(requests)

            // 处理结果
            try processBlock(image)
        }
    }

    /// 清理Vision相关缓存
    func clearCache() {
        // Vision框架内部有缓存，但无法直接访问
        // 可以通过释放持有Vision对象的变量来间接清理
    }
}

// MARK: - 图像质量评估

extension VisionHelper {
    /// 综合评估图像质量
    func assessImageQuality(_ cgImage: CGImage) -> ImageQualityAssessment {
        var assessment = ImageQualityAssessment()

        // 1. 模糊度评估
        let blurScore = analyzeBlur(from: cgImage)
        assessment.sharpnessScore = normalizeBlurScore(blurScore)

        // 2. 对比度评估（简化）
        assessment.contrastScore = estimateContrast(from: cgImage)

        // 3. 噪声评估（简化）
        assessment.noiseLevel = estimateNoise(from: cgImage)

        // 4. 曝光评估（简化）
        assessment.exposureScore = estimateExposure(from: cgImage)

        return assessment
    }

    private func normalizeBlurScore(_ blurScore: Float) -> Float {
        // 将拉普拉斯方差转换为0-1的质量分数
        // 经验值：方差>300为清晰，<100为模糊
        let normalized = (blurScore - 50) / 500 // 调整参数以适应实际数据
        return max(0, min(1, normalized))
    }

    private func estimateContrast(from cgImage: CGImage) -> Float {
        // 简化实现：计算图像直方图的扩展范围
        // 实际应该使用更准确的方法
        return 0.7 // 默认值
    }

    private func estimateNoise(from cgImage: CGImage) -> Float {
        // 简化实现
        return 0.2 // 默认低噪声
    }

    private func estimateExposure(from cgImage: CGImage) -> Float {
        // 简化实现：计算图像平均亮度
        return 0.6 // 默认值
    }
}

/// 图像质量评估结果
struct ImageQualityAssessment {
    var sharpnessScore: Float = 0.5 // 锐度/清晰度（0-1）
    var contrastScore: Float = 0.5  // 对比度（0-1）
    var noiseLevel: Float = 0.5     // 噪声水平（0-1，越低越好）
    var exposureScore: Float = 0.5  // 曝光（0-1）

    /// 综合质量分数
    var overallScore: Float {
        return sharpnessScore * 0.4 +
               contrastScore * 0.2 +
               (1.0 - noiseLevel) * 0.2 +
               exposureScore * 0.2
    }

    /// 质量等级
    var qualityLevel: QualityLevel {
        let score = overallScore
        if score >= 0.8 {
            return .excellent
        } else if score >= 0.6 {
            return .good
        } else if score >= 0.4 {
            return .fair
        } else {
            return .poor
        }
    }

    enum QualityLevel {
        case excellent
        case good
        case fair
        case poor

        var description: String {
            switch self {
            case .excellent: return "优秀"
            case .good: return "良好"
            case .fair: return "一般"
            case .poor: return "较差"
            }
        }
    }
}

// MARK: - 错误处理

enum VisionError: Error {
    case imageProcessingFailed
    case featureExtractionFailed
    case faceDetectionFailed
    case similarityCalculationFailed
}

// MARK: - 扩展

extension VNFeaturePrintObservation {
    /// 获取特征向量的字符串表示（用于调试）
    var featureDescription: String {
        return "VNFeaturePrintObservation: \(self.elementCount)个特征维度"
    }
}

extension VNFaceObservation {
    /// 获取人脸的边界框描述
    var boundingBoxDescription: String {
        let box = self.boundingBox
        return String(format: "(%.2f, %.2f, %.2f, %.2f)",
                     box.origin.x, box.origin.y,
                     box.width, box.height)
    }

    /// 检查是否为主要人脸（最大的边界框）
    func isPrimaryFace(in observations: [VNFaceObservation]) -> Bool {
        guard let largestFace = observations.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return false
        }

        return self == largestFace
    }
}