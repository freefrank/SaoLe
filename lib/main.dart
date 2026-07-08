import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'src/app/theme.dart';
import 'src/services/history_store.dart';
import 'src/services/settings_store.dart';
import 'src/ui/home_shell.dart';
import 'src/ui/scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 冷启动优化：launch mode 探测 + 两个 store 加载并行（Dart 3 record .wait）。
  // 顶层兜底：任一 Future 抛错也不白屏。
  String mode = 'normal';
  HistoryStore history;
  SettingsStore settings;
  try {
    final r = await (
      _launchMode(),
      HistoryStore.forApp(),
      SettingsStore.forApp(),
    ).wait;
    mode = r.$1;
    history = r.$2;
    settings = r.$3;
  } catch (_) {
    // 极端情况下（磁盘/权限）退化为可用的空态。
    history = HistoryStore(
      file: File('${Directory.systemTemp.path}/saole_history.json'),
    );
    settings = await SettingsStore.forApp();
  }

  runApp(
    SaoLeApp(
      initialScanOnly: mode == 'scan_only',
      history: history,
      settings: settings,
    ),
  );
}

Future<String> _launchMode() async {
  try {
    return await const MethodChannel(
          'saole/launch',
        ).invokeMethod<String>('getMode') ??
        'normal';
  } on PlatformException {
    return 'normal';
  } on MissingPluginException {
    return 'normal';
  }
}

class SaoLeApp extends StatefulWidget {
  final bool initialScanOnly;
  final HistoryStore history;
  final SettingsStore settings;
  const SaoLeApp({
    super.key,
    required this.initialScanOnly,
    required this.history,
    required this.settings,
  });

  @override
  State<SaoLeApp> createState() => _SaoLeAppState();
}

class _SaoLeAppState extends State<SaoLeApp> with WidgetsBindingObserver {
  late bool _scanOnly = widget.initialScanOnly;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 磁贴/小组件热启动时经 onNewIntent 更新原生 mode；回到前台重查并切换，
  // 避免 scan_only 不生效 / scanOnly UI 残留。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _launchMode().then((mode) {
        final scanOnly = mode == 'scan_only';
        if (mounted && scanOnly != _scanOnly) {
          setState(() => _scanOnly = scanOnly);
        }
      });
    }
  }

  ThemeMode _themeMode(SaoBrightness b) => switch (b) {
    SaoBrightness.system => ThemeMode.system,
    SaoBrightness.dark => ThemeMode.dark,
    SaoBrightness.light => ThemeMode.light,
  };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.history),
        ChangeNotifierProvider.value(value: widget.settings),
      ],
      // Material You：Android 12+ 跟随壁纸取色，取不到退回品牌蓝。
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) => Consumer<SettingsStore>(
          builder: (context, s, _) => MaterialApp(
            title: '扫了',
            debugShowCheckedModeBanner: false,
            theme: buildSaoTheme(Brightness.light, dynamicScheme: lightDynamic),
            darkTheme: buildSaoTheme(
              Brightness.dark,
              dynamicScheme: darkDynamic,
            ),
            themeMode: _themeMode(s.brightness),
            home: _scanOnly
                ? const Scaffold(body: ScannerScreen(scanOnly: true))
                : const HomeShell(),
          ),
        ),
      ),
    );
  }
}
