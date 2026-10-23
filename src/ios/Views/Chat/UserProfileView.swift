import SwiftUI

/// [B28 R11] 通讯录里「我自己」的编辑页。
///
/// 这只不是聊天对象，是用户本人的档案：AI 每次开口都会读到它。
/// 与 AI 人设的编辑页分开，是因为这里没有模型/工具/技能可配——
/// 只有"她是谁、她吃什么、她的雷区"。
///
/// 存的一直是 memory/personas/me/SOUL.md 原文，不另开数据库：
/// 人和 AI 改的是同一份文件，谁后写的就以谁为准。
struct UserProfileView: View {
    @ObservedObject private var store = PersonaStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""
    @State private var nameDraft: String = ""
    @State private var loadedBody: String = ""

    private let profileId = PersonaStore.userProfilePersonaID

    /// SOUL.md 被人或 AI 改过之后，让所有读人设的地方重新拉一遍。
    static func publishProfileChange() {
        NotificationCenter.default.post(name: .personaDidChange, object: nil)
    }

    private var persona: Persona? {
        store.personas.first { $0.id == profileId }
    }

    /// 称呼：档案里的「怎么称呼」优先，界面文案才跟着变。
    private var addressingName: String {
        let n = SystemPromptBuilder.userProfileAddressingName(for: profileId)
        return n.isEmpty ? (persona?.name ?? "我自己") : n
    }

    var hasUnsavedChanges: Bool { draft != loadedBody }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(addressingName)
                        .font(.system(size: 22, weight: .bold))
                    Text("这份档案描述的是你，不是任何一只 AI。你写进去的东西，AI 每次对话都会读到；它也可以在长期互动里补充。")
                        .font(.system(size: 12))
                        .foregroundStyle(ChatColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
            }

            // 称呼单独一格：它是自适应叫法的唯一开关，不该让人在正文里找。
            Section {
                HStack {
                    Text("怎么称呼你")
                    Spacer()
                    // 不用 get/set 直连磁盘：那样每敲一个字写一次文件，
                    // 光标还会被读回来的旧值顶掉。先落在本地，回车/离开时再落盘。
                    TextField("留空则用「你」", text: $nameDraft)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14))
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                }
            } header: {
                Text("叫法")
            } footer: {
                Text("填了之后，界面里的文案和 AI 对你的叫法都跟着变；AI 那边的人设名同理，人设叫什么系统就喊它什么。")
            }

            Section {
                NavigationLink {
                    UserProfileBodyEditor(bodyText: $draft, original: loadedBody, personaId: profileId)
                        .navigationTitle("我的档案")
                        .onAppear { reload() }
                } label: {
                    HStack {
                        SettingsRowIcon(icon: "person.text.rectangle")
                        Text("档案内容")
                        Spacer()
                        Text(fieldSummary())
                            .font(.system(size: 12))
                            .foregroundStyle(ChatColors.secondaryText)
                            .lineLimit(1)
                    }
                }
            } header: {
                Text("内容")
            } footer: {
                Text("按小节写，一行一条。冒号后面留空的条目不会进模型的上下文，所以不必删模板。")
            }

            Section {
                Toggle("把 NSFW 小节给 AI 看", isOn: Binding(
                    get: { SystemPromptBuilder.userProfileNSFWInjectionEnabled },
                    set: { SystemPromptBuilder.userProfileNSFWInjectionEnabled = $0 }
                ))
            } header: {
                Text("注入范围")
            } footer: {
                Text("关掉后 NSFW 那一节完全不进模型——有些敏感模型一看尺度描写就整段拒答。其余内容照常注入。")
            }

            Section {
                NavigationLink {
                    UserProfilePreview(personaId: profileId)
                        .navigationTitle("AI 实际读到什么")
                } label: {
                    HStack {
                        SettingsRowIcon(icon: "eye.fill")
                        Text("注入预览")
                    }
                }
            } footer: {
                Text("看到的就是下次对话真正进模型的那段文字。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我自己")
        .onAppear { reload() }
        .onDisappear { commitName() }
    }

    /// 落盘「怎么称呼」。空串也算一次有效修改（清掉叫法）。
    private func commitName() {
        let current = SystemPromptBuilder.userProfileAddressingName(for: profileId)
        guard nameDraft != current else { return }
        setFieldValue("怎么称呼", to: nameDraft.trimmingCharacters(in: .whitespaces))
    }

    private func reload() {
        let file = SoulStore.load(for: profileId)
        let text = (file?.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        draft = text.isEmpty ? PersonaStore.userProfileSoulTemplate() : text
        loadedBody = draft
        nameDraft = SystemPromptBuilder.userProfileAddressingName(for: profileId)
    }

    /// 小节填写进度，给"档案内容"那行当副标题。
    private func fieldSummary() -> String {
        let file = SoulStore.load(for: profileId)
        guard let text = file?.body, !text.isEmpty else { return "未填写" }
        let filled = SystemPromptBuilder.userProfileSection(from: file)
        let sections = filled.components(separatedBy: "## ").filter { $0.count > 1 }.count
        return sections > 0 ? "已填 \(sections) 节" : "未填写"
    }

    /// 改「怎么称呼：」那一行。找不到就补在「# 身份」下面。
    private func setFieldValue(_ key: String, to value: String) {
        let file = SoulStore.load(for: profileId)
        var text = file?.body ?? PersonaStore.userProfileSoulTemplate()
        var lines = text.components(separatedBy: "\n")
        var replaced = false
        for i in lines.indices {
            if lines[i].contains(key), lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                lines[i] = "- \(key)：\(value)"
                replaced = true
                break
            }
        }
        if !replaced, let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "# 身份" }) {
            lines.insert("- \(key)：\(value)", at: idx + 1)
        } else if !replaced {
            lines.append("- \(key)：\(value)")
        }
        let merged = lines.joined(separator: "\n")
        try? merged.write(to: SoulStore.fileURL(for: profileId), atomically: true, encoding: .utf8)
        loadedBody = merged
        draft = merged
        // 先落盘再广播，否则监听方读到的还是旧文件。
        Self.publishProfileChange()
    }
}

/// 档案正文编辑器。原文进原文出，不做结构化拆解——
/// 结构由小节标题约定，AI 和她写的是同一个文件。
private struct UserProfileBodyEditor: View {
    @Binding var bodyText: String
    let original: String
    let personaId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TextEditor(text: $bodyText)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 4)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(bodyText == original ? AppLocalized("完成") : AppLocalized("保存")) {
                        save()
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
    }

    private func save() {
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try text.write(to: SoulStore.fileURL(for: personaId), atomically: true, encoding: .utf8)
        } catch {
            MinisToast.show(AppLocalized("保存失败"))
            return
        }
        bodyText = text
        MinisToast.show(AppLocalized("已保存，下次对话开始生效"))
        dismiss()
    }
}

/// 注入预览：把她真正会喂给模型的那段渲染出来。
private struct UserProfilePreview: View {
    let personaId: String
    var body: some View {
        ScrollView {
            Text(SystemPromptBuilder.userProfileSection(for: personaId).isEmpty
                 ? AppLocalized("档案还是空的，暂时不会给 AI 加任何内容。")
                 : SystemPromptBuilder.userProfileSection(for: personaId))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
    }
}
