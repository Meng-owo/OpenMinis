//
//  TogetherThemeCenterView.swift
//  MinisApp
//
//  一起听 · 独立装扮与壁纸中心。
//  彻底告别长按隐蔽手势。我和醒醒都能随时换，AI 在后台也能通过 together wallpaper 一键换。
//

import SwiftUI
import UniformTypeIdentifiers

struct TogetherThemeCenterView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var state = TogetherStore.shared.load()
    @State private var activeSlot: String?
    @State private var pendingImage: [URL] = []

    private let slots: [(id: String, title: String, subtitle: String)] = [
        (TogetherImages.wallpaperNow, TogetherCopy.nowPlayingWallpaper, "播放主界面的全屏氛围大壁纸"),
        (TogetherImages.lyricsCover, TogetherCopy.lyricsWallpaper, "歌词页面的背景与专属封面"),
        (TogetherImages.wallpaperLibrary, TogetherCopy.libraryWallpaper, "所有歌单列表的背景壁纸"),
        (TogetherImages.wallpaperSync, TogetherCopy.syncWallpaper, "双人伴听同步页面的背景"),
        (TogetherImages.wallpaperLiked, TogetherCopy.likedWallpaper, "红心喜欢歌曲列表的背景"),
        (TogetherImages.wallpaperSweet, TogetherCopy.sweetWallpaper, "小梦给醒醒挑的私藏壁纸"),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(slots, id: \.id) { slot in
                            slotCard(slot)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .background(CSSThemeVariables.bg(scope: .chat).ignoresSafeArea())
            .navigationTitle(TogetherCopy.themeCenter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized("Done", comment: "完成")) {
                        dismiss()
                    }
                    .font(ChatFont.font(14, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.accent(scope: .chat))
                }
            }
            .sheet(item: Binding<SlotItem?>(
                get: { activeSlot.map { SlotItem(id: $0) } },
                set: { activeSlot = $0?.id }
            )) { item in
                DocumentCopyPicker(contentTypes: [.image], allowsMultipleSelection: false) { urls in
                    pendingImage = urls
                } onDone: {
                    if let first = pendingImage.first {
                        _ = TogetherStore.shared.setImage(slot: item.id, from: first)
                    }
                    pendingImage = []
                    activeSlot = nil
                    state = TogetherStore.shared.load()
                }
            }
        }
    }

    private var headerBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(ChatFont.font(24))
                .foregroundStyle(CSSThemeVariables.accent(scope: .chat))

            VStack(alignment: .leading, spacing: 3) {
                Text("我们俩的音乐专属装扮")
                    .font(ChatFont.font(14, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                Text("点击直接更换，或者让我在后台随时为你挑一张换上")
                    .font(ChatFont.font(11))
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CSSThemeVariables.card(scope: .chat))
        )
    }

    private func slotCard(_ slot: (id: String, title: String, subtitle: String)) -> some View {
        let hasCustom = TogetherImages.url(for: slot.id) != nil

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if let url = TogetherImages.url(for: slot.id),
                   let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    TogetherCover.fill(slot.id)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Image(systemName: "photo.on.rectangle")
                                .font(ChatFont.font(26))
                                .foregroundStyle(CSSThemeVariables.card(scope: .chat).opacity(0.8))
                        )
                }

                if hasCustom {
                    Button {
                        TogetherStore.shared.clearImage(slot: slot.id)
                        state = TogetherStore.shared.load()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(ChatFont.font(18))
                            .foregroundStyle(CSSThemeVariables.danger(scope: .chat))
                            .background(Circle().fill(Color.white))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                    .font(ChatFont.font(12, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                    .lineLimit(1)
                Text(slot.subtitle)
                    .font(ChatFont.font(9.5))
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                    .lineLimit(1)
            }

            Button {
                activeSlot = slot.id
            } label: {
                Text(TogetherCopy.changeCoverTitle)
                    .font(ChatFont.font(11, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.accent(scope: .chat))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CSSThemeVariables.optionBg(scope: .chat))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CSSThemeVariables.card(scope: .chat))
        )
    }
}

private struct SlotItem: Identifiable {
    let id: String
}
