import SwiftUI
import UIKit

// MARK: - 加号面板功能项类型定义

public enum PlusPanelItemType: String, CaseIterable, Identifiable {
    case zap = "zap"             // 快捷短语
    case image = "image"         // 图片
    case doc = "doc"             // 文档
    case book = "book"           // 知识库
    case sticker = "sticker"     // 表情包 (醒醒专属)
    case sparkles = "sparkles"   // 模型切换
    case chats = "chats"         // 对话框
    case group = "group"         // 群聊
    case gear = "gear"           // 对话框设置
    case footprint = "footprint" // 留痕
    case eyeoff = "eyeoff"       // 隐身模式
    case gauge = "gauge"         // 上下文用量
    case share = "share"         // 导出对话

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .zap: return "快捷短语"
        case .image: return "图片"
        case .doc: return "文档"
        case .book: return "知识库"
        case .sticker: return "表情包"
        case .sparkles: return "模型切换"
        case .chats: return "对话框"
        case .group: return "群聊"
        case .gear: return "对话框设置"
        case .footprint: return "留痕"
        case .eyeoff: return "隐身模式"
        case .gauge: return "上下文用量"
        case .share: return "导出对话"
        }
    }

    /// 精致可爱的实体矢量图标（原生系统符号，零编译负担，质感饱满）
    public var systemImageName: String {
        switch self {
        case .zap: return "bolt.fill"
        case .image: return "photo.fill"
        case .doc: return "doc.fill"
        case .book: return "book.fill"
        case .sticker: return "face.smiling.inverse"
        case .sparkles: return "sparkles"
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .group: return "person.2.fill"
        case .gear: return "slider.horizontal.3"
        case .footprint: return "pawprint.fill"
        case .eyeoff: return "eye.slash.fill"
        case .gauge: return "gauge.with.needle.fill"
        case .share: return "square.and.arrow.up.fill"
        }
    }
}

// MARK: - 单个功能按钮磁贴组件 (PlusPanelTileButton)

public struct PlusPanelTileButton: View {
    let item: PlusPanelItemType
    let isDark: Bool
    let onTap: () -> Void

    public init(item: PlusPanelItemType, isDark: Bool, onTap: @escaping () -> Void) {
        self.item = item
        self.isDark = isDark
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CSSThemeVariables.accentSoft(isDark: isDark))
                        .shadow(
                            color: CSSThemeVariables.sheetShadow(isDark: isDark).opacity(0.08),
                            radius: 8, x: 0, y: 2
                        )
                        .frame(width: 58, height: 58)

                    Image(systemName: item.systemImageName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                }

                Text(item.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TilePressButtonStyle())
        .accessibilityLabel(Text(item.title))
    }
}

private struct TilePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 主加号面板抽屉 (ChatPlusPanel)

public struct ChatPlusPanel: View {
    let onItemTap: (PlusPanelItemType) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage: Int = 0

    private var isDark: Bool { colorScheme == .dark }

    // 两页分页：8 + 5
    private let page1Items: [PlusPanelItemType] = [
        .zap, .image, .doc, .book,
        .sticker, .sparkles, .chats, .group
    ]
    private let page2Items: [PlusPanelItemType] = [
        .gear, .footprint, .eyeoff, .gauge, .share
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    public init(onItemTap: @escaping (PlusPanelItemType) -> Void) {
        self.onItemTap = onItemTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部分割线
            Rectangle()
                .fill(CSSThemeVariables.divider(isDark: isDark))
                .frame(height: 1)

            // 两页横向翻页 TabView
            TabView(selection: $currentPage) {
                // Page 1
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(page1Items) { item in
                        PlusPanelTileButton(item: item, isDark: isDark) {
                            onItemTap(item)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .tag(0)

                // Page 2
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(page2Items) { item in
                        PlusPanelTileButton(item: item, isDark: isDark) {
                            onItemTap(item)
                        }
                    }
                    // 占位保持4列对齐
                    ForEach(0..<3, id: \.self) { _ in
                        Color.clear.frame(height: 82)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 200)

            // 底部指示小圆点 (对齐原型)
            HStack(spacing: 8) {
                Capsule()
                    .fill(currentPage == 0 ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.divider(isDark: isDark))
                    .frame(width: currentPage == 0 ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentPage)

                Capsule()
                    .fill(currentPage == 1 ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.divider(isDark: isDark))
                    .frame(width: currentPage == 1 ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentPage)
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(CSSThemeVariables.card(isDark: isDark))
    }
}
