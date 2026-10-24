//
//  TogetherSkin.swift
//  MinisApp
//
//  一起听 · 皮肤层 + 文案层。
//
//  结构层定死（六屏布局、坐标、动效曲线），皮肤层全可换。
//  默认值一律从 App 主题派生：换 minis-theme 这一页跟着变，代码里没有裸色值。
//
//  额外留了一层自己的覆盖：together/skin.json。
//  我（shell 里的 together set skin.xxx）和你都能改它，改完面板不重启就变。
//  全局主题管基础色，这一层管"这一间屋子"的味道。
//

import SwiftUI

// MARK: - 皮肤

struct TogetherSkinValues: Codable, Equatable {
    /// 唱片本体：0 = 用主题主文字色，1 = 纯黑。中间值是深浅。
    var vinylDepth: Double = 0.9
    /// 唱片纹路的透明度
    var vinylRing: Double = 0.055
    /// 卡片/唱片中心圆的圆角
    var cardRadius: Double = 20
    /// 阴影强度 0–1
    var shadow: Double = 1.0
    /// 壁纸档位：warm / cool / rose（对应主题里三套背景）
    var wall: String = "warm"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vinylDepth = (try? c.decodeIfPresent(Double.self, forKey: .vinylDepth)) ?? 0.9
        vinylRing = (try? c.decodeIfPresent(Double.self, forKey: .vinylRing)) ?? 0.055
        cardRadius = (try? c.decodeIfPresent(Double.self, forKey: .cardRadius)) ?? 20
        shadow = (try? c.decodeIfPresent(Double.self, forKey: .shadow)) ?? 1.0
        wall = (try? c.decodeIfPresent(String.self, forKey: .wall)) ?? "warm"
    }
}

enum TogetherSkin {

    static var values: TogetherSkinValues {
        let url = TogetherStore.shared.rootURL.appendingPathComponent("skin.json")
        guard let data = try? Data(contentsOf: url),
              let v = try? JSONDecoder().decode(TogetherSkinValues.self, from: data) else {
            return TogetherSkinValues()
        }
        return v
    }

    /// 唱片色。深浅由 vinylDepth 控制，色相永远来自主题主文字色。
    static var vinyl: Color {
        let depth = min(1, max(0, values.vinylDepth))
        return CSSThemeVariables.textMain(scope: .chat).opacity(0.72 + 0.28 * depth)
    }

    static var vinylRing: Color {
        CSSThemeVariables.bg(scope: .chat).opacity(values.vinylRing)
    }

    static var shadowDeep: Color {
        .black.opacity(0.22 * values.shadow)
    }

    static var shadowSoft: Color {
        .black.opacity(0.14 * values.shadow)
    }

    static var cardRadius: CGFloat { CGFloat(values.cardRadius) }
}

// MARK: - 文案
//
// 一处集中，全部走本地化。改文案只改这里，不在六个视图里找。
// 名字永远是变量：出现人的地方用 ChatAddressing，不写死。

enum TogetherCopy {
    static var title: String { AppLocalized("Together", comment: "一起听 · 面板标题") }
    static var emptyTitle: String { AppLocalized("No songs yet", comment: "一起听 · 空状态标题") }
    static var emptyHint: String {
        AppLocalized("I'll find something, or drop a file in.", comment: "一起听 · 空状态说明")
    }
    static var like: String { AppLocalized("Like", comment: "一起听 · 喜欢") }
    static var comment: String { AppLocalized("Note", comment: "一起听 · 留言") }
    static var addToPlaylist: String { AppLocalized("Add", comment: "一起听 · 加到歌单") }
    static var volume: String { AppLocalized("Volume", comment: "一起听 · 音量") }
    static var leaveNoteTitle: String { AppLocalized("Leave a line at", comment: "一起听 · 留言位置标题") }
    static var leaveNotePlaceholder: String {
        AppLocalized("Wait for you at this line", comment: "一起听 · 留言输入占位")
    }
    static var leaveNoteAction: String { AppLocalized("Leave it", comment: "一起听 · 留言提交") }
    static var nowPlaying: String { AppLocalized("Now playing", comment: "一起听 · 顶栏") }
}