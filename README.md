# EnglishLab

Mac / iPhone / iPad 沉浸式英语学习 App（方向 A · Phase 1–4 全部完成）。
一个界面完成：**导入素材 → 边听边看 → 点词查义 → 隐藏文本盲听 → 影子跟读 → 生词复习 → 学习统计**，无字幕素材可 **AI 一键生成**。
一个三栏界面完成：**导入素材 → 边听边看 → 点词查义 → 隐藏文本盲听 → 生词复习**。

依据上层目录的产品文档（`../EnglishLearningApp_MasterDoc.md`、`../Architecture_Design.md`、`../DictionaryModule_Design.md`）实现。

## 功能

| 模块 | 功能 |
|------|------|
| 播放列表（左栏） | 导入本地视频/音频（可多选、同名字幕自动配对）、进度显示、继续播放、右键关联字幕/重命名/删除 |
| 播放器（中栏） | 视频画面/音频封面、播放/暂停、±10s、拖动进度、0.5–2.0x 倍速、音量、**AB 单句循环**、进度自动保存 |
| 文本区（中栏） | SRT/LRC/VTT/TXT 字幕、当前句高亮+自动滚动、点句跳转、字号调节、**5 种隐藏模式**（正常/首字母/模糊/完全隐藏/单句隐藏，悬停 peek）、右键复制句子 |
| 单词详情（右栏） | **点词查义**（词形还原 went→go）、音标、释义、例句、近反义词（可点击继续查）、素材中含该词的例句（点击跳转）、发音（真人音频优先/TTS 兜底）、加入生词本 |
| 生词本（⌘B） | 状态筛选（未掌握/复习中/已掌握）、搜索、详情、发音、CSV 导出 |
| **影子跟读**（每句 🎙） | 播原句 → 录音（实时电平条）→ 本地语音识别 → **词级着色**（绿✓/红错/下划线漏读/灰多读）+ 正确率 → 原音 vs 我的录音对比 → 再练一次 |
| 跟读记录（工具栏 〰） | 历史会话列表、平均分、搜索、着色结果回放、删除（同步删录音文件） |
| **艾宾浩斯复习**（工具栏 🧠+到期徽章） | 到期词卡片流：先回忆→空格揭示答案→`1` 忘记 / `2` 记得；间隔 1/2/4/7/15/30 天递增，6 阶段全过=已掌握，忘记 10 分钟后重现 |
| 学习统计（工具栏 📊） | 今日/累计学习时长、点词/跟读/复习次数、平均分；近 7 天学习时长柱状图 + 词汇量增长曲线（Swift Charts） |
| 导出 | 生词本 → 导出菜单：CSV / **Anki TSV**（Anki「文件→导入」直接可用，含音标/释义/例句） |
| **AI 生成字幕**（右键素材 / 文本区 ✨） | Apple SpeechTranscriber 设备端转写（macOS 26+/iOS 26+，免费离线、不上传音频），自动带时间轴；首次自动下载语言模型；老系统降级提示手动导入 |
| 设置（⌘,） | 主题（浅色/深色/系统）、字幕字号、默认倍速、快捷键说明、数据来源署名 |

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

### 平台差异

| | macOS 14+ | iPadOS 17+ | iOS 17+ |
|---|---|---|---|
| 布局 | 三栏同屏 | 横屏三栏 / 竖屏可折叠 | 底部 Tab（素材/播放/单词） |
| 导入 | NSOpenPanel | fileImporter | fileImporter |
| 导出 | NSSavePanel | 系统分享 | 系统分享 |
| 设置 | ⌘, 独立窗口 | —（字号在文本区调节） | 同 iPad |
| AI 字幕 | macOS 26+ | iOS 26+ | iOS 26+（否则降级提示） |
| 快捷键 | 全支持 | 外接键盘支持 | 外接键盘支持 |

iOS 真机运行需开发者签名（Xcode 自动签名 + 免费账号即可）；iCloud 同步本轮未做（需付费账号 + iCloud container，见路线图）。

单元测试（不需要 Xcode 工程）：

```bash
swift test --package-path Packages/SubtitleKit     # 字幕解析 9 tests
swift test --package-path Packages/VocabularyKit   # 查词/还原/缓存 20 tests
swift test --package-path Packages/ShadowingKit    # 跟读对齐/评分 11 tests
swift test --package-path Packages/ReviewKit       # 艾宾浩斯调度 6 tests
```

自检钩子（验证模型+调度/转写集成，不碰用户数据）：

```bash
./build/Build/Products/Debug/EnglishLab.app/Contents/MacOS/EnglishLab --selftest-review
# 输出 SELFTEST REVIEW OK
./build/Build/Products/Debug/EnglishLab.app/Contents/MacOS/EnglishLab --selftest-transcribe "$PWD/Samples/learning_english.m4a"
# 输出 SELFTEST TRANSCRIBE OK: N segments
```

### 跟读权限（首次使用）

第一次点 🎙 会依次请求 **麦克风** 与 **语音识别** 权限，请允许。
识别优先在设备本地完成（SFSpeechRecognizer on-device）；录音仅存本机，不上传。
若误点拒绝：系统设置 → 隐私与安全性 → 麦克风 / 语音识别 中勾选 EnglishLab。

## 示例素材

```bash
bash scripts/make_sample.sh   # 需要 ffmpeg；用 macOS say 合成
```

产出 `Samples/learning_english.m4a` + `learning_english.srt`（47 秒，10 句，逐句精确时间轴）。
在 App 中点 `+` 同时选中这两个文件导入即可体验完整流程。

## 快捷键

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

注：焦点在列表/输入框时部分按键可能被系统控件占用。

## 架构

```
EnglishLab/
├── project.yml               # xcodegen 工程定义
├── App/                      # 主 App（SwiftUI + SwiftData）
│   ├── Models/               # MediaItem/Playlist/SubtitleLine/WordRecord
│   ├── Services/             # PlayerManager/MediaStore/VocabularyManager/SpeechService
│   └── Views/                # 三栏 UI + 生词本 + 设置
└── Packages/
    ├── SubtitleKit/          # SRT/LRC/VTT/TXT 解析器（独立可测）
    ├── VocabularyKit/        # 查词模块（独立可测）
    │   ├── FreeDictionaryService   # dictionaryapi.dev
    │   ├── DatamuseService         # 近反义词
    │   ├── DiskDictionaryCache     # 30 天磁盘缓存
    │   ├── RuleBasedWordNormalizer # 词形还原候选
    │   └── DefaultVocabularyRepository
    ├── ShadowingKit/         # 跟读评估（独立可测）
    │   ├── TextAligner             # 标准化 + Levenshtein 词级对齐 + 正确率
    │   └── ScoredWord/ShadowingResult
    └── ReviewKit/            # 艾宾浩斯复习调度（独立可测）
        └── EbbinghausScheduler     # 阶段间隔/忘记重置/掌握判定
```

统计链路：`StatsTracker`（按天聚合 `DayStat`）← 播放时长（PlayerManager，seek 不计）/点词/跟读/加词/复习埋点；统计页用 Swift Charts 展示。

跟读链路（App/Services）：`ShadowingManager`（状态机）→ `AudioRecorderService`（m4a+电平）→ `SpeechRecognitionService`（on-device 优先）→ `TextAligner.assess` → 面板着色；会话存 SwiftData `ShadowingSession`，录音存 `Application Support/EnglishLab/Recordings`。

- 导入的文件拷贝到 `Application Support/EnglishLab/Media`（沙盒内，无需安全作用域书签）
- 查询缓存：`Caches/EnglishLab/Dictionary`
- 所有数据本地存储，不上传（隐私优先）

## 数据来源与授权

- 词典：[dictionaryapi.dev](https://dictionaryapi.dev)（Wiktionary，CC BY-SA 3.0）
- 近反义词：[Datamuse API](https://www.datamuse.com/api/)
- 发音：Wiktionary 音频，兜底 AVSpeechSynthesizer

## 路线图

- ~~Phase 2：影子跟读~~ ✅（词级评分；音素级 Azure 评估、波形对比留待进阶）
- ~~Phase 3：艾宾浩斯复习、学习统计、Anki 导出~~ ✅
- ~~Phase 4：AI 字幕生成、iOS/iPadOS 适配~~ ✅（用 Apple SpeechTranscriber 替代 Whisper，免部署/免费/离线）
- 待做：iCloud 同步（需付费开发者账号）、播放列表分组 UI、离线词库、Azure 音素级发音评估
