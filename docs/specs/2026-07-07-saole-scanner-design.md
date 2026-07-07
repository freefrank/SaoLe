# 扫了 (SaoLe) — 极速扫码器设计

- **日期**: 2026-07-07
- **状态**: 设计已批准，待出实施计划
- **来源**: 从 AVA (AnotherVaporAuth) 抽出扫码功能，独立成 app

## 定位

Android 通用极速扫码器。卖点是**极简 + 零广告 + 冷启动快 + 隐私**——现有扫码
之所以跟手，不是独家算法，而是壳子薄（无广告 SDK、无埋点、无多余流程）。本项目
从一开始就守住这条，避免把壳子做重。

- 包名: `pro.dotslash.saole`
- 平台: 仅 Android（首版），minSdk 24
- 技术栈: Flutter 3.44.x / Dart ^3.12.2
- 路线: 全新 `flutter create` 项目 + 选择性借用 AVA 工程脚手架，业务代码全新写
- 签名: **独立新建 keystore**（与 AVA 的 `~/ava-upload.jks` 密钥隔离）

## MVP 功能清单

- 核心：开摄像头 → 识别 → `ScanResultParser` 判类型 → 结果面板给动作
- 手电筒
- 从相册图片识别（`mobile_scanner` analyzeImage）
- 扫码历史（本地 JSON 持久化）
- URL 直开 / App 链接直开（`url_launcher`，含“扫到即自动打开”开关）
- WiFi 扫码一键连接
- Quick Settings 磁贴（点击直接进 scan-only）
- 桌面小组件（点击直接进 scan-only；就一个“点击开扫”图标块）
- OCR：**架构预留，v2 实现**

## 分层与目录

```
core/        纯 Dart，零 Flutter 依赖，可单测
  scan_result.dart      ScanResult 密封类型 + ScanResultParser
  history_entry.dart    历史记录模型
  recognizer.dart       (v2 OCR 接口占位)
services/
  history_store.dart    ChangeNotifier + JSON 文件(path_provider)
  settings_store.dart   shared_preferences
  platform/
    wifi_connect.dart   → Kotlin platform channel，WiFi 一键连接
    launcher.dart       url_launcher 封装(URL / App 链接直开 + 唤起探测)
ui/
  scanner_screen.dart   MobileScanner + 手电筒/相册按钮 + 闩锁；支持 scanOnly 模式
  result_sheet.dart     按 ScanResult 类型给动作的底部面板
  history_screen.dart   历史列表
  settings_screen.dart  设置
android/  ScanTileService · ScanWidgetProvider(+layout) · WiFi channel(Kotlin)
```

**状态管理**: `ChangeNotifier` + `provider`。不引入 riverpod（对此体量过度，且更重
冷启动）。

## 数据流

相机帧 → `MobileScanner.onDetect`（`_done` 闩锁防每帧重复检测，继承 AVA
`_ScannerPage` 思路）→ 原始字符串 → `ScanResultParser.parse()` 得 `ScanResult`
→ 写入 `HistoryStore`（若开启记录）→ 弹 `result_sheet` 给动作。

若设置开启“扫到即自动打开”且类型为 `Url`/`AppLink`，跳过面板直接 `launcher` 唤起。

## 结果类型与动作（`ScanResultParser`）

全 app 唯一有分量的业务逻辑，纯函数，重点单测对象。

| 类型 | 识别规则 | 动作 |
|---|---|---|
| `Url` | http/https | 打开浏览器 · 复制 · 分享 |
| `AppLink` | 非 http 的自定义 scheme（如 `steam://`） | 唤起对应 app（唤不起→回退浏览器/提示）· 复制 |
| `Wifi` | `WIFI:S:…;T:…;P:…;` | **一键连接** · 复制密码 · 复制 SSID |
| `Tel` | `tel:` | 拨号 · 复制 |
| `Email` | `mailto:` | 写信 · 复制 |
| `Geo` | `geo:` | 打开地图 · 复制 |
| `Text` | 兜底 | 复制 · 分享 ·（若内含网址）提取并打开 |

解析健壮性要求：畸形 WiFi 串不崩、超长 uint64（Steam client_id 那类）不溢出、
非拉丁文本原样保留。

## 快速入口 · scanOnly 模式

桌面小组件（AppWidget 是 RemoteViews）**不能**跑实时相机预览。因此“从小组件直接
扫”的落地方式：

1. 小组件/磁贴点击 → `PendingIntent` / `startActivityAndCollapse` 拉起 MainActivity，
   带 intent extra `mode=scan_only`。
2. Flutter 启动即读该 extra，直入全屏 `scanner_screen`（scanOnly=true）。
3. 扫到 → 执行动作 → `SystemNavigator.pop()` 自动关闭，**不进主界面 shell**（无历史/
   设置底栏）。

普通启动（点桌面图标）→ 正常首屏（首屏即扫码，带底部历史/设置入口）。

- **磁贴** `ScanTileService`：manifest 注册，点击 `startActivityAndCollapse` 启动
  scan_only。
- **桌面小组件** `ScanWidgetProvider` + layout：单个“点击开扫”图标块（不显示上次结果），
  点击 `PendingIntent` 启动 scan_only。因无需向 widget 回传数据，**不引入
  `home_widget` 包**，纯原生 AppWidget 实现。

## 历史存储

`HistoryEntry{ content, type, timestamp }` → JSON 文件落 `path_provider` 应用目录。

- 列表倒序、点击复现动作、滑动删除、一键清空
- 设置可关“记录历史”（隐私）
- 不上 sqlite（历史量小，JSON 足够，省依赖省包体）
- 损坏文件读取要能优雅恢复（返回空历史，不崩）

## 设置（`shared_preferences`）

- 扫到即自动打开（默认**关**，防钓鱼）
- 震动反馈
- 提示音
- 记录历史
- 连续扫描模式

## Android 原生集成（无 pub 依赖）

- **磁贴** `ScanTileService`（API 24+）：`startActivityAndCollapse`。
- **桌面小组件** `ScanWidgetProvider`：点击 `PendingIntent` 启动 scan_only。
- **WiFi 连接** `wifi_connect` platform channel：
  - API 30+：系统 `Settings.ACTION_WIFI_ADD_NETWORKS` 面板，预填 SSID/密码，
    用户点确认（不需 fine location 权限）。
  - API < 30：回退到跳系统 WiFi 设置页 + 密码已复制到剪贴板。
  - 权限最小化。

## 错误处理

全部 toast / 面板级降级，绝不崩：

- 相机权限拒绝 → 引导页 + 跳系统设置入口
- 相册选图无码 → 提示
- App 链接唤不起 → 回退浏览器或 toast
- WiFi 系统面板不可用 → 回退复制密码

## 测试

- `ScanResultParser` 全类型单测：含畸形 WiFi 串、超长 uint64、非拉丁文本、空串
- `HistoryStore` 单测：读写往返、损坏文件恢复
- platform channel 用 mock 验证参数
- CI 门禁（照搬 AVA）：`flutter analyze` 零问题 + `flutter test` 全绿；push 前本地必过

## 借用的 AVA 脚手架

- `lib/src/app/theme.dart`（`AvaTokens` 主题扩展）
- `lib/src/app/responsive.dart`（`context.r()` 尺寸缩放）
- `lib/src/ui/widgets/scanline_overlay.dart`（扫描线动效）
- 签名配置模板（`android/key.properties` gitignore + build.gradle signingConfig 那套），
  但用**新建的独立 keystore**，不复用 `~/ava-upload.jks`
- CI 的 analyze/test 门禁

业务代码（scanner/parser/history/settings/native）全部全新编写。

## 仓库与同步

- WSL 正本 `~/SaoLe/`（构建性能）→ 镜像 `/mnt/c/Users/freefrank/ownCloud/Git/SaoLe/`
- rsync 同步流程照搬 AVA CLAUDE.md 的 `s` 约定（WSL 为唯一正本、`--delete`、排除
  `.git/`、`build/`、`.dart_tool/` 等）
- 新独立 git 仓库；本 spec 作为首个 commit

## 不做（v2 / 否决）

- OCR（架构预留，v2）
- 生成二维码 / 分享自己的 WiFi 码（v2）
- iOS / 桌面
- 云同步
- 批量扫描导出
