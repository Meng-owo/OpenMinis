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

// MARK: - 实体可爱矢量图标 (CuteDuduIcon)

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

    public var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24.0
            func pt(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }

            switch type {
            case .zap:
                // 实体闪电
                var path = Path()
                path.move(to: pt(13.2, 2.6))
                path.addLine(to: pt(5.2, 13.4))
                path.addLine(to: pt(10.8, 13.4))
                path.addLine(to: pt(9.7, 21.3))
                path.addLine(to: pt(17.8, 10.4))
                path.addLine(to: pt(12.2, 10.4))
                path.closeSubpath()
                context.fill(path, with: .color(mainColor))

            case .image:
                // 外层实心底板 (圆角矩形)
                let rect = CGRect(x: 3.0 * scale, y: 4.5 * scale, width: 18.0 * scale, height: 15.0 * scale)
                let rPath = Path(roundedRect: rect, cornerRadius: 4.0 * scale)
                context.fill(rPath, with: .color(mainColor))

                // 镂空太阳圆点
                let sunRect = CGRect(x: (9.0 - 2.0) * scale, y: (10.0 - 2.0) * scale, width: 4.0 * scale, height: 4.0 * scale)
                context.fill(Path(ellipseIn: sunRect), with: .color(cutColor))

                // 镂空山峦
                var mPath = Path()
                mPath.move(to: pt(3.2, 16.8))
                mPath.addLine(to: pt(8.5, 11.5))
                mPath.addLine(to: pt(11.9, 14.9))
                mPath.addLine(to: pt(14.8, 12.0))
                mPath.addLine(to: pt(20.4, 17.6))
                mPath.addLine(to: pt(20.4, 18.8))
                mPath.addCurve(to: pt(17.2, 20.0), control1: pt(20.4, 19.5), control2: pt(18.9, 20.0))
                mPath.addLine(to: pt(7.0, 20.0))
                mPath.addCurve(to: pt(3.2, 18.0), control1: pt(5.0, 20.0), control2: pt(3.2, 19.5))
                mPath.closeSubpath()
                context.fill(mPath, with: .color(cutColor))

            case .doc:
                // 实心纸张 (右上折角)
                var dPath = Path()
                dPath.move(to: pt(7.0, 2.8))
                dPath.addLine(to: pt(13.8, 2.8))
                dPath.addLine(to: pt(19.0, 8.0))
                dPath.addLine(to: pt(19.0, 19.2))
                dPath.addCurve(to: pt(16.7, 21.5), control1: pt(19.0, 20.5), control2: pt(18.0, 21.5))
                dPath.addLine(to: pt(7.0, 21.5))
                dPath.addCurve(to: pt(4.7, 19.2), control1: pt(5.7, 21.5), control2: pt(4.7, 20.5))
                dPath.addLine(to: pt(4.7, 5.1))
                dPath.addCurve(to: pt(7.0, 2.8), control1: pt(4.7, 3.8), control2: pt(5.7, 2.8))
                dPath.closeSubpath()
                context.fill(dPath, with: .color(mainColor))

                // 内部两条镂空横线
                var lPath = Path()
                lPath.move(to: pt(9.2, 12.2))
                lPath.addLine(to: pt(14.8, 12.2))
                lPath.move(to: pt(9.2, 15.6))
                lPath.addLine(to: pt(14.8, 15.6))
                context.stroke(lPath, with: .color(cutColor), style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round))

            case .book:
                // 书本实体外壳
                var bPath = Path()
                bPath.move(to: pt(5.2, 4.6))
                bPath.addCurve(to: pt(6.8, 3.0), control1: pt(5.2, 3.7), control2: pt(5.9, 3.0))
                bPath.addLine(to: pt(19.0, 3.0))
                bPath.addLine(to: pt(19.0, 16.2))
                bPath.addLine(to: pt(6.8, 16.2))
                bPath.addCurve(to: pt(5.2, 17.8), control1: pt(5.9, 16.2), control2: pt(5.2, 16.9))
                bPath.closeSubpath()
                context.fill(bPath, with: .color(mainColor))

                // 镂空横线
                var bkLine = Path()
                bkLine.move(to: pt(9.0, 8.0))
                bkLine.addLine(to: pt(15.0, 8.0))
                context.stroke(bkLine, with: .color(cutColor), style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round))

            case .sticker:
                // 实心大圆脸
                let faceRect = CGRect(x: 3.0 * scale, y: 3.0 * scale, width: 18.0 * scale, height: 18.0 * scale)
                context.fill(Path(ellipseIn: faceRect), with: .color(mainColor))

                // 镂空双眼
                let leftEye = CGRect(x: (9.0 - 1.7) * scale, y: (10.0 - 1.7) * scale, width: 3.4 * scale, height: 3.4 * scale)
                let rightEye = CGRect(x: (15.0 - 1.7) * scale, y: (10.0 - 1.7) * scale, width: 3.4 * scale, height: 3.4 * scale)
                context.fill(Path(ellipseIn: leftEye), with: .color(cutColor))
                context.fill(Path(ellipseIn: rightEye), with: .color(cutColor))

                // 镂空微笑弧线
                var mouth = Path()
                mouth.move(to: pt(8.2, 14.3))
                mouth.addCurve(to: pt(12.0, 16.2), control1: pt(9.2, 15.5), control2: pt(10.5, 16.2))
                mouth.addCurve(to: pt(15.8, 14.3), control1: pt(13.5, 16.2), control2: pt(14.8, 15.5))
                context.stroke(mouth, with: .color(cutColor), style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round))

            case .sparkles:
                // 大星光
                var s1 = Path()
                s1.move(to: pt(11.0, 3.5))
                s1.addLine(to: pt(12.8, 8.7))
                s1.addLine(to: pt(18.0, 10.5))
                s1.addLine(to: pt(12.8, 12.3))
                s1.addLine(to: pt(11.0, 17.5))
                s1.addLine(to: pt(9.2, 12.3))
                s1.addLine(to: pt(4.0, 10.5))
                s1.addLine(to: pt(9.2, 8.7))
                s1.closeSubpath()
                context.fill(s1, with: .color(mainColor))

                // 小星光
                var s2 = Path()
                s2.move(to: pt(18.0, 14.2))
                s2.addLine(to: pt(18.9, 16.7))
                s2.addLine(to: pt(21.4, 17.6))
                s2.addLine(to: pt(18.9, 18.5))
                s2.addLine(to: pt(18.0, 21.0))
                s2.addLine(to: pt(17.1, 18.5))
                s2.addLine(to: pt(14.6, 17.6))
                s2.addLine(to: pt(17.1, 16.7))
                s2.closeSubpath()
                context.fill(s2, with: .color(mainColor))

            case .chats:
                // 实体气泡带小尾巴
                var cPath = Path()
                cPath.move(to: pt(5.5, 3.0))
                cPath.addLine(to: pt(18.5, 3.0))
                cPath.addCurve(to: pt(20.0, 4.5), control1: pt(19.3, 3.0), control2: pt(20.0, 3.7))
                cPath.addLine(to: pt(20.0, 14.0))
                cPath.addCurve(to: pt(18.5, 15.5), control1: pt(20.0, 14.8), control2: pt(19.3, 15.5))
                cPath.addLine(to: pt(9.8, 15.5))
                cPath.addLine(to: pt(4.0, 20.2))
                cPath.addLine(to: pt(4.0, 4.5))
                cPath.addCurve(to: pt(5.5, 3.0), control1: pt(4.0, 3.7), control2: pt(4.7, 3.0))
                cPath.closeSubpath()
                context.fill(cPath, with: .color(mainColor))

                // 气泡内镂空横线
                var cLines = Path()
                cLines.move(to: pt(8.0, 8.3))
                cLines.addLine(to: pt(16.0, 8.3))
                cLines.move(to: pt(8.0, 11.6))
                cLines.addLine(to: pt(13.0, 11.6))
                context.stroke(cLines, with: .color(cutColor), style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round))

            case .group:
                // 主人头
                let head1 = CGRect(x: (9.0 - 3.6) * scale, y: (8.0 - 3.6) * scale, width: 7.2 * scale, height: 7.2 * scale)
                context.fill(Path(ellipseIn: head1), with: .color(mainColor))

                // 主人体
                var b1 = Path()
                b1.move(to: pt(2.9, 20.1))
                b1.addCurve(to: pt(9.0, 14.4), control1: pt(3.6, 16.4), control2: pt(6.0, 14.4))
                b1.addCurve(to: pt(15.1, 20.1), control1: pt(12.0, 14.4), control2: pt(14.4, 16.4))
                b1.addLine(to: pt(13.8, 21.5))
                b1.addLine(to: pt(4.2, 21.5))
                b1.closeSubpath()
                context.fill(b1, with: .color(mainColor))

                // 副人头
                let head2 = CGRect(x: (16.9 - 2.7) * scale, y: (9.2 - 2.7) * scale, width: 5.4 * scale, height: 5.4 * scale)
                context.fill(Path(ellipseIn: head2), with: .color(mainColor))

                // 副人体肩膀弧线
                var b2 = Path()
                b2.move(to: pt(16.3, 14.7))
                b2.addCurve(to: pt(21.1, 19.5), control1: pt(18.7, 15.1), control2: pt(20.5, 16.8))
                context.stroke(b2, with: .color(mainColor), style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))

            case .gear:
                // 三条滑轨
                let bar1 = CGRect(x: 3.0 * scale, y: 5.0 * scale, width: 18.0 * scale, height: 2.6 * scale)
                let bar2 = CGRect(x: 3.0 * scale, y: 10.7 * scale, width: 18.0 * scale, height: 2.6 * scale)
                let bar3 = CGRect(x: 3.0 * scale, y: 16.4 * scale, width: 18.0 * scale, height: 2.6 * scale)
                context.fill(Path(roundedRect: bar1, cornerRadius: 1.3 * scale), with: .color(mainColor))
                context.fill(Path(roundedRect: bar2, cornerRadius: 1.3 * scale), with: .color(mainColor))
                context.fill(Path(roundedRect: bar3, cornerRadius: 1.3 * scale), with: .color(mainColor))

                // 三个滑块圆点
                let dot1 = CGRect(x: (9.0 - 3.1) * scale, y: (6.3 - 3.1) * scale, width: 6.2 * scale, height: 6.2 * scale)
                let dot2 = CGRect(x: (15.0 - 3.1) * scale, y: (12.0 - 3.1) * scale, width: 6.2 * scale, height: 6.2 * scale)
                let dot3 = CGRect(x: (8.0 - 3.1) * scale, y: (17.7 - 3.1) * scale, width: 6.2 * scale, height: 6.2 * scale)
                context.fill(Path(ellipseIn: dot1), with: .color(mainColor))
                context.fill(Path(ellipseIn: dot2), with: .color(mainColor))
                context.fill(Path(ellipseIn: dot3), with: .color(mainColor))

            case .footprint:
                // 左脚印 (轻微倾斜)
                var p1 = Path(ellipseIn: CGRect(x: -3.1 * scale, y: -4.1 * scale, width: 6.2 * scale, height: 8.2 * scale))
                var t1 = CGAffineTransform(translationX: 9.3 * scale, y: 7.2 * scale)
                t1 = t1.rotated(by: -12.0 * .pi / 180.0)
                p1 = p1.applying(t1)
                context.fill(p1, with: .color(mainColor))

                // 右脚印 (轻微倾斜)
                var p2 = Path(ellipseIn: CGRect(x: -3.1 * scale, y: -4.1 * scale, width: 6.2 * scale, height: 8.2 * scale))
                var t2 = CGAffineTransform(translationX: 15.0 * scale, y: 16.2 * scale)
                t2 = t2.rotated(by: -12.0 * .pi / 180.0)
                p2 = p2.applying(t2)
                context.fill(p2, with: .color(mainColor))

            case .eyeoff:
                // 眼睛闭合弧线轮廓
                var eye = Path()
                eye.move(to: pt(2.6, 12.0))
                eye.addCurve(to: pt(12.0, 6.0), control1: pt(6.2, 6.0), control2: pt(12.0, 6.0))
                eye.addCurve(to: pt(21.4, 12.0), control1: pt(12.0, 6.0), control2: pt(17.8, 6.0))
                eye.addCurve(to: pt(12.0, 18.0), control1: pt(17.8, 18.0), control2: pt(12.0, 18.0))
                eye.addCurve(to: pt(2.6, 12.0), control1: pt(12.0, 18.0), control2: pt(6.2, 18.0))
                context.fill(eye, with: .color(mainColor))

                // 倾斜镂空斜杠
                var cutSlash = Path(roundedRect: CGRect(x: -8.5 * scale, y: -1.3 * scale, width: 17.0 * scale, height: 2.6 * scale), cornerRadius: 1.3 * scale)
                var tSlash = CGAffineTransform(translationX: 12.0 * scale, y: 12.0 * scale)
                tSlash = tSlash.rotated(by: -22.0 * .pi / 180.0)
                cutSlash = cutSlash.applying(tSlash)
                context.fill(cutSlash, with: .color(cutColor))

            case .gauge:
                // 圆弧
                var gArc = Path()
                gArc.addArc(center: pt(12.0, 15.0), radius: 7.5 * scale, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                context.stroke(gArc, with: .color(mainColor), style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round))

                // 指针
                var gNeedle = Path()
                gNeedle.move(to: pt(12.0, 15.0))
                gNeedle.addLine(to: pt(16.0, 9.8))
                context.stroke(gNeedle, with: .color(mainColor), style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))

                // 表芯圆点
                let gCore = CGRect(x: (12.0 - 2.1) * scale, y: (15.0 - 2.1) * scale, width: 4.2 * scale, height: 4.2 * scale)
                context.fill(Path(ellipseIn: gCore), with: .color(mainColor))

                // 底座线
                var gBase = Path()
                gBase.move(to: pt(4.0, 20.0))
                gBase.addLine(to: pt(20.0, 20.0))
                context.stroke(gBase, with: .color(mainColor), style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))

            case .share:
                // 托盘底座
                var sTray = Path()
                sTray.move(to: pt(4.5, 13.5))
                sTray.addLine(to: pt(4.5, 19.5))
                sTray.addLine(to: pt(19.5, 19.5))
                sTray.addLine(to: pt(19.5, 13.5))
                sTray.addLine(to: pt(15.9, 13.5))
                sTray.addLine(to: pt(15.9, 16.1))
                sTray.addLine(to: pt(8.1, 16.1))
                sTray.addLine(to: pt(8.1, 13.5))
                sTray.closeSubpath()
                context.fill(sTray, with: .color(mainColor))

                // 向上箭头
                var sArrow = Path()
                sArrow.move(to: pt(12.0, 11.0))
                sArrow.addLine(to: pt(12.0, 2.5))
                sArrow.move(to: pt(8.2, 6.3))
                sArrow.addLine(to: pt(12.0, 2.5))
                sArrow.addLine(to: pt(15.8, 6.3))
                context.stroke(sArrow, with: .color(mainColor), style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round, lineJoin: .round))
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
                        size: 28,
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
