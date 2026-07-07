<div align="center">

<img src="assets/icon/icon.png" width="96" alt="扫了 图标" />

# 扫了 (SaoLe)

**极简、零广告、隐私优先的 Android 扫码器。**

[![CI](https://github.com/freefrank/SaoLe/actions/workflows/ci.yml/badge.svg)](https://github.com/freefrank/SaoLe/actions/workflows/ci.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android)](https://developer.android.com)

[English](README.md) · 简体中文

</div>

---

卖点不是什么独家算法，而是**壳子薄**——没有广告 SDK、没有埋点、没有多余流程，
所以才跟手。本项目从第一天就守住这条线。

## 功能

- **扫码即动作** —— 识别二维码/条码，判断内容类型，给出对应动作。支持类型：
  网址、应用链接、WiFi、电话、邮箱、位置、**FIDO**，以及兜底文本（含内嵌网址提取）。
- **单码零延迟** —— 只有一个码时即时出结果。
- **多码原地点选** —— 画面里有多个码时，**当前画面原地冻结**，你直接在定格画面上
  点选要用的那个。带**"再次深度检测"**按钮，重跑静态分析补全漏检的码。
- **变焦** —— 竖直变焦滑块会随手机倾斜切到就近一侧（左右手都顺手），支持双指捏合。
- **镜头选择** —— 底部列出设备的物理镜头（超广角 / 主摄 / 长焦），兼容单摄、双摄、三摄。
- **手电筒** 与 **相册识图**。
- **FIDO 链接直接打开**，走系统 passkey / 安全密钥流程。
- **WiFi 一键连接** —— 通过系统网络面板预填（无需定位权限）。
- **网址 / 应用链接直开**，可选"扫到即自动打开"（默认关闭，防钓鱼）。
- **历史** —— 本地 JSON，倒序，点击复现动作，滑动删除，一键清空。
- **设置** —— 震动、提示音、记录历史、连续扫描、深色/浅色/跟随系统。
- **Quick Settings 磁贴** 与 **1×1 桌面小组件** —— 都直接进入扫码模式，扫完即退出。
- **隐私** —— 无广告、无埋点，除了打开你扫到的内容外不联网。

## 架构

三层，依赖精简：

```
lib/
  main.dart                 入口：读 scan_only intent、装配 provider、MaterialApp
  src/
    app/       theme.dart（明暗令牌）· responsive.dart
    core/      scan_result.dart（密封类型 + ScanResultParser）· history_entry.dart
    services/  history_store.dart · settings_store.dart
      platform/  launcher.dart · wifi_connect.dart
    ui/        scanner_screen · qr_tap_picker · result_sheet · history · settings · home_shell
android/app/src/main/kotlin/pro/dotslash/saole/
  MainActivity · ScanTileService（磁贴）· ScanWidgetProvider（桌面小组件）
```

- **状态**：`provider` + `ChangeNotifier`（不用 riverpod，更轻、冷启动更快）。
- **core** 纯 Dart、零 Flutter 依赖 —— `ScanResultParser` 是唯一有分量的业务逻辑，
  也是单测重点（畸形 WiFi 串、超长 uint64 的 Steam ID、非拉丁文本、空串都不能崩）。
- **原生** 集成（磁贴、小组件、WiFi 连接）纯 Android/Kotlin，无额外 pub 依赖。

## 技术栈

Flutter 3.44 · Dart ^3.12 · Android 12+（`minSdk 31`）· `mobile_scanner` ·
`provider` · `sensors_plus` · `path_provider` · `shared_preferences` ·
`url_launcher` · `share_plus` · `image_picker`。

## 构建

```bash
flutter pub get
flutter test          # 单元测试
flutter analyze       # 静态检查门禁

# 按架构拆分的 release APK（arm64 约 26 MB）
flutter build apk --split-per-abi --release
```

产物：`build/app/outputs/flutter-apk/app-<abi>-release.apk`。

### Release 签名（可选）

不提供 keystore 时，release 会回退到 debug 签名：

```bash
cp android/key.properties.example android/key.properties   # 再填入真实值
# 生成 keystore：
keytool -genkeypair -v -keystore android/saole-upload.jks \
  -alias saole -keyalg RSA -keysize 2048 -validity 10000
```

`key.properties` 与 `*.jks` 已被 git 忽略 —— 切勿提交。CI 里在仓库 Secrets 配
`KEYSTORE_BASE64` / `STORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS`
（见 `.github/workflows/release.yml`）。

## 下载

打 `v*` tag 会触发 GitHub Actions，构建各架构 APK 并发布到
[Releases](https://github.com/freefrank/SaoLe/releases) 页。

## 不做（有意为之）

OCR（架构预留，v2）· 生成/分享自己的二维码 · iOS / 桌面 · 云同步 · 批量导出。

## 许可证

待定。
