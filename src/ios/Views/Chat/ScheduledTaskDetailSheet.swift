//
//  ScheduledTaskDetailSheet.swift
//  MinisApp
//
//  Beautiful detail & control sheet for scheduled tasks and proactive pulses.
//  Driven 100% by CSSThemeVariables.
//

import SwiftUI

struct ScheduledTaskDetailSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var registry = AgentJobRegistry.shared

    let jobId: String
    @State private var runsList: [ScheduledRun] = []
    @State private var isRunningNow = false
    @State private var confirmDelete = false

    private var isDark: Bool { colorScheme == .dark }
    private var job: AgentJob? { registry.job(id: jobId) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag grabber
            Capsule()
                .fill(CSSThemeVariables.divider(isDark: isDark))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            if let job = job {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: job.isPulse ? "waveform.path.ecg" : "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                        .frame(width: 44, height: 44)
                        .background(CSSThemeVariables.accentSoft(isDark: isDark))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(job.isPulse ? "自主脉搏" : "定时任务")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CSSThemeVariables.accentSoft(isDark: isDark))
                                .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                                .clipShape(Capsule())

                            statusBadge(for: job)
                        }
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                            .frame(width: 30, height: 30)
                            .background(CSSThemeVariables.optionBg(isDark: isDark))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                Divider()
                    .overlay(CSSThemeVariables.divider(isDark: isDark))

                // Scrollable Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Action buttons row
                        HStack(spacing: 10) {
                            // Run Now Button
                            Button {
                                triggerRunNow(job)
                            } label: {
                                HStack(spacing: 6) {
                                    if isRunningNow {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: job.isPulse ? "hand.tap.fill" : "play.fill")
                                            .font(.system(size: 12))
                                    }
                                    Text(job.isPulse ? "戳一下" : "立即运行")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(CSSThemeVariables.accent(isDark: isDark))
                                .foregroundStyle(CSSThemeVariables.accentFg(isDark: isDark))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(isRunningNow)

                            // Enable / Disable Toggle
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                registry.setEnabled(jobId: job.id, enabled: !job.isEnabled)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: job.isEnabled ? "pause.fill" : "play.fill")
                                        .font(.system(size: 12))
                                    Text(job.isEnabled ? "暂停" : "恢复")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(CSSThemeVariables.optionBg(isDark: isDark))
                                .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // Delete Button
                            Button {
                                let impact = UINotificationFeedbackGenerator()
                                impact.notificationOccurred(.warning)
                                confirmDelete = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(CSSThemeVariables.optionBg(isDark: isDark))
                                    .foregroundStyle(CSSThemeVariables.danger(isDark: isDark))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.top, 4)

                        // Properties Card
                        VStack(spacing: 12) {
                            detailRow(label: "触发规则", value: job.trigger.humanLabel, icon: "repeat")
                            if let next = job.nextFireAt {
                                detailRow(label: "下次触发", value: ScheduledTimeText.upcoming(next), icon: "timer")
                            }
                            detailRow(label: "已触发次数", value: "\(job.firedCount) 次", icon: "number")
                            if let r = job.remaining {
                                detailRow(label: "剩余次数", value: "\(r) 次", icon: "hourglass")
                            }
                            if let dlv = job.deliverySentenceHuman {
                                detailRow(label: "递送说明", value: dlv, icon: "paperplane")
                            }
                            if let cmd = job.prefilledTool?.shellCommand {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 12))
                                            .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                                        Text("预填命令")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                                    }
                                    Text(cmd)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(CSSThemeVariables.optionBg(isDark: isDark))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            if let p = job.prompt, !p.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "text.bubble")
                                            .font(.system(size: 12))
                                            .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                                        Text("提示词内容")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                                    }
                                    Text(p)
                                        .font(.system(size: 13))
                                        .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(CSSThemeVariables.optionBg(isDark: isDark))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                        .padding(16)
                        .background(CSSThemeVariables.card(isDark: isDark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // Runs History Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("运行记录 (最新 \(runsList.count) 条)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

                            if runsList.isEmpty {
                                Text("暂无触发记录")
                                    .font(.system(size: 13))
                                    .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.7))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(runsList) { run in
                                    HStack(spacing: 10) {
                                        Image(systemName: run.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(run.ok ? CSSThemeVariables.success(isDark: isDark)
                                                : CSSThemeVariables.danger(isDark: isDark))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ScheduledTimeText.past(run.firedAt) + " · " + ScheduledTimeText.clockText(run.firedAt))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                            if let prev = run.preview {
                                                Text(prev)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        if let sid = run.sessionId {
                                            Text(String(sid.prefix(6)))
                                                .font(.system(size: 10, design: .monospaced))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(CSSThemeVariables.optionBg(isDark: isDark))
                                                .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                    .padding(10)
                                    .background(CSSThemeVariables.optionBg(isDark: isDark))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                        .padding(16)
                        .background(CSSThemeVariables.card(isDark: isDark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                    Text("未找到该任务或任务已结束")
                        .font(.system(size: 14))
                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .background(CSSThemeVariables.bg(isDark: isDark))
        .alert("删除这个任务？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { deleteJob() }
        } message: {
            Text(job?.deleteConfirmMessage ?? "删除后无法恢复。")
        }
        .onAppear {
            if let j = job {
                runsList = registry.runs(jobId: j.id)
            }
        }
    }

    /// [AUD-10] Delete = cancel + remove, the same pair the CLI uses. `remove`
    /// alone dropped the timer and left a running child session working for a
    /// result nobody would ever receive.
    private func deleteJob() {
        guard let job else { return }
        registry.cancel(jobId: job.id, reason: "ui delete")
        registry.remove(jobId: job.id)
        dismiss()
    }

    private func statusBadge(for job: AgentJob) -> some View {
        let text: String
        let color: Color
        if !job.isEnabled {
            text = "已暂停"
            color = CSSThemeVariables.warning(isDark: isDark)
        } else if job.state == .running {
            text = "运行中"
            color = CSSThemeVariables.success(isDark: isDark)
        } else if job.state == .done {
            text = "已完成"
            color = CSSThemeVariables.accent(isDark: isDark)
        } else {
            text = "等待中"
            color = CSSThemeVariables.accent(isDark: isDark)
        }

        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func detailRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                .frame(width: 16, alignment: .leading)
                .padding(.top, 2)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                .multilineTextAlignment(.trailing)
        }
    }

    private func triggerRunNow(_ job: AgentJob) {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        isRunningNow = true
        Task {
            _ = await ScheduledJobRunner.fireNow(job)
            await MainActor.run {
                isRunningNow = false
                runsList = registry.runs(jobId: job.id)
            }
        }
    }
}
