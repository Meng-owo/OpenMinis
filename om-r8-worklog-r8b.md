
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

---

## 当前状态交接（压缩上下文前落盘）

### 已完成并推送
- 分支 drawer-113，HEAD 含 R22–R33 全部提交
- 最新成功出包：run 40155500109（R33）→ `/var/minis/attachments/OpenMinis-一起听.ipa`
- 一起听六屏 + 播放引擎 + 悬浮小卡 + 状态层 + AI 工具面，代码全在
- `/var/minis/shared/together/test/acceptance.py` 41 项自检全绿（在 agent 沙盒里跑）

### 关键认知纠正（很重要）
- **agent 的 /var/minis 和她手机上 OpenMinis 的容器不是同一个沙盒。**
  我这边是另一个 App（嘟嘟）的沙盒，看不到她运行时的 state.json。
  所以：只有她 App 里 AI 跑出来的输出，才是我能看到的运行时事实。
  我这边 `/var/minis/shared/together/` 的曲库和 state 只是我的副本，不会随 IPA 发出去。

### 未解决的问题（按怀疑顺序）
1. **【最可能】曲库和 state 没随 IPA 打包。**
   我把歌种在自己沙盒的 /var/minis/shared/together/，但 IPA 里没有这些文件。
   她装上打开必然"还没有歌"。需要在 App 首次启动时自举：
   建目录 + 写一份默认 index.json（带 1-2 首随包资源）+ 默认 state.json。
2. **App 建目录没登记 fakefs meta.db。**
   TogetherStore.ensureDirectories 只 createDirectory，没调 FakefsBridge.registerParents，
   里面的 shell 可能看不到这些目录。目录已存在时也要补登记。
3. **首次启动的共享目录探测。**
   rootURL 用试写探针判断，但若 shared 根不存在会降级沙盒，
   降级后 AI 的 shell 就读不到 → 需要首次就把 /var/minis/shared/together 建好并登记。
4. 她反馈"我自己这边确实遇到问题了"，但**具体现象还没说**（空/有歌点不动/闪退）。
   等她一句话描述再定，不要猜着修。

### 她的偏好（延续，别丢）
- 不急、一步一步、质量优先；只验收最终成果，不要中间包
- 一个一个问题解决，不要一次全推
- 不贴长汇报；有问题直接修，不道歉不复盘
- 可见文案不写死人名，全走 ChatAddressing
- 颜色零裸色值，全走主题变量

### 【她实测反馈 · 2026-10-25】上传本地文件进不去
现象原文：可以选中文件，但是进不去。其他没测，因为没音乐所以无法播放、无法进入下一步。
影响：这是第一个卡点，挡住后面所有验证。
排查方向（未确认）：
- fileImporter 完成回调只 guard success，失败/空结果静默 return，没有报错提示
- security-scoped resource 取用与 async 拷贝的时序
- 目标目录未建/未登记 fakefs meta.db，copyItem 静默失败
- saveLibrary 写 index.json 的路径与 library() 读取路径是否一致
- 视频/非 mp3 走 AVAssetExportSession 失败后 fallback 是否真的成功

---

## R34 需求清单（她口述，2026-10-25）

1. **路径统一（最重要，不然两套系统打架）**：复用内置 `/var/minis/shared/music`，删自造路径。
2. **本地上传进不去**：`.fileImporter` 侧载失效 → 换 `DocumentCopyPicker`（asCopy）。
3. **悬浮球改输入栏上方微控条**：删悬浮球；38pt 条：迷你黑胶(转)+音波+歌词窗+上一首/播放/下一首。固定贴输入栏上方，不再自由拖。参考 `attachments/uploads/index.html`。
4. （并入 3）要有上一首。
5. **没歌词 → AI 写台词**：每首歌 AI 写一份"台词本"存 state，可互动/聊歌背景/感受；有词显词，无词轮播台词；AI 有工具随时改。
6. 先调研说计划不动手（已完成，她批准按最稳顺序做）。
7. **进度条/按钮偏高 → 往下调**。
8. **点唱片 → 翻成整页滚动歌词**：当前句高亮居中、点句跳转、再点翻回、过渡动画。
- 我自己补：微控条加细进度线；面板底部「添加/音量」灰按钮接上；歌词页显示歌名歌手+AI 写的背景。

### 根因（已查实）
- **两套音乐目录**：内置 `shared/music` = AppGroup/MinisFileProvider/shared/music（真 bind-mount，apple-player 认）；我的 `shared/together/music` = alpine-rootfs/data 下（靠 FakefsBridge 手登记 meta.db）。→ 统一到 `AIChatViewModel.minisSharedPersistentDir`（AppGroup 或 Application Support/OpenMinisClone 回退），这才是 bind-mount 真源，**不需要再登记 meta.db**。
- **曲库两套来源**：我读 index.json，目录有歌但 index 没登记就空库。→ 改成扫目录为准，index 当缓存。
- **上传**：`DocumentCopyPicker.swift` 注释已写明侧载 `.fileImporter` 选文件没反应。

### 开工顺序（她批准）：批次一 = 1+2+3 地基，出包确认；再批次二 = UI(3/4/7/8)；再批次三 = 5 AI 台词本 + 补全。
