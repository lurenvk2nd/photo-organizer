import Foundation
import CoreData

/// 用户选择记录，存储在Core Data中
@objc(UserSelection)
class UserSelection: NSManagedObject {
    @NSManaged var groupId: String
    @NSManaged var primaryPhotoId: String?
    @NSManaged var keptPhotoIds: [String] // 用户最终保留的照片ID
    @NSManaged var deletedPhotoIds: [String] // 用户删除的照片ID
    @NSManaged var selectionDate: Date
    @NSManaged var isAcceptedRecommendation: Bool // 是否一键接受推荐

    /// 便捷初始化方法
    convenience init(context: NSManagedObjectContext,
                    groupId: String,
                    primaryPhotoId: String? = nil,
                    keptPhotoIds: [String] = [],
                    deletedPhotoIds: [String] = [],
                    isAcceptedRecommendation: Bool = false) {
        self.init(entity: UserSelection.entity(), insertInto: context)
        self.groupId = groupId
        self.primaryPhotoId = primaryPhotoId
        self.keptPhotoIds = keptPhotoIds
        self.deletedPhotoIds = deletedPhotoIds
        self.selectionDate = Date()
        self.isAcceptedRecommendation = isAcceptedRecommendation
    }

    /// 检查照片是否已被处理过
    static func isPhotoProcessed(_ photoId: String, in context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<UserSelection> = UserSelection.fetchRequest()
        request.predicate = NSPredicate(format: "keptPhotoIds CONTAINS %@ OR deletedPhotoIds CONTAINS %@", photoId, photoId)

        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("检查照片处理状态失败: \(error)")
            return false
        }
    }

    /// 获取所有已处理照片ID
    static func allProcessedPhotoIds(in context: NSManagedObjectContext) -> Set<String> {
        let request: NSFetchRequest<UserSelection> = UserSelection.fetchRequest()

        do {
            let selections = try context.fetch(request)
            var allIds = Set<String>()

            for selection in selections {
                allIds.formUnion(selection.keptPhotoIds)
                allIds.formUnion(selection.deletedPhotoIds)
            }

            return allIds
        } catch {
            print("获取已处理照片失败: \(error)")
            return []
        }
    }

    /// 获取指定组的处理记录
    static func selection(for groupId: String, in context: NSManagedObjectContext) -> UserSelection? {
        let request: NSFetchRequest<UserSelection> = UserSelection.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %@", groupId)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            print("获取组选择记录失败: \(error)")
            return nil
        }
    }

    /// 删除指定组的处理记录
    static func deleteSelection(for groupId: String, in context: NSManagedObjectContext) throws {
        if let selection = selection(for: groupId, in: context) {
            context.delete(selection)
            try context.save()
        }
    }

    /// 批量删除处理记录
    static func deleteSelections(for groupIds: [String], in context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<UserSelection> = UserSelection.fetchRequest()
        request.predicate = NSPredicate(format: "groupId IN %@", groupIds)

        let selections = try context.fetch(request)
        for selection in selections {
            context.delete(selection)
        }

        try context.save()
    }
}

// Core Data扩展
extension UserSelection {
    @nonobjc class func fetchRequest() -> NSFetchRequest<UserSelection> {
        return NSFetchRequest<UserSelection>(entityName: "UserSelection")
    }
}

/// 用户选择管理器
class UserSelectionManager {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// 保存用户选择
    func saveSelection(groupId: String,
                      primaryPhotoId: String?,
                      keptPhotoIds: [String],
                      deletedPhotoIds: [String],
                      isAcceptedRecommendation: Bool) throws {
        // 删除旧的记录（如果存在）
        if let existing = UserSelection.selection(for: groupId, in: context) {
            context.delete(existing)
        }

        // 创建新记录
        let selection = UserSelection(context: context,
                                     groupId: groupId,
                                     primaryPhotoId: primaryPhotoId,
                                     keptPhotoIds: keptPhotoIds,
                                     deletedPhotoIds: deletedPhotoIds,
                                     isAcceptedRecommendation: isAcceptedRecommendation)

        try context.save()
    }

    /// 一键接受推荐
    func acceptRecommendation(groupId: String,
                            primaryPhotoId: String,
                            suggestedPhotoIds: [String]) throws {
        // 其他照片都标记为删除
        let allPhotoIds = suggestedPhotoIds + [primaryPhotoId]
        let deletedPhotoIds = allPhotoIds.filter { $0 != primaryPhotoId }

        try saveSelection(groupId: groupId,
                         primaryPhotoId: primaryPhotoId,
                         keptPhotoIds: [primaryPhotoId],
                         deletedPhotoIds: deletedPhotoIds,
                         isAcceptedRecommendation: true)
    }

    /// 获取需要删除的照片（用于批量操作）
    func photosToDelete() -> [String] {
        let request: NSFetchRequest<UserSelection> = UserSelection.fetchRequest()

        do {
            let selections = try context.fetch(request)
            var allDeletedIds: [String] = []

            for selection in selections {
                allDeletedIds.append(contentsOf: selection.deletedPhotoIds)
            }

            return allDeletedIds
        } catch {
            print("获取待删除照片失败: \(error)")
            return []
        }
    }

    /// 获取统计信息
    func getStatistics() -> (kept: Int, deleted: Int, groups: Int) {
        let request: NSFetchRequest<UserSelection> = UserSelection.fetchRequest()

        do {
            let selections = try context.fetch(request)
            var totalKept = 0
            var totalDeleted = 0

            for selection in selections {
                totalKept += selection.keptPhotoIds.count
                totalDeleted += selection.deletedPhotoIds.count
            }

            return (totalKept, totalDeleted, selections.count)
        } catch {
            print("获取统计信息失败: \(error)")
            return (0, 0, 0)
        }
    }
}