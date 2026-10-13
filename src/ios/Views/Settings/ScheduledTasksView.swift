//
//  ScheduledTasksView.swift
//  MinisApp
//
//  Complete management screen for scheduled tasks and proactive pulses.
//  Aligns with and surpasses Android's ScheduledTasksScreen.
//  Driven 100% by CSSThemeVariables.
//

import SwiftUI

struct ScheduledTasksView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var registry = AgentJobRegistry.shared

    @State private var selectedJobId: String? = nil
    @State private var pendingDeleteId: String? = nil

    @ObservedObject private var fontSettings = FontSettings.shared
    private var isDark: Bool { colorScheme == .dark }
    private var allJobs: [AgentJob] { registry.list() }

    /// [AUD-10] The row waiting for its delete confirmation.
    private var pendingJob: AgentJob? { pendingDeleteId.flatMap { registry.job(id: $0) } }

    /// [AUD-10] Delete = cancel + remove, the same pair the CLI uses. `remove`
    /// on its own dropped the timer and left a running child session working
    /// for a result nobody would ever receive.
    private func performDelete() {
guard let id = pendingDeleteId else { return }
        registry.cancel(jobId: id, reason: "ui delete")
        registry.remove(jobId: id)
        pendingDeleteId = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("定时任务与脉搏")
                    .font(.system(size: fontSettings.scaledApp(20), weight: .bold))
                    .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: fontSettings.scaledApp(13), weight: .semibold))
                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                        .frame(width: 32, height: 32)
                        .background(CSSThemeVariables.optionBg(isDark: isDark))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .overlay(CSSThemeVariables.divider(isDark: isDark))

            // Body
            if allJobs.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: fontSettings.scaledApp(44)))
                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.6))
                    Text("暂无挂载的定时任务或脉搏")
                        .font(.system(size: fontSettings.scaledApp(15), weight: .medium))
                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                    Text("可以在聊天里直接创建一个。")
                        .font(.system(size: fontSettings.scaledApp(12)))
                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    // Summary Section
                    Section {
                        HStack(spacing: 16) {
                            summaryCard(title: "总任务数", count: allJobs.count, icon: "list.bullet")
                            summaryCard(title: "活跃运行中", count: allJobs.filter { $0.isEnabled && $0.state != .done }.count, icon: "play.circle.fill")
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 8)
                    }

                    // Task Items Section
                    Section {
                        ForEach(allJobs) { job in
                            taskRow(for: job)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedJobId = job.id
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        pendingDeleteId = job.id
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .alert("删除这个任务？", isPresented: Binding(
                    get: { pendingDeleteId != nil },
                    set: { if !$0 { pendingDeleteId = nil } }
                )) {
                    Button("取消", role: .cancel) { pendingDeleteId = nil }
                    Button("删除", role: .destructive) { performDelete() }
                } message: {
                    Text(pendingJob?.deleteConfirmMessage ?? "删除后无法恢复。")
                }
                .scrollContentBackground(.hidden)
                .background(CSSThemeVariables.bg(isDark: isDark))
            }
        }
        .background(CSSThemeVariables.bg(isDark: isDark))
        .sheet(item: Binding<IdentifiableJobId?>(
            get: { selectedJobId.map { IdentifiableJobId(id: $0) } },
            set: { selectedJobId = $0?.id }
        )) { ident in
            ScheduledTaskDetailSheet(jobId: ident.id)
        }
    }

    private func summaryCard(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: fontSettings.scaledApp(20)))
                .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: fontSettings.scaledApp(11)))
                    .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                Text("\(count)")
                    .font(.system(size: fontSettings.scaledApp(18), weight: .bold))
                    .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CSSThemeVariables.card(isDark: isDark))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func taskRow(for job: AgentJob) -> some View {
        HStack(spacing: 12) {
            Image(systemName: job.isPulse ? "waveform.path.ecg" : "clock.arrow.circlepath")
                .font(.system(size: fontSettings.scaledApp(16), weight: .semibold))
                .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                .frame(width: 34, height: 34)
                .background(CSSThemeVariables.accentSoft(isDark: isDark))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(.system(size: fontSettings.scaledApp(15), weight: .semibold))
                        .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                        .lineLimit(1)

                    if job.isPulse {
                        Text("脉搏")
                            .font(.system(size: fontSettings.scaledApp(10), weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(CSSThemeVariables.accentSoft(isDark: isDark))
                            .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(job.trigger.humanLabel)
                        .font(.system(size: fontSettings.scaledApp(12)))
                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

                    if let next = job.nextFireAt {
                        Text("下次: \(formatNext(next))")
                            .font(.system(size: fontSettings.scaledApp(11)))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.8))
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding<Bool>(
                get: { job.isEnabled },
                set: { registry.setEnabled(jobId: job.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: CSSThemeVariables.accent(isDark: isDark)))
        }
        .padding(.vertical, 4)
    }

    /// [AUD-17] Was a private "5m / 2h" shorthand; now the shared human phrasing
    /// so the list and the detail sheet cannot drift apart.
    private func formatNext(_ date: Date) -> String { ScheduledTimeText.upcoming(date) }
}

private struct IdentifiableJobId: Identifiable {
    let id: String
}
