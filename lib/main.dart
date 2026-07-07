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
  final (mode, history, settings) = await (
    _launchMode(),
    HistoryStore.forApp(),
    SettingsStore.forApp(),
  ).wait;

  runApp(SaoLeApp(
    scanOnly: mode == 'scan_only',
    history: history,
    settings: settings,
  ));
}

Future<String> _launchMode() async {
  try {
    return await const MethodChannel('saole/launch')
            .invokeMethod<String>('getMode') ??
        'normal';
  } on PlatformException {
    return 'normal';
  } on MissingPluginException {
    return 'normal';
  }
}

class SaoLeApp extends StatelessWidget {
  final bool scanOnly;
  final HistoryStore history;
  final SettingsStore settings;
  const SaoLeApp({
    super.key,
    required this.scanOnly,
    required this.history,
    required this.settings,
  });

  ThemeMode _themeMode(SaoBrightness b) => switch (b) {
        SaoBrightness.system => ThemeMode.system,
        SaoBrightness.dark => ThemeMode.dark,
        SaoBrightness.light => ThemeMode.light,
      };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, s, _) => MaterialApp(
          title: '扫了',
          debugShowCheckedModeBanner: false,
          theme: buildSaoTheme(Brightness.light),
          darkTheme: buildSaoTheme(Brightness.dark),
          themeMode: _themeMode(s.brightness),
          home: scanOnly
              ? const Scaffold(body: ScannerScreen(scanOnly: true))
              : const HomeShell(),
        ),
      ),
    );
  }
}
