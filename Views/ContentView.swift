import SwiftUI
import Photos

/// 主内容视图，应用的主要导航入口
struct ContentView: View {
    @StateObject private var groupingViewModel = GroupingViewModel()
    @StateObject private var recommendationViewModel = RecommendationViewModel()
    @State private var selectedTab: AppTab = .grouping
    @State private var showingSettings = false
    @State private var showingExport = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // 分组标签页
            GroupListView(viewModel: groupingViewModel,
                         recommendationViewModel: recommendationViewModel)
                .tabItem {
                    Label("分组", systemImage: "square.grid.2x2")
                }
                .tag(AppTab.grouping)

            // 推荐标签页
            RecommendationView(viewModel: recommendationViewModel)
                .tabItem {
                    Label("推荐", systemImage: "star")
                }
                .tag(AppTab.recommendation)

            // 处理标签页
            ProcessingView(groupingViewModel: groupingViewModel,
                          recommendationViewModel: recommendationViewModel)
                .tabItem {
                    Label("处理", systemImage: "checkmark.circle")
                }
                .tag(AppTab.processing)
        }
        .navigationTitle(selectedTab.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == .grouping && !groupingViewModel.photoGroups.isEmpty {
                    Button(action: { showingExport = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingExport) {
            ExportView(groups: groupingViewModel.photoGroups,
                      statistics: groupingViewModel.statistics)
        }
        .alert("错误", isPresented: .constant(groupingViewModel.errorMessage != nil ||
                                           recommendationViewModel.errorMessage != nil)) {
            Button("确定") {
                groupingViewModel.errorMessage = nil
                recommendationViewModel.errorMessage = nil
            }
        } message: {
            Text(groupingViewModel.errorMessage ?? recommendationViewModel.errorMessage ?? "")
        }
    }
}

// MARK: - 标签枚举

enum AppTab {
    case grouping
    case recommendation
    case processing

    var title: String {
        switch self {
        case .grouping: return "照片分组"
        case .recommendation: return "智能推荐"
        case .processing: return "批量处理"
        }
    }

    var icon: String {
        switch self {
        case .grouping: return "square.grid.2x2"
        case .recommendation: return "star"
        case .processing: return "checkmark.circle"
        }
    }
}

// MARK: - 预览

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 15 Pro")
    }
}

// MARK: - 应用主入口

@main
struct PhotoOrganizerApp: App {
    // 初始化Core Data上下文
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

// MARK: - Persistence Controller

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PhotoOrganizer")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data加载失败: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}