#!/bin/sh
# [B28 round 6] 样张共享卡（气泡页+配色页）+ 摘掉假控件（禁用色板僵尸）。
cd "$(dirname "$0")/.." || exit 2
V=src/ios/Views/Settings/AppearanceStudioView.swift
fail=0
ok()  { printf 'OK   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }

# R6-1 liveSampleCard：一处定义，两处使用（气泡页、配色页）
if [ "$(rg -c 'liveSampleCard' "$V")" -ge 3 ]; then ok R6-1; else bad "R6-1 样张卡没做到两处共享"; fi

# R6-2 配色页真的挂了样张
if rg -A2 'private var palettePage' "$V" | rg -q liveSampleCard; then ok R6-2; else bad "R6-2 配色页没有样张"; fi

# R6-3 分类行的禁用 ColorPicker 摘干净（死字段不摆活控件）
if rg -q 'ColorPicker.*categoryColorBinding' "$V"; then bad "R6-3 假色板还挂着"; else ok R6-3; fi

# R6-4 新样张文案九语种
if python3 - "$V" <<'PY'
import json,sys
c=json.load(open('src/ios/Localizable.xcstrings',encoding='utf-8'))['strings']
want={"de","en","es","fr","ja","ko","ru","zh-Hans","zh-Hant"}
bad=[k for k in ["主文字看看我","次文字也看看我"] if want-set(c.get(k,{}).get('localizations',{}))]
print(bad); raise SystemExit(1 if bad else 0)
PY
then ok R6-4; else bad "R6-4 样张文案语种不齐"; fi

echo "----"
if [ "$fail" -gt 0 ]; then echo "$fail FAILED"; exit 1; else echo "全部通过"; fi
