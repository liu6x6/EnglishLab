# EnglishLab

Mac / iPhone / iPad 沉浸式英语学习 App。
一个界面完成：**导入素材 → 边听边看 → 点词查义 → 隐藏文本盲听 → 影子跟读 → 生词复习 → 学习统计**，无字幕素材可 **AI 一键生成**（双引擎）。

依据上层目录的产品文档（`../EnglishLearningApp_MasterDoc.md`、`../Architecture_Design.md`、`../DictionaryModule_Design.md`、`../ShadowingModule_Design.md`）实现。

## 功能

| 模块 | 功能 |
|------|------|
| 素材管理 | 本地视频/音频导入（多选、同名字幕自动配对）、**拖拽文件到窗口自动导入**、自建播放列表分组、素材搜索、进度显示、**启动自动恢复上次素材**、右键/长按：AI 字幕/关联字幕/重命名/删除 |
| 播放器 | **视频居中显示、画面大小可调（50–100%）**、播放/暂停、±10s、拖动进度、0.5–2.0x 倍速、音量、**单句播放（播完自动停）**、**AB 单句循环**、进度自动保存 |
| 文本区 | SRT/LRC/VTT/TXT 字幕、当前句高亮+自动滚动、点句单句播放/点时间戳跳转、字号调节、**5 种隐藏模式**（正常/首字母/模糊/完全隐藏/单句隐藏，悬停 peek，隐藏状态持久化）、右键复制句子 |
| 查词 | **点词查义**（词形还原 went→go）、**中文释义优先**（ECDICT）、**断网离线可查**（2.6 万常用词内嵌）、**词组查询**、音标、英文释义、例句、近反义词（可点击继续查）、素材例句跳转、发音（真人音频优先/TTS 兜底，音频本地缓存）、**查词历史**、加入生词本 |
| 影子跟读 | 每句 🎙：播原句 → 录音（实时电平条）→ 本地识别 → **词级着色**（绿✓/红错/下划线漏读/灰多读）+ 正确率 → 原音 vs 我的录音对比 → 再练一次；**红词点击单独重练**（TTS 示范→录音→单词评分→返回整句） |
| 生词本 | 状态筛选（未掌握/复习中/已掌握）、搜索、详情、发音、**批量加词**（粘贴文本→提取候选→勾选入库）、CSV / **Anki TSV** 导出 |
| 艾宾浩斯复习 | 到期词卡片流：先回忆→揭示答案→忘记/记得；间隔 1/2/4/7/15/30 天递增，6 阶段全过=已掌握，忘记 10 分钟后重现；到期红色徽章 |
| 学习统计 | 今日/累计学习时长、点词/跟读/复习次数、跟读平均分；近 7 天学习时长柱状图 + 词汇量增长曲线（Swift Charts） |
| 跟读记录 | 历史会话列表、平均分、搜索、着色结果回放、删除（同步删录音文件） |
| **AI 生成字幕** | **双引擎**：Apple SpeechTranscriber（macOS 26+/iOS 26+，系统级极快）+ **whisper.cpp**（macOS 14+/iOS 17+，Metal/Accelerate 加速，实测 47 倍实时）；自动路由：<26 用 whisper，≥26 默认 Apple；设置→转写可切换引擎、下载/选择模型（tiny.en~medium.en/large-v3-turbo）；完全设备端、不上传音频 |
| iOS 后台播放 | 退后台/锁屏继续听；锁屏/控制中心显示进度；耳机线控播放/暂停/±10s/拖动 |

## 平台差异

| | macOS 14+ | iPadOS 17+ | iPhone（iOS 17+） |
|---|---|---|---|
| 布局 | 三栏同屏 | 横屏三栏 / 竖屏可折叠 | 底部 5 Tab：素材/播放/单词/**学习**/**设置** |
| 学习工具 | 工具栏（复习/生词本/统计/跟读记录） | 工具栏 | **「学习」Tab** 整合四入口 |
| 设置 | ⌘, 独立窗口（通用/快捷键/转写/关于） | 工具栏齿轮 → 面板 | 底部 Tab，顶部 segment（通用/转写） |
| 导入 | NSOpenPanel + 拖拽 | 原生文档选择器 + 拖拽 | 原生文档选择器 + 拖拽 |
| 导出 | NSSavePanel | 系统分享 | 系统分享 |
| 句子操作按钮 | 悬停显示 | 悬停/常驻 | 常驻（▶️ 单句 / 🎙 跟读 / 🔁 循环） |
| AI 字幕 | macOS 26+ Apple，否则 whisper | iOS 26+ Apple，否则 whisper | 同 iPad |
| 快捷键 | 全支持 | 外接键盘 | 外接键盘 |

iOS 真机运行需开发者签名（Xcode 自动签名 + 免费账号即可）。

## 构建与运行

依赖：Xcode 26+（含 iOS SDK）、[xcodegen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen        # 如未安装
cd EnglishLab
xcodegen generate
open EnglishLab.xcodeproj    # Xcode 选 EnglishLab（Mac）或 EnglishLab-iOS（模拟器/真机）⌘R
```

命令行构建（双平台）：

```bash
xcodegen generate
# macOS
xcodebuild -project EnglishLab.xcodeproj -scheme EnglishLab -configuration Debug build
# iOS 模拟器
xcodebuild -project EnglishLab.xcodeproj -scheme EnglishLab-iOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

### 单元测试（57 个，不需要 Xcode 工程）

```bash
swift test --package-path Packages/SubtitleKit     # 字幕解析 9
swift test --package-path Packages/VocabularyKit   # 查词/还原/缓存/离线词典/词组 31
swift test --package-path Packages/ShadowingKit    # 跟读对齐/评分 11
swift test --package-path Packages/ReviewKit       # 艾宾浩斯调度 6
```

### 集成自检钩子（不碰用户数据）

```bash
BIN=./build/Build/Products/Debug/EnglishLab.app/Contents/MacOS/EnglishLab
$BIN --selftest-review                                          # 复习模型+调度
$BIN --selftest-dict                                            # 内嵌离线词典
$BIN --selftest-audio "<发音URL>"                                # 发音下载缓存
$BIN --selftest-transcribe "$PWD/Samples/learning_english.m4a"  # Apple 转写（需 26+）
$BIN --selftest-whisper "$PWD/Samples/learning_english.m4a" base.en  # whisper 转写（需已下载模型）
```

### Whisper 模型与 xcframework

- 模型按需下载（设置→转写）：hf-mirror 快速通道，存 `Application Support/EnglishLab/WhisperModels`
- `whisper.xcframework` 已预构建并提交（macOS arm64 / iOS 真机 arm64 / 模拟器 arm64+x86_64），重新构建：

```bash
python3 scripts/fetch_whisper_src.py        # GitHub API 清单 + jsDelivr 并发拉源码
bash scripts/build_whisper_xcframework.sh   # cmake 静态构建 + xcframework（需 cmake）
```

- 模拟器上 whisper 自动用 CPU（NEON）：模拟器 Metal 驱动大缓冲区有 XPC 限制；真机/Mac 用 Metal GPU

### 离线词典数据

内嵌 `ecdict.sqlite`（26,484 常用词，6.2MB，考试词汇+高频词过滤）。重新构建：

```bash
bash scripts/make_ecdict.sh   # hf-mirror 快速下载全量 77 万词 → 过滤 → 6MB sqlite
```

### 跟读权限（首次使用）

第一次点 🎙 会依次请求 **麦克风** 与 **语音识别** 权限，请允许。
识别优先在设备本地完成（SFSpeechRecognizer on-device）；录音仅存本机，不上传。
若误点拒绝：系统设置 → 隐私与安全性 → 麦克风 / 语音识别 中勾选 EnglishLab。

## 示例素材

仓库自带 `Samples/learning_english.m4a` + `.srt`（47 秒，10 句，逐句精确时间轴）。
重新生成：`bash scripts/make_sample.sh`（需 ffmpeg，用 macOS say 合成）。
App 中点 `+` 同时选中两个文件导入，或直接拖入窗口。

## 快捷键（macOS / 外接键盘）

| 键 | 功能 |
|----|------|
| 空格 | 播放/暂停 |
| ← / → | 快退/快进 10 秒 |
| ↑ / ↓ | 音量 ± |
| [ / ] | 减速/加速 |
| L | 当前句单句循环 |
| H | 循环切换文本隐藏模式 |
| ⌘B | 生词本 |
| ⌘, | 设置 |

采用原生焦点系统（`.onKeyPress`）：**输入框/列表聚焦时按键自动让路**，不会误触发；隐藏模式全局记忆。

## 架构

```
EnglishLab/
├── project.yml               # xcodegen 工程定义（macOS + iOS 双 target）
├── App/                      # 主 App（SwiftUI + SwiftData，条件编译跨平台）
│   ├── Models/               # MediaItem/Playlist/SubtitleLine/WordRecord/ShadowingSession/DayStat/LookupHistory
│   ├── Services/             # PlayerManager/MediaStore/MediaImporter/VocabularyManager/
│   │                         # ShadowingManager/AudioRecorder/SpeechRecognition/TranscriptionManager/
│   │                         # WhisperModelManager/AudioCache/StatsTracker/NowPlaying(iOS)
│   └── Views/                # 三栏(mac/iPad) + 5 Tab(iPhone) + 各功能面板 + PlatformHelpers
└── Packages/
    ├── SubtitleKit/          # SRT/LRC/VTT/TXT 解析器
    ├── VocabularyKit/        # 查词：FreeDictionary + Datamuse + 磁盘缓存 + 词形还原 + ECDICT 离线
    ├── ShadowingKit/         # 跟读：标准化 + Levenshtein 词级对齐 + 评分
    ├── ReviewKit/            # 艾宾浩斯复习调度
    └── WhisperCpp/           # whisper.xcframework（预构建）+ Swift 转写封装
```

关键数据流：
- **查词**：缓存 → 在线（FreeDictionary+Datamuse）+ ECDICT 中文合并 → 断网/未收录时 ECDICT 离线兜底
- **跟读**：ShadowingManager 状态机 → 录音 → SFSpeechRecognizer → TextAligner 词级对齐 → 着色面板；会话存 SwiftData
- **AI 字幕**：TranscriptionManager 引擎路由 → Apple SpeechTranscriber / whisper.cpp → 时间轴字幕入库
- **统计**：StatsTracker 按天聚合（播放时长/点词/跟读/加词/复习）→ Swift Charts

存储（全部本地，隐私优先）：
- 媒体：`Application Support/EnglishLab/Media`（导入拷贝进沙盒）
- 录音：`Application Support/EnglishLab/Recordings`
- Whisper 模型：`Application Support/EnglishLab/WhisperModels`
- 查询缓存：`Caches/EnglishLab/Dictionary`（30 天）；发音缓存：`Caches/EnglishLab/Audio`

## 数据来源与授权

- 词典：[dictionaryapi.dev](https://dictionaryapi.dev)（Wiktionary，CC BY-SA 3.0）
- 离线英汉词典：[ECDICT](https://github.com/skywind3000/ecdict)（MIT，内嵌精简版）
- 语音转写：Apple SpeechTranscriber（系统）+ [whisper.cpp](https://github.com/ggml-org/whisper.cpp)（MIT），模型来自 [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp)
- 近反义词：[Datamuse API](https://www.datamuse.com/api/)
- 发音：Wiktionary 音频，兜底 AVSpeechSynthesizer

## 路线图

已完成：Phase 1 精学 MVP · Phase 2 影子跟读 · Phase 3 复习/统计/导出 · Phase 4 AI 字幕+iOS 适配 · whisper.cpp 双引擎 · 体验打磨（启动恢复/快捷键门控/查词历史/批量加词/红词重练/发音缓存等）

待做：
- iCloud 同步（需付费开发者账号 + iCloud container）
- 播放列表拖拽排序
- Azure 音素级发音评估、波形对比
- whisper 词级时间戳（卡拉OK式高亮）、模型下载断点续传
- App 图标接入工程（SVG 已备：`designs/app-icon.svg`）
