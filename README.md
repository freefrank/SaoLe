<div align="center">

<img src="assets/icon/icon.png" width="96" alt="SaoLe icon" />

# 扫了 (SaoLe)

**A minimal, ad-free, privacy-first QR & barcode scanner for Android.**

[![CI](https://github.com/freefrank/SaoLe/actions/workflows/ci.yml/badge.svg)](https://github.com/freefrank/SaoLe/actions/workflows/ci.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android)](https://developer.android.com)

English · [简体中文](README.zh.md)

</div>

---

The selling point isn't a secret algorithm — it's a **thin shell**: no ad SDKs, no
tracking, no bloated flows. That's why it feels instant. This project holds that
line from day one.

## Features

- **Scan & act** — decode QR/barcodes, classify the payload, and offer the right
  action. Recognized types: URL, app link, Wi-Fi, phone, email, geo, **FIDO**,
  and plain text (with embedded-URL extraction).
- **Single code, zero delay** — one code resolves instantly.
- **Multiple codes, tap to pick** — when several codes are in frame, the shot
  **freezes in place** and you tap the one you want, right on the frozen preview.
  A **"re-detect"** button re-runs static analysis to catch anything missed.
- **Zoom** — a vertical zoom slider that moves to the side you're tilting toward
  (thumb-friendly for either hand), plus pinch-to-zoom.
- **Lens picker** — a bottom bar lists the device's physical lenses
  (ultra-wide / main / telephoto); works with 1-, 2-, or 3-camera phones.
- **Torch** and **scan from gallery** image.
- **FIDO links open directly** for passkey / security-key flows.
- **Wi-Fi one-tap connect** via the system network panel (no location permission).
- **URL / app-link direct open**, with an opt-in "auto-open on scan" (off by
  default, anti-phishing).
- **History** — local JSON, newest first, tap to replay, swipe to delete, clear all.
- **Settings** — haptics, beep, keep history, continuous scan, light/dark/system.
- **Quick Settings tile** and **1×1 home-screen widget** — both launch straight
  into a scan-only mode that exits when done.
- **Privacy** — no ads, no analytics, no network access beyond launching what you
  scan.

## Architecture

Three layers, dependency-light:

```
lib/
  main.dart                 entry: reads scan_only intent, wires providers, MaterialApp
  src/
    app/       theme.dart (dark/light tokens) · responsive.dart
    core/      scan_result.dart (sealed types + ScanResultParser) · history_entry.dart
    services/  history_store.dart · settings_store.dart
      platform/  launcher.dart · wifi_connect.dart
    ui/        scanner_screen · qr_tap_picker · result_sheet · history · settings · home_shell
android/app/src/main/kotlin/pro/dotslash/saole/
  MainActivity · ScanTileService (QS tile) · ScanWidgetProvider (home widget)
```

- **State**: `provider` + `ChangeNotifier` (no riverpod — lighter, faster cold start).
- **Core** is pure Dart, zero Flutter deps — `ScanResultParser` is the one piece
  of real business logic and the focus of unit tests (malformed Wi-Fi strings,
  huge uint64 Steam IDs, non-Latin text, empty input — all must not crash).
- **Native** integration (tile, widget, Wi-Fi connect) is plain Android/Kotlin,
  no extra pub packages.

## Tech stack

Flutter 3.44 · Dart ^3.12 · Android 12+ (`minSdk 31`) · `mobile_scanner` ·
`provider` · `sensors_plus` · `path_provider` · `shared_preferences` ·
`url_launcher` · `share_plus` · `image_picker`.

## Build

```bash
flutter pub get
flutter test          # unit tests
flutter analyze       # lint gate

# per-architecture release APKs (arm64 is ~26 MB)
flutter build apk --split-per-abi --release
```

Output: `build/app/outputs/flutter-apk/app-<abi>-release.apk`.

### Release signing (optional)

Release builds fall back to the debug key unless you provide a keystore:

```bash
cp android/key.properties.example android/key.properties   # then fill in real values
# generate a keystore:
keytool -genkeypair -v -keystore android/saole-upload.jks \
  -alias saole -keyalg RSA -keysize 2048 -validity 10000
```

`key.properties` and `*.jks` are git-ignored — never commit them. For CI,
provide `KEYSTORE_BASE64` / `STORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS` as
repository secrets (see `.github/workflows/release.yml`).

## Download

Tagged releases (`v*`) trigger a GitHub Actions workflow that builds the
split-per-abi APKs and publishes them to the
[Releases](https://github.com/freefrank/SaoLe/releases) page.

## Not doing (by design)

OCR (architecture reserved, v2) · generating/sharing your own QR codes ·
iOS / desktop · cloud sync · batch export.

## License

TBD.
