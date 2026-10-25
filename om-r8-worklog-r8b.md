
## R22 媒体库内容去重（a5acf77）

来源：醒醒截图，播放页一张头像列出了十几张一模一样的图。
根因：换头像每写一次就留一个新 UUID 文件，历史压缩版也没删，扫描只按路径去重。
做法：`PlayHubView` 新增 `dedupeByContent` / `fingerprint` / `preferred` / `isUUIDLike`。
先按 size 分组，只有同 size 才读前 64KB 做 FNV-1a，600 张里实际读盘的是少数。
组内保留 `/uploads/` 原件，其次非 UUID 文件名的。
只改显示层；磁盘上的旧副本没动（清理要改数据库引用，等醒醒点头）。

## R23 一起听地基（5516d40）

TASK.md 七步流程，0-2 步已过：复述任务、缺信息一次问全、计划贴出。
数据源定案：AI 上网找歌+歌词，或醒醒上传（无词则补），增删改都落本地，不绑别的 App，留 `MusicImporter` 口子。

状态层先用 Python 跑通再搬 Swift：
- `/var/minis/shared/together/together.py`：flock + 原子写 + revision，命令 status/get/set/play/pause/resume/seek/note/mood/reply/radio/events/history
- `/var/minis/shared/together/test/state.py`：14 项自检全绿
  - 并发写入改用 25 批 ×4 进程：iSH 4GB 扛不住 100 个 python 同时起（MemoryError），不是锁失效
  - 坏文件恢复补 `_recover`：备份完立刻落默认值，不留"文件不存在"的窗口

Swift 侧（`src/ios/Agent/Together/`）：
- `TogetherState.swift`：模型逐字段对齐 state.json，全部 `decodeIfPresent` + 默认值，单字段坏不拖垮整份
- `TogetherStore.swift`：`hostPath(forGuestPath:)` 做 guest→host 映射，共享目录不可写降级沙盒并记日志；
  `mutate(by:event:detail:)` 统一 revision+1、事件追加、帧数封顶；场景动作 play/seek/like/note/radio/mood/speak
  speak 三句封顶在写盘前判
- 自审修三处：`FileHandle(forUpdating: fd)` 是错 API → 直接 fd + flock；fsync 漏 fd → 用 `Data.write(.atomic)`；
  speak 第四句仍落空事件 → 先判再写

CI：`build-ios-ipa.yml` dispatch ref=drawer-113，验证编译。

## R24-R33 一起听（Together）

TASK.md 七步走完：意图复述 → 缺信息一次问全 → 计划 → 调研 → 审计 → 动手 → 复审。
数据源定案：AI 上网找歌+歌词 / 醒醒上传（无词则补），增删改全落本地，
不绑别的 App，留 `MusicImporter` 协议做口子。

### 状态层（R23 起，Python 跑通再搬 Swift）
- `/var/minis/shared/together/together.py`：flock + 原子写 + revision，命令
  status/now/get/set/play/pause/resume/seek/note/mood/reply/radio/handoff/playlist/lib/skin/events/history/loopline
- `test/state.py`：14 项全绿（并发 100 次不丢、坏文件备份+重建、事件封顶 500、revision 单调）
- Swift `TogetherState.swift`：模型逐字段对齐 state.json，全 decodeIfPresent + 默认值
- Swift `TogetherStore.swift`：flock + 原子写，`mutate` 统一 revision/事件/封顶；场景动作 play/seek/like/note/radio/mood/speak/playlist

### 路径（踩过的坑）
- `/var/minis` 在 App 侧 = `Documents/alpine-rootfs/data/var/minis`（由 mount 输出实证）
- 第一版：探测不到共享根就缩回沙盒 → 面板一直"还没有歌"。改成建目录 + 试写探针才判定
- 写共享目录要走 `FakefsBridge` 登记 `alpine-rootfs/meta.db` 的 paths/stats，
  否则 iSH 侧看不见 App 写的 state（SkillStore 里 ensureFakefsMetadata 同一件事）
- `rootDecision` 两处判定比的中文字符串还不一样 → 收成 `isSharedRoot` 布尔

### 音频（R24）
- `TogetherPlayer.swift`：独立 AVPlayer 引擎，不复用语音气泡那套
- 后台靠 AudioSessionCoordinator + Info.plist audio mode（已有）
- `VoiceNowPlaying` 加一起听分支并优先：音乐长播，锁屏该显示歌名不被语音消息顶掉

### 界面（R25-R29）
- `TogetherPanelView`：播放页照 reference.html 01 屏，双人头像 104、五键控制、底部四功能
- `TogetherRootView`：底部标签栏串 在听/歌单/一起/喜欢
- `TogetherScreens`：歌单库 / 歌单详情 / 我喜欢的音乐 / 一起听 / 编辑面板 / 加歌
- `TogetherMiniBar`：悬浮小卡 250x72，贴边收起成 12pt 竖条
- `TogetherSkin`：皮肤层（唱片深浅/纹路/圆角/阴影）+ `TogetherCopy` 文案层 + `TogetherIdentity` 头像单一取法

### 共感与工具（R28/R30）
- 事件流：她的每次切歌/拖动/喜欢都落一条，我读得到
- `me.presence`：我在不在、什么心情、想不想说话
- `me.history`：我推过的歌+理由，下一回合读得到
- `reply` 一天三句封顶（写盘前判，超了不落空事件）
- `now` 命令给的是判断不是字段表
- `soulEditHint` 补 TOGETHER 段，全部参数核对过

### 自审修的真问题
- R25b：Swift 字符串 `\/` 非法转义
- R25c：`ChatFont.font(size:)` 参数无标签，20 处报错；唱片五层叠加 type-check 超时 → 拆 `TogetherDiscView`
- R25d：`TogetherSkin` 取值入口是 @MainActor，跟着标
- R27：`TogetherTrack` 补 Identifiable；`TogetherCover` 标 @MainActor
- R29b：`TogetherPlaylist` 不是 Hashable，导航改 `NavigationLink(value:)`
- R32：跟随比 revision 会被进度回写反复触发 → 改比事件 id；冷启动无条件 play → 尊重 state 的暂停
- R33：`restoreIfNeeded` 冷启动接着放

### 曲库
真歌三首（archive.org 公有领域 / CC 授权，含来源标注）：
Gymnopédie No.1、Frogs Legs Rag、Danny Boy。
无词的两首用 `loopLines` 循环一句我写的话。
`together-fetch.py`：import（视频抽音轨）/ lyrics（lrclib 带时间轴）/ search / list。
抓不到歌词就留空，不编。
