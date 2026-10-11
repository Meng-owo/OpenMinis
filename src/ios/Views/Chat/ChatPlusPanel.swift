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
}

// MARK: - 独立小巧可爱矢量图标体系 (零编译负担)

private struct CuteZapView: View {
    let color: Color
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24.0
            var p = Path()
            p.move(to: CGPoint(x: 13.2 * s, y: 2.6 * s))
            p.addLine(to: CGPoint(x: 5.2 * s, y: 13.4 * s))
            p.addLine(to: CGPoint(x: 10.8 * s, y: 13.4 * s))
            p.addLine(to: CGPoint(x: 9.7 * s, y: 21.3 * s))
            p.addLine(to: CGPoint(x: 17.8 * s, y: 10.4 * s))
            p.addLine(to: CGPoint(x: 12.2 * s, y: 10.4 * s))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        }
    }
}

private struct CuteImageView: View {
    let mainColor: Color
    let cutColor: Color
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24.0
            let r = CGRect(x: 3.0 * s, y: 4.5 * s, width: 18.0 * s, height: 15.0 * s)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4.0 * s), with: .color(mainColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 7.0 * s, y: 8.0 * s, width: 4.0 * s, height: 4.0 * s)), with: .color(cutColor))
            var m = Path()
            m.move(to: CGPoint(x: 3.2 * s, y: 16.8 * s))
            m.addLine(to: CGPoint(x: 8.5 * s, y: 11.5 * s))
            m.addLine(to: CGPoint(x: 11.9 * s, y: 14.9 * s))
            m.addLine(to: CGPoint(x: 14.8 * s, y: 12.0 * s))
            m.addLine(to: CGPoint(x: 20.4 * s, y: 17.6 * s))
            m.addLine(to: CGPoint(x: 20.4 * s, y: 18.8 * s))
            m.addLine(to: CGPoint(x: 3.2 * s, y: 18.8 * s))
            m.closeSubpath()
            ctx.fill(m, with: .color(cutColor))
        }
    }
}

private struct CuteDocView: View {
    let mainColor: Color
    let cutColor: Color
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24.0
            var p = Path()
            p.move(to: CGPoint(x: 7.0 * s, y: 2.8 * s))
            p.addLine(to: CGPoint(x: 13.8 * s, y: 2.8 * s))
            p.addLine(to: CGPoint(x: 19.0 * s, y: 8.0 * s))
            p.addLine(to: CGPoint(x: 19.0 * s, y: 19.2 * s))
            p.addLine(to: CGPoint(x: 7.0 * s, y: 19.2 * s))
            p.closeSubpath()
            ctx.fill(p, with: .color(mainColor))
            var l = Path()
            l.move(to: CGPoint(x: 9.2 * s, y: 12.2 * s))
            l.addLine(to: CGPoint(x: 14.8 * s, y: 12.2 * s))
            l.move(to: CGPoint(x: 9.2 * s, y: 15.6 * s))
            l.addLine(to: CGPoint(x: 14.8 * s, y: 15.6 * s))
            ctx.stroke(l, with: .color(cutColor), style: StrokeStyle(lineWidth: 2.0 * s, lineCap: .round))
        }
    }
}

private struct CuteBookView: View {
    let mainColor: Color
    let cutColor: Color
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24.0
            let r = CGRect(x: 5.0 * s, y: 3.5 * s, width: 14.0 * s, height: 17.0 * s)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2.0 * s), with: .color(mainColor))
            var l = Path()
            l.move(to: CGPoint(x: 8.5 * s, y: 8.0 * s))
            l.addLine(to: CGPoint(x: 15.5 * s, y: 8.0 * s))
            ctx.stroke(l, with: .color(cutColor), style: StrokeStyle(lineWidth: 2.0 * s, lineCap: .round))
        }
    }
}

private struct CuteStickerView: View {
    let mainColor: Color
    let cutColor: Color
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24.0
            let r = CGRect(x: 3.0 * s, y: 3.0 * s, width: 18.0 * s, height: 18.0 * s)
            ctx.fill(Path(ellipseIn: r), with: .color(mainColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 7.3 * s, y: 8.3 * s, width: 3.4 * s, height: 3.4 * s)), with: .color(cutColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 13.3 * s, y: 8.3 * s, width: 3.4 * s, height: 3.4 * s)), with: .color(cutColor))
            var m = Path()
            m.move(to: CGPoint(x: 8.2 * s, y: 14.3 * s))
            m.addQuadCurve(to: CGPoint(x: 15.8 * s, y: 14.3 * s), control: CGPoint(x: 12.0 * s, y: 17.2 * s))
            ctx.stroke(m, with: .color(cutColor), style: StrokeStyle(lineWidth: 2.0 * s, lineCap: .round))
        }
    }
}

private struct CuteSparklesView: View {
    let color: Color
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(color)
    }
}

private struct CuteChatsView: View {
    let mainColor: Color
    let cutColor: Color
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24.0
            var p = Path()
            p.move(to: CGPoint(x: 4.5 * s, y: 4.0 * s))
            p.addLine(to: CGPoint(x: 19.5 * s, y: 4.0 * s))
            p.addLine(to: CGPoint(x: 19.5 * s, y: 15.0 * s))
            p.addLine(to: CGPoint(x: 10.0 * s, y: 15.0 * s))
            p.addLine(to: CGPoint(x: 4.5 * s, y: 19.5 * s))
            p.closeSubpath()
            ctx.fill(p, with: .color(mainColor))
            var l = Path()
            l.move(to: CGPoint(x: 8.0 * s, y: 8.5 * s))
            l.addLine(to: CGPoint(x: 16.0 * s, y: 8.5 * s))
            l.move(to: CGPoint(x: 8.0 * s, y: 11.5 * s))
            l.addLine(to: CGPoint(x: 13.0 * s, y: 11.5 * s))
            ctx.stroke(l, with: .color(cutColor), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        }
    }
}

private struct CuteGroupView: View {
    let color: Color
    var body: some View {
        Image(systemName: "person.2.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(color)
    }
}

private struct CuteGearView: View {
    let color: Color
    var body: some View {
        Image(systemName: "slider.horizontal.3")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(color)
    }
}

private struct CuteFootprintView: View {
    let color: Color
    var body: some View {
        Image(systemName: "shoeprints.fill")
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(color)
    }
}

private struct CuteEyeOffView: View {
    let color: Color
    var body: some View {
        Image(systemName: "eye.slash.fill")
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(color)
    }
}

private struct CuteGaugeView: View {
    let color: Color
    var body: some View {
        Image(systemName: "gauge.with.needle.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(color)
    }
}

private struct CuteShareView: View {
    let color: Color
    var body: some View {
        Image(systemName: "square.and.arrow.up.fill")
            .font(.system(size: 19, weight: .semibold))
            .foregroundColor(color)
    }
}

// MARK: - 可爱矢量图标分发器 (CuteDuduIcon)

public struct CuteDuduIcon: View {
    let type: PlusPanelItemType
    let size: CGFloat
    let mainColor: Color
    let cutColor: Color

    public init(type: PlusPanelItemType, size: CGFloat = 28, mainColor: Color, cutColor: Color) {
        self.type = type
        self.size = size
        self.mainColor = mainColor
        self.cutColor = cutColor
    }

    @ViewBuilder
    public var body: some View {
        Group {
            switch type {
            case .zap:
                CuteZapView(color: mainColor)
            case .image:
                CuteImageView(mainColor: mainColor, cutColor: cutColor)
            case .doc:
                CuteDocView(mainColor: mainColor, cutColor: cutColor)
            case .book:
                CuteBookView(mainColor: mainColor, cutColor: cutColor)
            case .sticker:
                CuteStickerView(mainColor: mainColor, cutColor: cutColor)
            case .sparkles:
                CuteSparklesView(color: mainColor)
            case .chats:
                CuteChatsView(mainColor: mainColor, cutColor: cutColor)
            case .group:
                CuteGroupView(color: mainColor)
            case .gear:
                CuteGearView(color: mainColor)
            case .footprint:
                CuteFootprintView(color: mainColor)
            case .eyeoff:
                CuteEyeOffView(color: mainColor)
            case .gauge:
                CuteGaugeView(color: mainColor)
            case .share:
                CuteShareView(color: mainColor)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 单个功能按钮磁贴组件 (PlusPanelTileButton)

public struct PlusPanelTileButton: View {
    let item: PlusPanelItemType
    let isDark: Bool
    let onTap: () -> Void

    @State private var isPressed: Bool = false

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

                    CuteDuduIcon(
                        type: item,
                        size: 26,
                        mainColor: CSSThemeVariables.textMain(isDark: isDark),
                        cutColor: CSSThemeVariables.accentSoft(isDark: isDark)
                    )
                }

                Text(item.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(TilePressButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(Text(item.title))
    }
}

private struct TilePressButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { pressed in
                isPressed = pressed
            }
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

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
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}
