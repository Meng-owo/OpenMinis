import Foundation
import SwiftUI

// MARK: - 摇一套配色
//
// [10-18 醒醒] 「他那个调色盘随机摇骰子也不错啊。他的构思可以学。」
//
// 参考的是 LiveTheme 那个思路：不给你十六个色去自己配，而是**按一套配色
// 骨架摇**——先定一个主色（色相 + 饱和度 + 明度），其余角色全部由它推导
// 出来，保证摇出来一定是协调的，不会出现粉底配荧光绿。
//
// 关键不是"随机十六个色"，是"随机一个色，其余按规则算"。所以：
// - 摇一百次也不会出丑的
// - 但也不是只有一种风格（色相、冷暖、深浅都在摇）
//
// 推导规则（浅色为例，深色另算）：
//   主色 accent         ← 摇
//   canvas              ← 主色同色相，明度拉到接近白
//   surface             ← 比 canvas 再亮一点（或纯白）
//   raised              ← 比 surface 再亮（浮层要"浮起来"）
//   mutedSurface        ← 比 canvas 暗一档
//   iconTile            ← 介于 mutedSurface 和 surface 之间
//   chip                ← 比 iconTile 再深一点点
//   field               ← 跟 surface 同档，略偏主色
//   border              ← 比 canvas 暗两档
//   primaryText         ← 主色同色相，明度压到很低（不用纯黑）
//   secondaryText       ← 主色同色相，明度中等
//   userBubble          ← 主色，明度很高（淡）
//   assistantBubble     ← 跟 surface 一样
//   success/warning/destructive ← 固定语义色，只微调明度贴合整体

enum AppearanceThemeShuffle {

    /// 摇一套。`seed` 传 nil 就是真随机；传固定值可以复现同一套。
    static func shuffle(seed: UInt64? = nil) -> (light: [AppearanceColorRole: String],
                                                 dark: [AppearanceColorRole: String],
                                                 name: String) {
        var rng = SplitMix64(seed: seed ?? UInt64.random(in: 0...UInt64.max))

        // 1. 摇主色：色相全圈，饱和度收在中段（太艳会俗），明度按浅/深分别定
        let hue = Double(rng.next() % 3600) / 10.0
        let sat = Double(38 + rng.next() % 30) / 100.0   // 0.38 ... 0.67
        let accentLight = hsl(hue, sat, 0.52)
        let accentDark = hsl(hue, sat * 0.78, 0.66)

        // 2. 冷暖微调：整体底色往主色偏一点点，不要偏成另一种颜色
        let canvasLight = hsl(hue, min(0.16, sat * 0.26), 0.975)
        let canvasDark = hsl(hue, min(0.14, sat * 0.22), 0.095)

        let light: [AppearanceColorRole: String] = [
            .canvas: canvasLight,
            .surface: hsl(hue, min(0.12, sat * 0.20), 0.992),
            .raised: hsl(hue, min(0.10, sat * 0.17), 1.0),
            .mutedSurface: hsl(hue, min(0.18, sat * 0.30), 0.945),
            .iconTile: hsl(hue, min(0.16, sat * 0.27), 0.958),
            .chip: hsl(hue, min(0.20, sat * 0.33), 0.925),
            .field: hsl(hue, min(0.14, sat * 0.23), 0.988),
            .border: hsl(hue, min(0.14, sat * 0.24), 0.885),
            .primaryText: hsl(hue, min(0.22, sat * 0.36), 0.145),
            .secondaryText: hsl(hue, min(0.18, sat * 0.30), 0.475),
            .accent: accentLight,
            .userBubble: hsl(hue, min(0.46, sat * 0.76), 0.905),
            .assistantBubble: hsl(hue, min(0.12, sat * 0.20), 0.992),
            .success: hsl(148, 0.26, 0.475),
            .warning: hsl(34, 0.52, 0.545),
            .destructive: hsl(2, 0.48, 0.545),
        ]

        let dark: [AppearanceColorRole: String] = [
            .canvas: canvasDark,
            .surface: hsl(hue, min(0.14, sat * 0.23), 0.155),
            .raised: hsl(hue, min(0.14, sat * 0.23), 0.205),
            .mutedSurface: hsl(hue, min(0.16, sat * 0.26), 0.225),
            .iconTile: hsl(hue, min(0.16, sat * 0.26), 0.238),
            .chip: hsl(hue, min(0.18, sat * 0.29), 0.262),
            .field: hsl(hue, min(0.14, sat * 0.23), 0.180),
            .border: hsl(hue, min(0.16, sat * 0.26), 0.300),
            .primaryText: hsl(hue, min(0.14, sat * 0.22), 0.935),
            .secondaryText: hsl(hue, min(0.14, sat * 0.23), 0.705),
            .accent: accentDark,
            .userBubble: hsl(hue, min(0.34, sat * 0.56), 0.300),
            .assistantBubble: hsl(hue, min(0.14, sat * 0.23), 0.155),
            .success: hsl(148, 0.24, 0.665),
            .warning: hsl(34, 0.46, 0.685),
            .destructive: hsl(2, 0.50, 0.700),
        ]

        return (light, dark, name(for: hue, sat: sat))
    }

    /// 摇出来的名字。不为了起名而起名，只在她点「存这套」时给个默认值。
    private static func name(for hue: Double, sat: Double) -> String {
        let hueName: String
        switch hue {
        case ..<18, 340...: hueName = "石榴"
        case ..<45: hueName = "橘"
        case ..<70: hueName = "杏"
        case ..<105: hueName = "苔"
        case ..<150: hueName = "薄荷"
        case ..<185: hueName = "湖"
        case ..<215: hueName = "海"
        case ..<255: hueName = "夜"
        case ..<285: hueName = "薰衣草"
        case ..<315: hueName = "紫"
        default: hueName = "樱"
        }
        let tone = sat > 0.55 ? "浓" : (sat > 0.46 ? "中" : "淡")
        return hueName + tone
    }

    // MARK: - HSL → HEX

    /// HSL 转十六进制。`h` 是 0...360 的度数，`s`/`l` 是 0...1。
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> String {
        let hh = h.truncatingRemainder(dividingBy: 360) / 360
        let ss = min(1, max(0, s))
        let ll = min(1, max(0, l))

        func hue2rgb(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }

        let r: Double, g: Double, b: Double
        if ss == 0 {
            r = ll; g = ll; b = ll
        } else {
            let q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss
            let p = 2 * ll - q
            r = hue2rgb(p, q, hh + 1.0 / 3.0)
            g = hue2rgb(p, q, hh)
            b = hue2rgb(p, q, hh - 1.0 / 3.0)
        }
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// 小而快的伪随机。用它而不是 `Int.random` 是为了「同一套能复现」——
/// 摇到喜欢的可以留着，摇到不喜欢按回去也不会一样。
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
