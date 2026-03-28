import SwiftUI
import Photos

/// 设置视图，管理应用配置和偏好
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("groupingTimeThreshold") private var timeThreshold: Double = 30
    @AppStorage("groupingDistanceThreshold") private var distanceThreshold: Double = 50
    @AppStorage("visualSimilarityThreshold") private var similarityThreshold: Double = 85
    @AppStorage("autoAcceptRecommendations") private var autoAcceptRecommendations = false
    @AppStorage("showDetailedExplanations") private var showDetailedExplanations = true
    @AppStorage("keepOriginalPhotos") private var keepOriginalPhotos = true
    @AppStorage("enableiCloudSync") private var enableiCloudSync = false
    @State private var showingResetConfirmation = false
    @State private var showingPermissions = false
    @State private var photoLibraryStatus: PHAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationView {
            Form {
                // 分组设置
                groupingSettingsSection

                // 推荐设置
                recommendationSettingsSection

                // 隐私与安全
                privacySettingsSection

                // 关于
                aboutSection

                // 重置选项
                resetSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkPhotoLibraryStatus()
            }
            .alert("重置设置", isPresented: $showingResetConfirmation) {
                Button("取消", role: .cancel) { }
                Button("重置", role: .destructive) {
                    resetSettings()
                }
            } message: {
                Text("这将重置所有设置为默认值，此操作不可撤销。")
            }
        }
    }

    // MARK: - 分组设置

    private var groupingSettingsSection: some View {
        Section {
            // 时间阈值
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("时间分组阈值")
                    Spacer()
                    Text("\(Int(timeThreshold))秒")
                        .foregroundColor(.secondary)
                }

                Slider(value: $timeThreshold, in: 5...120, step: 5) {
                    Text("时间阈值")
                } minimumValueLabel: {
                    Text("5s")
                } maximumValueLabel: {
                    Text("120s")
                }
            }
            .padding(.vertical, 4)

            // 距离阈值
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("地点分组阈值")
                    Spacer()
                    Text("\(Int(distanceThreshold))米")
                        .foregroundColor(.secondary)
                }

                Slider(value: $distanceThreshold, in: 10...200, step: 10) {
                    Text("距离阈值")
                } minimumValueLabel: {
                    Text("10m")
                } maximumValueLabel: {
                    Text("200m")
                }
            }
            .padding(.vertical, 4)

            // 视觉相似度阈值
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("视觉相似度阈值")
                    Spacer()
                    Text("\(Int(similarityThreshold))%")
                        .foregroundColor(.secondary)
                }

                Slider(value: $similarityThreshold, in: 70...95, step: 5) {
                    Text("相似度阈值")
                } minimumValueLabel: {
                    Text("70%")
                } maximumValueLabel: {
                    Text("95%")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("分组设置")
        } footer: {
            Text("调整分组算法的敏感度。较小的值会产生更多、更精细的分组。")
        }
    }

    // MARK: - 推荐设置

    private var recommendationSettingsSection: some View {
        Section {
            Toggle("自动接受推荐", isOn: $autoAcceptRecommendations)

            Toggle("显示详细解释", isOn: $showDetailedExplanations)

            Toggle("保留原始照片", isOn: $keepOriginalPhotos)
                .disabled(!autoAcceptRecommendations)
        } header: {
            Text("推荐设置")
        } footer: {
            if autoAcceptRecommendations {
                Text("启用后，系统推荐的最高质量照片会自动标记为保留。")
            }
        }
    }

    // MARK: - 隐私设置

    private var privacySettingsSection: some View {
        Section {
            // 照片库权限
            Button(action: {
                showingPermissions = true
            }) {
                HStack {
                    Image(systemName: photoLibraryStatusIcon)
                        .foregroundColor(photoLibraryStatusColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("照片库权限")
                            .foregroundColor(.primary)

                        Text(photoLibraryStatusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Toggle("iCloud同步", isOn: $enableiCloudSync)
                .disabled(true) // 暂时禁用

            // 数据管理
            NavigationLink {
                DataManagementView()
            } label: {
                Label("数据管理", systemImage: "externaldrive")
            }
        } header: {
            Text("隐私与安全")
        } footer: {
            Text("所有照片分析都在设备端完成，不会上传到云端。")
        }
        .sheet(isPresented: $showingPermissions) {
            PermissionsView()
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            // 版本信息
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }

            // 开发者信息
            NavigationLink {
                DeveloperInfoView()
            } label: {
                Label("开发者信息", systemImage: "person")
            }

            // 帮助与反馈
            Link(destination: URL(string: "https://example.com/help")!) {
                Label("帮助与反馈", systemImage: "questionmark.circle")
            }

            // 隐私政策
            Link(destination: URL(string: "https://example.com/privacy")!) {
                Label("隐私政策", systemImage: "hand.raised")
            }

            // 使用条款
            Link(destination: URL(string: "https://example.com/terms")!) {
                Label("使用条款", systemImage: "doc.text")
            }
        } header: {
            Text("关于")
        }
    }

    // MARK: - 重置

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("重置所有设置", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 权限状态

    private var photoLibraryStatusIcon: String {
        switch photoLibraryStatus {
        case .authorized, .limited:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private var photoLibraryStatusColor: Color {
        switch photoLibraryStatus {
        case .authorized, .limited:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var photoLibraryStatusDescription: String {
        switch photoLibraryStatus {
        case .authorized:
            return "完全访问权限"
        case .limited:
            return "受限访问权限"
        case .denied:
            return "访问被拒绝"
        case .restricted:
            return "访问受限"
        case .notDetermined:
            return "未请求权限"
        @unknown default:
            return "未知状态"
        }
    }

    // MARK: - 方法

    private func checkPhotoLibraryStatus() {
        photoLibraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func resetSettings() {
        timeThreshold = 30
        distanceThreshold = 50
        similarityThreshold = 85
        autoAcceptRecommendations = false
        showDetailedExplanations = true
        keepOriginalPhotos = true
        enableiCloudSync = false
    }
}

// MARK: - 数据管理视图

struct DataManagementView: View {
    @State private var cacheSize: String = "计算中..."
    @State private var showingClearCacheConfirmation = false
    @State private var showingClearDataConfirmation = false

    var body: some View {
        Form {
            Section {
                // 缓存大小
                HStack {
                    Text("缓存大小")
                    Spacer()
                    Text(cacheSize)
                        .foregroundColor(.secondary)
                }

                // 清理缓存
                Button(role: .destructive) {
                    showingClearCacheConfirmation = true
                } label: {
                    Label("清理分析缓存", systemImage: "trash")
                }
            } header: {
                Text("存储管理")
            } footer: {
                Text("清理缓存不会影响您的照片，只会删除分析过程中生成的临时数据。")
            }

            Section {
                // 清理所有数据
                Button(role: .destructive) {
                    showingClearDataConfirmation = true
                } label: {
                    Label("清理所有数据", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("数据重置")
            } footer: {
                Text("这将删除所有选择记录和设置，但不会删除您的照片。")
            }
        }
        .navigationTitle("数据管理")
        .onAppear {
            calculateCacheSize()
        }
        .alert("清理缓存", isPresented: $showingClearCacheConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                clearCache()
            }
        } message: {
            Text("这将删除所有分析缓存，下次分析可能需要更长时间。")
        }
        .alert("清理所有数据", isPresented: $showingClearDataConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("这将重置应用的所有数据和设置，此操作不可撤销。")
        }
    }

    private func calculateCacheSize() {
        // 这里应该实际计算缓存大小
        // 简化实现
        cacheSize = "约50MB"
    }

    private func clearCache() {
        // 清理缓存逻辑
        cacheSize = "0MB"
    }

    private func clearAllData() {
        // 清理所有数据逻辑
        clearCache()
    }
}

// MARK: - 权限视图

struct PermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photoLibraryStatus: PHAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 图标
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .padding(.top)

                    // 标题
                    VStack(spacing: 8) {
                        Text("照片库权限")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("需要访问您的照片库以进行智能分组和推荐")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    // 权限状态
                    VStack(spacing: 16) {
                        PermissionStatusView(
                            icon: photoLibraryStatusIcon,
                            title: "照片库访问",
                            status: photoLibraryStatusDescription,
                            color: photoLibraryStatusColor
                        )
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // 说明
                    VStack(alignment: .leading, spacing: 12) {
                        PermissionFeatureView(
                            icon: "magnifyingglass",
                            title: "智能分析",
                            description: "分析照片质量、内容和相似度"
                        )

                        PermissionFeatureView(
                            icon: "square.grid.2x2",
                            title: "自动分组",
                            description: "按时间、地点和画面相似度分组"
                        )

                        PermissionFeatureView(
                            icon: "star",
                            title: "智能推荐",
                            description: "推荐最佳照片并建议删除重复项"
                        )
                    }
                    .padding()

                    // 隐私保证
                    VStack(spacing: 8) {
                        Text("隐私保证")
                            .font(.headline)

                        Text("• 所有分析都在设备端完成\n• 不会上传照片到云端\n• 不会收集个人身份信息")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // 操作按钮
                    if photoLibraryStatus != .authorized && photoLibraryStatus != .limited {
                        Button(action: requestPhotoLibraryAccess) {
                            Text("授予权限")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
            }
            .navigationTitle("权限管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkPhotoLibraryStatus()
            }
        }
    }

    private var photoLibraryStatusIcon: String {
        switch photoLibraryStatus {
        case .authorized, .limited:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private var photoLibraryStatusColor: Color {
        switch photoLibraryStatus {
        case .authorized, .limited:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var photoLibraryStatusDescription: String {
        switch photoLibraryStatus {
        case .authorized:
            return "完全访问权限"
        case .limited:
            return "受限访问权限"
        case .denied:
            return "访问被拒绝"
        case .restricted:
            return "访问受限"
        case .notDetermined:
            return "未请求权限"
        @unknown default:
            return "未知状态"
        }
    }

    private func checkPhotoLibraryStatus() {
        photoLibraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func requestPhotoLibraryAccess() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                photoLibraryStatus = status
            }
        }
    }
}

struct PermissionStatusView: View {
    let icon: String
    let title: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct PermissionFeatureView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 开发者信息视图

struct DeveloperInfoView: View {
    var body: some View {
        Form {
            Section {
                // 应用信息
                InfoRowView(title: "应用名称", value: "照片整理助手")
                InfoRowView(title: "版本", value: "1.0.0")
                InfoRowView(title: "构建版本", value: "1000")
            } header: {
                Text("应用信息")
            }

            Section {
                // 开发者信息
                InfoRowView(title: "开发者", value: "照片整理团队")
                InfoRowView(title: "联系方式", value: "support@example.com")
                InfoRowView(title: "官方网站", value: "https://example.com")
            } header: {
                Text("开发者信息")
            }

            Section {
                // 技术信息
                InfoRowView(title: "框架", value: "SwiftUI + Photos + Vision")
                InfoRowView(title: "最低系统版本", value: "iOS 16.0")
                InfoRowView(title: "数据存储", value: "Core Data")
            } header: {
                Text("技术信息")
            }

            Section {
                // 开源许可
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("开源许可", systemImage: "doc.text")
                }
            } header: {
                Text("法律信息")
            }
        }
        .navigationTitle("开发者信息")
    }
}

struct InfoRowView: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("开源许可")
                    .font(.title)
                    .padding(.bottom)

                LicenseView(
                    name: "SwiftUI",
                    license: "Apple MIT License",
                    description: "Apple Inc. 提供的用户界面框架"
                )

                LicenseView(
                    name: "Photos Framework",
                    license: "Apple MIT License",
                    description: "Apple Inc. 提供的照片库访问框架"
                )

                LicenseView(
                    name: "Vision Framework",
                    license: "Apple MIT License",
                    description: "Apple Inc. 提供的计算机视觉框架"
                )

                LicenseView(
                    name: "Core Data",
                    license: "Apple MIT License",
                    description: "Apple Inc. 提供的数据持久化框架"
                )

                Spacer()
            }
            .padding()
        }
        .navigationTitle("开源许可")
    }
}

struct LicenseView: View {
    let name: String
    let license: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)

            Text(license)
                .font(.subheadline)
                .foregroundColor(.blue)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - 预览

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}