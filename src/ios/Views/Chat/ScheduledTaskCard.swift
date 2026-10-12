//
//  ScheduledTaskCard.swift
//  MinisApp
//
//  Elegant in-chat scheduled task / proactive pulse card.
//  Driven 100% by CSSThemeVariables.
//

import SwiftUI

// [AUD-10] One wording for the two delete entry points (the list swipe and the
// detail sheet's trash button), because they delete the same thing.
extension AgentJob {
    /// The question the delete confirmation asks, including what else dies with it.
    var deleteConfirmMessage: String {
        if hasRunningChild {
            return "「\(title)」的子任务还在运行。删除会把这次运行一并停掉，它的结果不会再回到会话里。"
        }
        if state == .running || state == .pending {
            return "「\(title)」还在等待触发，删除后不会再运行，历史记录也会一起消失。"
        }
        return "「\(title)」的运行记录会一起消失，删除后无法恢复。"
    }
}

struct ScheduledTaskCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var registry = AgentJobRegistry.shared

    let jobId: String
    @State private var showingDetail = false

    private var isDark: Bool { colorScheme == .dark }
    private var job: AgentJob? { registry.job(id: jobId) }

    var body: some View {
        if let job = job {
            Button {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                showingDetail = true
            } label: {
                HStack(spacing: 12) {
                    // Left Icon
                    ZStack {
                        Circle()
                            .fill(CSSThemeVariables.accentSoft(isDark: isDark))
                            .frame(width: 38, height: 38)

                        Image(systemName: job.isPulse ? "waveform.path.ecg" : "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                    }

                    // Middle Info
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(job.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                .lineLimit(1)

                            Text(job.isPulse ? "脉搏" : "定时")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(CSSThemeVariables.accentSoft(isDark: isDark))
                                .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 8) {
                            Text(job.trigger.logLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

                            if let next = job.nextFireAt {
                                Text("下次: \(formatNext(next))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.8))
                            }
                        }
                    }

                    Spacer()

                    // Right Status & Chevron
                    HStack(spacing: 6) {
                        Circle()
                            .fill(job.isEnabled ? CSSThemeVariables.success(isDark: isDark)
                                : CSSThemeVariables.warning(isDark: isDark))
                            .frame(width: 7, height: 7)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(CSSThemeVariables.card(isDark: isDark))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: CSSThemeVariables.sheetShadow(isDark: isDark).opacity(0.04), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showingDetail) {
                ScheduledTaskDetailSheet(jobId: job.id)
            }
        }
    }

    private func formatNext(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff < 60 {
            return "即将触发"
        } else if diff < 3600 {
            return "\(Int(diff / 60))分钟后"
        } else if diff < 86400 {
            return "\(Int(diff / 3600))小时后"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            return f.string(from: date)
        }
    }
}

// MARK: - 自主脉搏触发卡片（聊天流内，仅脉搏类任务渲染）

/// [T-scheduled-prefill-and-pulse] 小梦被自主脉搏唤醒时在会话里留下的一张轻声卡片。
/// 普通定时任务仍然完全隐身（不打扰），只有「脉搏」——小梦主动想找醒醒——
/// 才会留下这个痕迹，且体积小、无边框噪音。点一下即可看到完整详情与运行记录。
struct ScheduledPulseCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var registry = AgentJobRegistry.shared
    let jobId: String
    let title: String
    var fireIndex: Int?
    var remaining: Int?

    @State private var showingDetail = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            showingDetail = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CSSThemeVariables.accentSoft(isDark: isDark))
                        .frame(width: 30, height: 30)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalized("小梦 · 自主脉搏"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 11))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                            .lineLimit(1)
                        if let f = fireIndex {
                            Text("· 第\(f)次")
                                .font(.system(size: 11))
                                .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.8))
                        }
                        if let r = remaining, r > 0 {
                            Text("· 剩\(r)")
                                .font(.system(size: 11))
                                .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.8))
                        }
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(CSSThemeVariables.card(isDark: isDark))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: CSSThemeVariables.sheetShadow(isDark: isDark).opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .sheet(isPresented: $showingDetail) {
            ScheduledTaskDetailSheet(jobId: jobId)
        }
    }
}
