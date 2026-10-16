import SwiftUI

// MARK: - PersonaQuickSwitcher
//
// [batch9b · 一击切换] 顶部标题点开的人设快捷浮层：标题正下方浮出人设
// 列表，点谁切谁；底部一行「管理人设…」进完整管理页（新建/编辑/删除/复制）。
//
// 为什么自绘而不是 .popover：
//  ① iPhone 上 popover 默认被系统适配成 sheet（正是要去的形态），必须
//    逆着系统默认走，且本仓零 .popover 先例；
//  ② 浮层挂在稳定列表层（本仓已有同范式的 folderMiniBarOverlay），
//    不挂 toolbar principal——那个区域是本仓两次事故（丢通知 / UAF）的现场；
//  ③ 「管理人设…」要开 sheet，popover 内嵌套 present 易碎。
//
// 交互：点行 = 切换（当前项则仅收起）；点空白 = 收起；切换不等 DB 往返，
// 列表刷新由既有 .personaDidChange 链在后台完成。

struct PersonaQuickSwitcher: View {
    @ObservedObject var store: PersonaStore

    /// 点「管理人设…」：宿主先收浮层、（延迟一拍）再开管理 sheet。
    var onManage: () -> Void
    /// 点空白处收起。
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // 点任何空白处收起。浅遮罩：下方会话列表仍可见（切换后立刻能看到列表变化）。
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            card
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
        .transition(.opacity)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.personas) { p in
                        personaRow(p)
                        if p.id != store.personas.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            Button {
                onManage()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.crop.square.stack")
                        .font(.system(size: 15))
                        .foregroundStyle(AppearanceStudio.shared.color(.secondaryText))
                        .frame(width: 26)
                    Text("管理人设…")
                        .font(.subheadline)
                        .foregroundStyle(AppearanceStudio.shared.color(.primaryText))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppearanceStudio.shared.color(.secondaryText))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppearanceStudio.shared.color(.border).opacity(0.5), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    // MARK: - Row

    private func personaRow(_ p: Persona) -> some View {
        Button {
            // 点当前项 = 只想收起，不做无谓的 setCurrent（其自带同值 guard）。
            if p.id != store.currentPersonaID {
                store.setCurrent(p.id)
            }
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                PersonaAvatarView(iconRef: p.avatar, size: 26)

                Text(p.name)
                    .font(.body)
                    .foregroundStyle(AppearanceStudio.shared.color(.primaryText))
                    .lineLimit(1)

                if p.isBuiltIn {
                    Text("内置")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppearanceStudio.shared.color(.mutedSurface)))
                        .foregroundStyle(AppearanceStudio.shared.color(.secondaryText))
                }

                Spacer()

                if p.id == store.currentPersonaID {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppearanceStudio.shared.color(.accent))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
