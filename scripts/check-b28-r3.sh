#!/bin/sh
# [B28 round 3] 真机反馈三条：alert 层级、标题重复、内外卡片语言。
cd "$(dirname "$0")/.." || exit 2
V=src/ios/Views/Settings/AppearanceStudioView.swift
fail=0
ok()  { printf 'OK   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }

# R3-1 主题库里的「删」必须就地弹确认：alert 得挂在子页宿主上（pageContent 链），
# 不能留在根页 List —— 真机实测挂在根页时，弹框要退回上一页才出现。
AL=$(rg -n '\.alert\(alertTitle' "$V" | head -1 | cut -d: -f1)
SV=$(rg -n 'ScrollView \{' "$V" | head -1 | cut -d: -f1)
if [ -n "$AL" ] && [ -n "$SV" ] && [ "$AL" -gt "$SV" ]; then ok R3-1; else bad "R3-1 alert 还在根页链上（行 $AL < 子页宿主 $SV）"; fi

# R3-2 页名不在左上角和内容里出现两遍：「外观」「主题库」这种重复标题清零
if ! rg -q 'navigationTitle\(AppLocalized\("Appearance"\)\)' "$V" && ! rg -q 'navigationTitle\(item\.title\)' "$V"; then
  ok R3-2; else bad "R3-2 还有重复的页面标题"; fi

# R3-3 内外卡片同一语言：圆角和系统分组列表对齐（10pt continuous、无阴影）
if rg -A20 "struct StudioCard" "$V" | rg -q "cornerRadius: 10"; then ok R3-3; else bad "R3-3 子页卡片还是另一套圆角"; fi

echo "----"
if [ "$fail" -gt 0 ]; then echo "$fail FAILED"; exit 1; else echo "全部通过"; fi
