import SwiftUI
import UIKit
import PhotosUI

// MARK: - PersonaContactsView
//
// 微信/QQ 风格的人设通讯录：
// - 原生全屏 Navigation 页面（非抽屉），可从底栏一键推入
// - 顶部通讯录列表，点击任一人设进入人设主页（PersonaDetailHomeView）
// - 支持右上角添加新人设、左滑快捷删除与复制

struct PersonaContactsView: View {
    @ObservedObject var store = PersonaStore.shared
    @Environment(\.dismiss) private var dismiss
    var onSelectAndChat: ((Persona) -> Void)?

    @State private var searchText = ""
    @State private var showNewSheet = false
    @State private var newName = ""
    @State private var deleteTarget: Persona?

    private var filteredPersonas: [Persona] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return store.personas
        }
        return store.personas.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredPersonas) { persona in
                    NavigationLink {
                        PersonaDetailHomeView(personaId: persona.id, onSelectAndChat: onSelectAndChat)
                    } label: {
                        HStack(spacing: 14) {
                            PersonaAvatarView(iconRef: persona.avatar, size: 46)
                                .overlay(
                                    Circle()
                                        .stroke(persona.id == store.currentPersonaID ? MinisThemeList.accent : Color.clear, lineWidth: 2)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(persona.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(ChatColors.primaryText)

                                    if persona.isBuiltIn {
                                        Text("内置")
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                            .foregroundStyle(.secondary)
                                    }

                                    if persona.id == store.currentPersonaID {
                                        Text("使用中")
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(MinisThemeList.accent.opacity(0.15)))
                                            .foregroundStyle(MinisThemeList.accent)
                                    }
                                }

                                Text(personaBio(for: persona))
                                    .font(.system(size: 12))
                                    .foregroundStyle(ChatColors.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !persona.isBuiltIn && store.personas.count > 1 {
                            Button(role: .destructive) {
                                deleteTarget = persona
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        Button {
                            _ = store.duplicatePersona(persona.id)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                }
            } header: {
                Text("所有联系人")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ChatColors.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索联系人")
        .navigationTitle("通讯录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showNewSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .alert("新建联系人", isPresented: $showNewSheet) {
            TextField("联系人名字", text: $newName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                _ = store.addPersona(name: trimmed)
            }
        }
        .alert("确认删除联系人", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let target = deleteTarget {
                    store.deletePersona(target.id)
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("确定要删除「\(target.name)」吗？该人设的专属记忆与历史会话将一并清理。")
            }
        }
    }

    private func personaBio(for persona: Persona) -> String {
        let soulURL = PersonaStore.memoryDir(for: persona.id).appendingPathComponent("SOUL.md")
        if let text = try? String(contentsOf: soulURL, encoding: .utf8), !text.isEmpty {
            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return lines.first?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) ?? "点击微调此人设"
        }
        return persona.isBuiltIn ? "系统内置专属助手" : "点击微调此人设"
    }
}

// MARK: - PersonaDetailHomeView (复刻 Kelivo 人设主页)

struct PersonaDetailHomeView: View {
    let personaId: String
    var onSelectAndChat: ((Persona) -> Void)?

    @ObservedObject var store = PersonaStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    private var persona: Persona? {
        store.personas.first { $0.id == personaId }
    }

    var body: some View {
        Group {
            if let p = persona {
                List {
                    // Header: 大圆头像 + 名字
                    Section {
                        VStack(spacing: 12) {
                            Button {
                                showPhotoPicker = true
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    PersonaAvatarView(iconRef: p.avatar, size: 84)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(p.id == store.currentPersonaID ? MinisThemeList.accent : Color.secondary.opacity(0.2), lineWidth: 3))
                                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)

                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.white)
                                        .padding(5)
                                        .background(Circle().fill(MinisThemeList.accent))
                                        .offset(x: -2, y: -2)
                                }
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 6) {
                                Text(p.name)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(ChatColors.primaryText)

                                Button {
                                    renameText = p.name
                                    showRenameAlert = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            if p.id == store.currentPersonaID {
                                Text("当前活跃人设")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(MinisThemeList.accent.opacity(0.16)))
                                    .foregroundStyle(MinisThemeList.accent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .listRowBackground(Color.clear)

                    // 9 大子项导航 (完全对标 Kelivo)
                    Section {
                        NavigationLink {
                            PersonaBasicSettingsView(personaId: p.id)
                        } label: {
                            Label {
                                Text("基础设置")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(MinisThemeList.accent)
                            }
                        }

                        NavigationLink {
                            PersonaPromptSettingsView(personaId: p.id)
                        } label: {
                            Label {
                                Text("提示词")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.blue)
                            }
                        }

                        NavigationLink {
                            PersonaMemorySettingsView(personaId: p.id)
                        } label: {
                            Label {
                                Text("记忆")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "brain")
                                    .foregroundStyle(.purple)
                            }
                        }

                        NavigationLink {
                            PersonaLocalToolsSettingsView(personaId: p.id)
                        } label: {
                            Label {
                                HStack {
                                    Text("本地工具")
                                        .font(.system(size: 16))
                                    Spacer()
                                    let enabledCount = p.localToolIds?.count ?? LocalToolRegistry.all.count
                                    Text("\(enabledCount)/\(LocalToolRegistry.all.count)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "wrench.and.screwdriver")
                                    .foregroundStyle(.orange)
                            }
                        }

                        NavigationLink {
                            PersonaSkillsSettingsView(personaId: p.id)
                        } label: {
                            Label {
                                Text("技能")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.yellow)
                            }
                        }

                        NavigationLink {
                            PersonaMcpSettingsView(personaId: p.id)
                        } label: {
                            Label {
                                Text("MCP")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "terminal")
                                    .foregroundStyle(.green)
                            }
                        }

                        NavigationLink {
                            PersonaSimpleSubpageView(title: "快捷短语", icon: "bolt", hint: "为该助手配置常用快捷短语。输入时支持一键呼出。")
                        } label: {
                            Label {
                                Text("快捷短语")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "bolt")
                                    .foregroundStyle(.red)
                            }
                        }

                        NavigationLink {
                            PersonaSimpleSubpageView(title: "自定义请求", icon: "bubble.left.and.exclamationmark.bubble.right", hint: "为该助手注入独立的请求头与自定义请求体参数。")
                        } label: {
                            Label {
                                Text("自定义请求")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                                    .foregroundStyle(.teal)
                            }
                        }

                        NavigationLink {
                            PersonaSimpleSubpageView(title: "正则替换", icon: "textformat", hint: "为该助手的回答输出配置正则匹配与替换清洗规则。")
                        } label: {
                            Label {
                                Text("正则替换")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "textformat")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 底部开始对话按钮
                    Section {
                        Button {
                            store.setCurrent(p.id)
                            onSelectAndChat?(p)
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("与 Ta 对话")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .foregroundStyle(MinisThemeList.accent)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(p.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                store.setCurrent(p.id)
                            } label: {
                                Label("设为当前活跃人设", systemImage: "checkmark.circle")
                            }

                            Button {
                                if let copy = store.duplicatePersona(p.id) {
                                    store.setCurrent(copy.id)
                                }
                            } label: {
                                Label("复制为人设副本", systemImage: "doc.on.doc")
                            }

                            if !p.isBuiltIn && store.personas.count > 1 {
                                Button(role: .destructive) {
                                    store.deletePersona(p.id)
                                    dismiss()
                                } label: {
                                    Label("删除人设", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16))
                        }
                    }
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { newItem in
                    guard let item = newItem else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            saveAvatarImage(image, for: p)
                        }
                    }
                }
                .alert("重命名人设", isPresented: $showRenameAlert) {
                    TextField("人设名字", text: $renameText)
                    Button("取消", role: .cancel) {}
                    Button("保存") {
                        store.renamePersona(p.id, to: renameText)
                    }
                }
            } else {
                Text("人设不存在或已被删除")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveAvatarImage(_ image: UIImage, for p: Persona) {
        let maxDim: CGFloat = 256
        let scale = min(maxDim / image.size.width, maxDim / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        guard let pngData = resized.pngData() else { return }

        let name = "persona_\(p.id).png"
        let dir = AIChatViewModel.minisMemoryPersistentDir.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(name)
        try? pngData.write(to: fileURL, options: .atomic)

        var updated = p
        updated.avatar = "avatars/\(name)"
        store.updatePersona(updated)
    }
}

// MARK: - 1. PersonaBasicSettingsView (复刻 photo_9459470E.png 基础设置)

struct PersonaBasicSettingsView: View {
    let personaId: String
    @ObservedObject var store = PersonaStore.shared

    @State private var tempValue: Double = 1.0
    @State private var tempEnabled: Bool = false
    @State private var showTempSheet = false

    @State private var topPValue: Double = 1.0
    @State private var topPEnabled: Bool = false
    @State private var showTopPSheet = false

    @State private var showContextSheet = false
    @State private var contextLimitEnabled: Bool = false
    @State private var contextMessageCount: Int = 20

    @State private var showThinkingBudgetSheet = false
    @State private var thinkingBudgetEnabled: Bool = false
    @State private var thinkingBudgetValue: Int = 4096

    @State private var showMaxTokensSheet = false
    @State private var maxTokensEnabled: Bool = false
    @State private var maxTokensValue: Int = 4096

    @State private var showModelPicker = false
    @State private var showBackgroundPhotoPicker = false
    @State private var backgroundPhotoItem: PhotosPickerItem?

    private var persona: Persona? {
        store.personas.first { $0.id == personaId }
    }

    var body: some View {
        Group {
            if let p = persona {
                List {
                    // Group 1: 采样与推理参数
                    Section {
                        // Temperature
                        Button {
                            showTempSheet = true
                        } label: {
                            HStack {
                                Label {
                                    Text("Temperature")
                                        .font(.system(size: 16))
                                } icon: {
                                    Image(systemName: "thermometer")
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                Text(p.temperature != nil ? String(format: "%.2f", p.temperature!) : "已关闭 (使用服务商默认)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        // Top P
                        Button {
                            showTopPSheet = true
                        } label: {
                            HStack {
                                Label {
                                    Text("Top P")
                                        .font(.system(size: 16))
                                } icon: {
                                    Image(systemName: "rays")
                                        .foregroundStyle(.blue)
                                }
                                Spacer()
                                Text(p.topP != nil ? String(format: "%.2f", p.topP!) : "已关闭 (使用服务商默认)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        // 上下文消息数量
                        Button {
                            showContextSheet = true
                        } label: {
                            HStack {
                                Label {
                                    Text("上下文消息数量")
                                        .font(.system(size: 16))
                                } icon: {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .foregroundStyle(.green)
                                }
                                Spacer()
                                Text(p.limitContextMessages ? "\(p.contextMessageSize) 条" : "已关闭 (无限制)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        // 思考预算
                        Button {
                            showThinkingBudgetSheet = true
                        } label: {
                            HStack {
                                Label {
                                    Text("思考预算")
                                        .font(.system(size: 16))
                                } icon: {
                                    Image(systemName: "brain")
                                        .foregroundStyle(.purple)
                                }
                                Spacer()
                                Text(p.thinkingBudget != nil ? "\(p.thinkingBudget!)" : "-")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        // 最大 Token 数
                        Button {
                            showMaxTokensSheet = true
                        } label: {
                            HStack {
                                Label {
                                    Text("最大 Token 数")
                                        .font(.system(size: 16))
                                } icon: {
                                    Image(systemName: "number")
                                        .foregroundStyle(.teal)
                                }
                                Spacer()
                                Text(p.maxTokens != nil ? "\(p.maxTokens!)" : "无限制")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        // 默认工作区
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("默认工作区")
                                        .font(.system(size: 16))
                                    Text("新建对话时自动绑定，已有对话不受影响。")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder")
                                    .foregroundStyle(.indigo)
                            }
                            Spacer()
                            Text(p.defaultWorkspace ?? "无")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }

                        // 使用助手头像
                        Toggle(isOn: Binding(
                            get: { p.useAssistantAvatar },
                            set: { val in
                                var updated = p
                                updated.useAssistantAvatar = val
                                store.updatePersona(updated)
                            }
                        )) {
                            Label {
                                Text("使用助手头像")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "person.circle")
                                    .foregroundStyle(.pink)
                            }
                        }

                        // 使用助手名字
                        Toggle(isOn: Binding(
                            get: { p.useAssistantName },
                            set: { val in
                                var updated = p
                                updated.useAssistantName = val
                                store.updatePersona(updated)
                            }
                        )) {
                            Label {
                                Text("使用助手名字")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "textformat")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 流式输出
                        Toggle(isOn: Binding(
                            get: { p.streamOutput },
                            set: { val in
                                var updated = p
                                updated.streamOutput = val
                                store.updatePersona(updated)
                            }
                        )) {
                            Label {
                                Text("流式输出")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }

                    // Group 2: 聊天模型
                    Section {
                        Button {
                            showModelPicker = true
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(MinisThemeList.accent.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Text("使")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(MinisThemeList.accent)
                                }

                                Text(modelDisplayName(for: p.modelId))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(ChatColors.primaryText)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("聊天模型")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ChatColors.primaryText)
                    } footer: {
                        Text("为该助手设置默认聊天模型 (未设置时使用全局默认)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // Group 3: 聊天背景
                    Section {
                        Toggle(isOn: Binding(
                            get: { p.useGradientBackground },
                            set: { val in
                                var updated = p
                                updated.useGradientBackground = val
                                store.updatePersona(updated)
                            }
                        )) {
                            Label {
                                Text("渐变背景")
                                    .font(.system(size: 16))
                            } icon: {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                            }
                        }

                        Button {
                            showBackgroundPhotoPicker = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "photo")
                                Text(p.background != nil ? "更换背景图片" : "选择背景图片")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    } header: {
                        Text("聊天背景")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ChatColors.primaryText)
                    } footer: {
                        Text("设置助手聊天页面的背景图片")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("基础设置")
                .navigationBarTitleDisplayMode(.inline)
                .photosPicker(isPresented: $showBackgroundPhotoPicker, selection: $backgroundPhotoItem, matching: .images)
                .onChange(of: backgroundPhotoItem) { newItem in
                    guard let item = newItem else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            saveBackgroundImage(image, for: p)
                        }
                    }
                }
                // Temperature 弹板调节
                .sheet(isPresented: $showTempSheet) {
                    NavigationStack {
                        Form {
                            Toggle("启用自定义 Temperature", isOn: $tempEnabled)
                            if tempEnabled {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("采样温度: \(String(format: "%.2f", tempValue))")
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                    }
                                    Slider(value: $tempValue, in: 0.0...2.0, step: 0.05)
                                    Text("较高的值会使输出更加随机发散，较低的值会更严谨集中。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .navigationTitle("Temperature")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") {
                                    var updated = p
                                    updated.temperature = tempEnabled ? tempValue : nil
                                    store.updatePersona(updated)
                                    showTempSheet = false
                                }
                            }
                        }
                        .onAppear {
                            tempEnabled = (p.temperature != nil)
                            tempValue = p.temperature ?? 1.0
                        }
                    }
                    .presentationDetents([.height(260)])
                }
                // Top P 弹板调节
                .sheet(isPresented: $showTopPSheet) {
                    NavigationStack {
                        Form {
                            Toggle("启用自定义 Top P", isOn: $topPEnabled)
                            if topPEnabled {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("核采样阈值: \(String(format: "%.2f", topPValue))")
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                    }
                                    Slider(value: $topPValue, in: 0.0...1.0, step: 0.02)
                                    Text("仅从累积概率达到 Top P 的候选中采样。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .navigationTitle("Top P")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") {
                                    var updated = p
                                    updated.topP = topPEnabled ? topPValue : nil
                                    store.updatePersona(updated)
                                    showTopPSheet = false
                                }
                            }
                        }
                        .onAppear {
                            topPEnabled = (p.topP != nil)
                            topPValue = p.topP ?? 1.0
                        }
                    }
                    .presentationDetents([.height(260)])
                }
                // 上下文限制弹板
                .sheet(isPresented: $showContextSheet) {
                    NavigationStack {
                        Form {
                            Toggle("限制上下文消息数量", isOn: $contextLimitEnabled)
                            if contextLimitEnabled {
                                Stepper("保留消息条数: \(contextMessageCount) 条", value: $contextMessageCount, in: 1...200, step: 2)
                            }
                        }
                        .navigationTitle("上下文消息数量")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") {
                                    var updated = p
                                    updated.limitContextMessages = contextLimitEnabled
                                    updated.contextMessageSize = contextMessageCount
                                    store.updatePersona(updated)
                                    showContextSheet = false
                                }
                            }
                        }
                        .onAppear {
                            contextLimitEnabled = p.limitContextMessages
                            contextMessageCount = p.contextMessageSize
                        }
                    }
                    .presentationDetents([.height(220)])
                }
                // 思考预算弹板
                .sheet(isPresented: $showThinkingBudgetSheet) {
                    NavigationStack {
                        Form {
                            Toggle("启用思考预算 (Thinking Budget)", isOn: $thinkingBudgetEnabled)
                            if thinkingBudgetEnabled {
                                Stepper("Token 预算: \(thinkingBudgetValue)", value: $thinkingBudgetValue, in: 1024...65536, step: 1024)
                            }
                        }
                        .navigationTitle("思考预算")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") {
                                    var updated = p
                                    updated.thinkingBudget = thinkingBudgetEnabled ? thinkingBudgetValue : nil
                                    store.updatePersona(updated)
                                    showThinkingBudgetSheet = false
                                }
                            }
                        }
                        .onAppear {
                            thinkingBudgetEnabled = (p.thinkingBudget != nil)
                            thinkingBudgetValue = p.thinkingBudget ?? 4096
                        }
                    }
                    .presentationDetents([.height(220)])
                }
                // 最大 Token 弹板
                .sheet(isPresented: $showMaxTokensSheet) {
                    NavigationStack {
                        Form {
                            Toggle("限制最大 Token 数", isOn: $maxTokensEnabled)
                            if maxTokensEnabled {
                                Stepper("最大输出: \(maxTokensValue)", value: $maxTokensValue, in: 512...32768, step: 512)
                            }
                        }
                        .navigationTitle("最大 Token 数")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") {
                                    var updated = p
                                    updated.maxTokens = maxTokensEnabled ? maxTokensValue : nil
                                    store.updatePersona(updated)
                                    showMaxTokensSheet = false
                                }
                            }
                        }
                        .onAppear {
                            maxTokensEnabled = (p.maxTokens != nil)
                            maxTokensValue = p.maxTokens ?? 4096
                        }
                    }
                    .presentationDetents([.height(220)])
                }
                // 模型选择弹层
                .sheet(isPresented: $showModelPicker) {
                    NavigationStack {
                        List {
                            Button {
                                var updated = p
                                updated.modelId = nil
                                store.updatePersona(updated)
                                showModelPicker = false
                            } label: {
                                HStack {
                                    Text("使用全局默认")
                                        .foregroundStyle(ChatColors.primaryText)
                                    Spacer()
                                    if p.modelId == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(MinisThemeList.accent)
                                    }
                                }
                            }

                            ForEach(ProviderConfigStore.shared.config.modelEntries) { entry in
                                Button {
                                    var updated = p
                                    updated.modelId = entry.id
                                    store.updatePersona(updated)
                                    showModelPicker = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.model.displayName ?? entry.model.id)
                                                .foregroundStyle(ChatColors.primaryText)
                                            if let inst = ProviderConfigStore.shared.instance(for: entry.providerInstanceId) {
                                                Text(inst.label)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if p.modelId == entry.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(MinisThemeList.accent)
                                        }
                                    }
                                }
                            }
                        }
                        .navigationTitle("选择聊天模型")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("取消") { showModelPicker = false }
                            }
                        }
                    }
                }
            }
        }
    }

    private func modelDisplayName(for modelId: String?) -> String {
        guard let mid = modelId, !mid.isEmpty else { return "使用全局默认" }
        if let entry = ProviderConfigStore.shared.config.modelEntries.first(where: { $0.id == mid }) {
            return entry.model.displayName ?? entry.model.id
        }
        return mid
    }

    private func saveBackgroundImage(_ image: UIImage, for p: Persona) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let name = "persona_bg_\(p.id).jpg"
        let dir = AIChatViewModel.minisMemoryPersistentDir.appendingPathComponent("backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(name)
        try? data.write(to: fileURL, options: .atomic)

        var updated = p
        updated.background = fileURL.path
        store.updatePersona(updated)
    }
}

// MARK: - 2. PersonaPromptSettingsView (复刻 photo_6E385EE9.png 提示词)

struct PersonaPromptSettingsView: View {
    let personaId: String
    @ObservedObject var store = PersonaStore.shared

    @State private var soulText = ""
    @State private var allowConvPrompt = false
    @State private var allowInjection = false
    @State private var appendTime = false
    @State private var messageTemplate = "{{ message }}"
    @State private var showImportFile = false

    private let availableVariables = [
        "{cur_date}", "{cur_time}", "{cur_datetime}",
        "{model_id}", "{model_name}", "{locale}", "{timezone}",
        "{system_version}", "{device_info}", "{battery_level}",
        "{nickname}", "{assistant_name}"
    ]

    private var persona: Persona? {
        store.personas.first { $0.id == personaId }
    }

    var body: some View {
        Group {
            if let p = persona {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 系统提示词区域
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("系统提示词")
                                    .font(.system(size: 15, weight: .bold))
                                Spacer()
                                Button {
                                    showImportFile = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.badge.plus")
                                        Text("从文件导入")
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                    .foregroundStyle(ChatColors.primaryText)
                                }
                            }

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(ChatColors.secondaryBg)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)

                                TextEditor(text: $soulText)
                                    .font(.system(size: 14))
                                    .padding(8)
                                    .background(Color.clear)
                                    .frame(minHeight: 200)
                            }
                            .frame(minHeight: 200)

                            // 可用变量
                            VStack(alignment: .leading, spacing: 6) {
                                Text("可用变量：")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                                    ForEach(availableVariables, id: \.self) { variable in
                                        Button {
                                            insertVariable(variable)
                                        } label: {
                                            Text(variable)
                                                .font(.system(size: 11, design: .monospaced))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(RoundedRectangle(cornerRadius: 6).fill(MinisThemeList.accent.opacity(0.12)))
                                                .foregroundStyle(MinisThemeList.accent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 16)

                        // 独立选项卡片
                        VStack(spacing: 12) {
                            Toggle(isOn: $allowConvPrompt) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("独立对话系统提示")
                                        .font(.system(size: 15, weight: .medium))
                                    Text("允许每个对话设置自己的系统提示词。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            Toggle(isOn: $allowInjection) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("独立对话指令注入")
                                        .font(.system(size: 15, weight: .medium))
                                    Text("每个对话单独选择指令注入和世界书，默认不选中。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            Toggle(isOn: $appendTime) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("追加当前时间")
                                        .font(.system(size: 15, weight: .medium))
                                    Text("在每条用户消息末尾追加发送时刻。时间在请求末尾，不影响 Prompt 缓存。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ChatColors.secondaryBg))
                        .padding(.horizontal, 16)

                        // 聊天内容模板
                        VStack(alignment: .leading, spacing: 8) {
                            Text("聊天内容模板")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ChatColors.primaryText)

                            TextField("{{ message }}", text: $messageTemplate)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ChatColors.secondaryBg))
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 16)
                }
                .navigationTitle("提示词")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            savePromptSettings(for: p)
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onAppear {
                    loadPromptSettings(for: p)
                }
                .fileImporter(isPresented: $showImportFile, allowedContentTypes: [.text, .plainText]) { result in
                    if let url = try? result.get(),
                       let text = try? String(contentsOf: url, encoding: .utf8) {
                        soulText = text
                    }
                }
            }
        }
    }

    private func insertVariable(_ variable: String) {
        if soulText.isEmpty {
            soulText = variable
        } else {
            soulText += " " + variable
        }
    }

    private func loadPromptSettings(for p: Persona) {
        allowConvPrompt = p.allowConversationSystemPrompt
        allowInjection = p.allowConversationPromptInjection
        appendTime = p.appendCurrentTimeToUserMessage
        messageTemplate = p.messageTemplate

        let soulURL = PersonaStore.memoryDir(for: p.id).appendingPathComponent("SOUL.md")
        if let text = try? String(contentsOf: soulURL, encoding: .utf8) {
            soulText = text
        }
    }

    private func savePromptSettings(for p: Persona) {
        var updated = p
        updated.allowConversationSystemPrompt = allowConvPrompt
        updated.allowConversationPromptInjection = allowInjection
        updated.appendCurrentTimeToUserMessage = appendTime
        updated.messageTemplate = messageTemplate
        store.updatePersona(updated)

        let soulURL = PersonaStore.memoryDir(for: p.id).appendingPathComponent("SOUL.md")
        try? FileManager.default.createDirectory(at: soulURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? soulText.write(to: soulURL, atomically: true, encoding: .utf8)
        SoulStore.refreshCache()
        NotificationCenter.default.post(name: .soulMdChanged, object: nil)
    }
}

// MARK: - 3. PersonaLocalToolsSettingsView (复刻 photo_8A79EFD5.png 本地工具)

struct PersonaLocalToolsSettingsView: View {
    let personaId: String
    @ObservedObject var store = PersonaStore.shared

    private var persona: Persona? {
        store.personas.first { $0.id == personaId }
    }

    var body: some View {
        Group {
            if let p = persona {
                let enabledSet = Set(p.localToolIds ?? LocalToolRegistry.all.map(\.id))

                List {
                    Section {
                        ForEach(LocalToolRegistry.all) { tool in
                            Toggle(isOn: Binding(
                                get: { enabledSet.contains(tool.id) },
                                set: { isOn in
                                    var currentSet = enabledSet
                                    if isOn { currentSet.insert(tool.id) }
                                    else { currentSet.remove(tool.id) }
                                    var updated = p
                                    updated.localToolIds = Array(currentSet)
                                    store.updatePersona(updated)
                                }
                            )) {
                                HStack(spacing: 12) {
                                    Image(systemName: tool.icon)
                                        .font(.system(size: 18))
                                        .frame(width: 26)
                                        .foregroundStyle(MinisThemeList.accent)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tool.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(ChatColors.primaryText)
                                        Text(tool.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    } header: {
                        HStack {
                            Text("本地工具列表")
                            Spacer()
                            Button("全选") {
                                var updated = p
                                updated.localToolIds = LocalToolRegistry.all.map(\.id)
                                store.updatePersona(updated)
                            }
                            .font(.system(size: 12))
                            Text("·")
                            Button("全关") {
                                var updated = p
                                updated.localToolIds = []
                                store.updatePersona(updated)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("本地工具")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - 4. PersonaMemorySettingsView (独立记忆查看)

struct PersonaMemorySettingsView: View {
    let personaId: String
    @ObservedObject var store = PersonaStore.shared

    @State private var globalMd = ""
    @State private var soulMd = ""

    private var persona: Persona? {
        store.personas.first { $0.id == personaId }
    }

    var body: some View {
        Group {
            if let p = persona {
                List {
                    Section("全局人设事实 (GLOBAL.md)") {
                        Text(globalMd.isEmpty ? "暂无 GLOBAL.md 长期事实记录" : globalMd)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(ChatColors.secondaryText)
                            .lineLimit(10)
                    }

                    Section("提示词灵魂设定 (SOUL.md)") {
                        Text(soulMd.isEmpty ? "暂无 SOUL.md" : soulMd)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(ChatColors.secondaryText)
                            .lineLimit(10)
                    }

                    Section("记忆管理") {
                        Button(role: .destructive) {
                            clearPersonaLogs(for: p)
                        } label: {
                            Text("清理该人设的每日日志归档")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("记忆")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    loadMemoryFiles(for: p)
                }
            }
        }
    }

    private func loadMemoryFiles(for p: Persona) {
        let memDir = PersonaStore.memoryDir(for: p.id)
        if let g = try? String(contentsOf: memDir.appendingPathComponent("GLOBAL.md"), encoding: .utf8) {
            globalMd = g
        }
        if let s = try? String(contentsOf: memDir.appendingPathComponent("SOUL.md"), encoding: .utf8) {
            soulMd = s
        }
    }

    private func clearPersonaLogs(for p: Persona) {
        let memDir = PersonaStore.memoryDir(for: p.id)
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: memDir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "md" && f.lastPathComponent != "SOUL.md" && f.lastPathComponent != "GLOBAL.md" {
                try? fm.removeItem(at: f)
            }
        }
    }
}

// MARK: - 5. PersonaSkillsSettingsView (技能白名单)

struct PersonaSkillsSettingsView: View {
    let personaId: String
    @ObservedObject var store = PersonaStore.shared

    private var persona: Persona? {
        store.personas.first { $0.id == personaId }
    }

    var body: some View {
        Group {
            if let p = persona {
                let enabledSkillIds = Set(p.skillIds ?? SkillStore.shared.skills.map(\.id))

                List {
                    Section {
                        ForEach(SkillStore.shared.skills) { skill in
                            Toggle(isOn: Binding(
                                get: { enabledSkillIds.contains(skill.id) },
                                set: { isOn in
                                    var currentSet = enabledSkillIds
                                    if isOn { currentSet.insert(skill.id) }
                                    else { currentSet.remove(skill.id) }
                                    var updated = p
                                    updated.skillIds = Array(currentSet)
                                    store.updatePersona(updated)
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.name)
                                        .font(.system(size: 15, weight: .medium))
                                    if !skill.description.isEmpty {
                                        Text(skill.description)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("启用的技能 (关掉的不再进入该人设的上下文)")
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("技能")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - 6. PersonaMcpSettingsView (MCP 白名单)

struct PersonaMcpSettingsView: View {
    let personaId: String
    @ObservedObject var store = PersonaStore.shared

    private var persona: Persona? {
        store.personas.first { $0.id == personaId }
    }

    var body: some View {
        Group {
            if let p = persona {
                let enabledMcpIds = Set(p.mcpServerIds ?? MCPStore.shared.servers.map(\.id))

                List {
                    Section {
                        ForEach(MCPStore.shared.servers) { server in
                            Toggle(isOn: Binding(
                                get: { enabledMcpIds.contains(server.id) },
                                set: { isOn in
                                    var currentSet = enabledMcpIds
                                    if isOn { currentSet.insert(server.id) }
                                    else { currentSet.remove(server.id) }
                                    var updated = p
                                    updated.mcpServerIds = Array(currentSet)
                                    store.updatePersona(updated)
                                }
                            )) {
                                Text(server.id)
                                    .font(.system(size: 15, weight: .medium))
                            }
                        }
                    } header: {
                        Text("绑定的 MCP 服务器 (关掉的不再进入该人设的上下文)")
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("MCP")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - 7. PersonaSimpleSubpageView (快捷短语 / 自定义请求 / 正则替换 提示页)

struct PersonaSimpleSubpageView: View {
    let title: String
    let icon: String
    let hint: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(MinisThemeList.accent)
                .padding(.top, 40)

            Text(title)
                .font(.system(size: 20, weight: .bold))

            Text(hint)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
