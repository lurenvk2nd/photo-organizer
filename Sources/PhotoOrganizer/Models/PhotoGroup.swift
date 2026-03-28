import Foundation
import Photos

/// 照片组模型，表示同一场景下的照片集合
struct PhotoGroup: Identifiable, Equatable {
    let id: UUID
    var photos: [PHAsset]
    var creationDate: Date?
    var location: CLLocation?
    var groupReason: GroupReason

    /// 分组原因
    enum GroupReason {
        case timeProximity(threshold: TimeInterval)
        case locationProximity(threshold: CLLocationDistance)
        case visualSimilarity(threshold: Float)
        case combined
    }

    init(id: UUID = UUID(), photos: [PHAsset], creationDate: Date? = nil, location: CLLocation? = nil, groupReason: GroupReason = .combined) {
        self.id = id
        self.photos = photos
        self.creationDate = creationDate
        self.location = location
        self.groupReason = groupReason
    }

    static func == (lhs: PhotoGroup, rhs: PhotoGroup) -> Bool {
        lhs.id == rhs.id
    }

    /// 获取组的时间范围（秒）
    var timeRange: TimeInterval? {
        guard let firstDate = photos.compactMap({ $0.creationDate }).min(),
              let lastDate = photos.compactMap({ $0.creationDate }).max() else {
            return nil
        }
        return lastDate.timeIntervalSince(firstDate)
    }

    /// 获取组的地点中心
    var centerLocation: CLLocation? {
        let locations = photos.compactMap { $0.location }
        guard !locations.isEmpty else { return nil }

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

    /// 获取组的描述信息
    var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var parts: [String] = []

        if let date = creationDate {
            parts.append(dateFormatter.string(from: date))
        }

        if photos.count > 1 {
            parts.append("\(photos.count)张照片")
        }

        switch groupReason {
        case .timeProximity(let threshold):
            parts.append("时间相近(\(Int(threshold))秒内)")
        case .locationProximity(let threshold):
            parts.append("地点相近(\(Int(threshold))米内)")
        case .visualSimilarity(let threshold):
            parts.append("画面相似(相似度\(Int(threshold * 100))%)")
        case .combined:
            parts.append("相似场景")
        }

        return parts.joined(separator: " · ")
    }
}