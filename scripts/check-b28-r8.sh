#!/usr/bin/env bash
# [10-23 醒醒 R8] 四条体感问题的回归断言。
# 她原话：① 用户气泡展开/收起屏幕一跳一跳 ② AI 代码块展开挡着气泡
# ③ 滑动看上下文一卡一卡、自己跳到没滑到的位置 ④ 她自己发的代码块没了
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "  ok  $1"; }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

C=src/ios/Views/Chat/ChatMessageViews.swift
V3=src/ios/Agent/MessageList/CollectionViewMessageListV3.swift
L=src/ios/Agent/MessageList/MessageListLayout.swift
S=src/ios/Views/Chat/SelectableMarkdownView.swift

# R8-1 自带围栏的代码也要走代码块（旧判据只认 autoFenced 改动过文本）
if rg -qF 'text.contains("```") || UserCodeFencing.autoFenced(text) != text' "$C"; then
  ok R8-1; else bad "R8-1 用户自带三反引号的代码还会被当纯文本"; fi

# R8-1b 视图和列表预计算共用同一个代码判据（只改一边=高度对不上）
if rg -qF 'static func hasCode(_ text: String) -> Bool' "$C" \
   && rg -qF '!UserMessageText.hasCode(text)' "$V3" \
   && ! rg -qF 'UserCodeFencing.autoFenced(text) == text' "$V3"; then
  ok R8-1b; else bad "R8-1b 预计算和视图的代码判据不一致"; fi

# R8-2 展开/收起保留旧高度当占位（删缓存会先画一帧错高度 = 那一跳）
if rg -qF 'func invalidateHeightKeepingPlaceholder' "$L" \
   && rg -qF 'layout.invalidateHeightKeepingPlaceholder(at: i)' "$V3"; then
  ok R8-2; else bad "R8-2 展开仍走删缓存路径"; fi

# R8-3 用户气泡展开按锚点回填 offset（被点那条原地不动）
if rg -qF 'let anchorScreenY = cv.cellForItem(at: ip)' "$V3" \
   && rg -qF 'cv.contentOffset.y = min(max(newY - anchorScreenY, minOff), maxOff)' "$V3"; then
  ok R8-3; else bad "R8-3 用户气泡展开没有锚点保持"; fi

# R8-4 滚动结算按顶部可见格子反推 offset（不再只放回数字）
if rg -qF 'let target = postY - screenY' "$V3" \
   && rg -qF 'cv.contentOffset.y = min(max(target, minOff), maxOff)' "$V3"; then
  ok R8-4; else bad "R8-4 settle 仍只恢复数字 offset"; fi

# R8-5 滚动中只放行视口下方的高度变化
if rg -qF 'if originalAttributes.frame.minY < viewportBottom,' "$L" \
   && ! rg -qF 'preferred <= original + 0.5' "$L"; then
  ok R8-5; else bad "R8-5 滚动中仍放行视口内增长"; fi

# R8-6 代码块折叠后失效 TextKit 布局，否则 sizeThatFits 还是旧高度
if rg -qF 'func refreshAttachmentBounds(for view: UIView)' "$S" \
   && rg -qF '.refreshAttachmentBounds(for: wrapper)' "$S"; then
  ok R8-6; else bad "R8-6 折叠后没有失效附件布局"; fi

echo "----"
if [ "$fail" -gt 0 ]; then echo "$fail FAILED"; exit 1; else echo "全部通过"; fi
