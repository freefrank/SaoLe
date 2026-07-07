import 'package:flutter/material.dart';

import 'history_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

/// 普通启动首屏：首屏即扫码，底部切历史/设置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_index) {
        0 => const ScannerScreen(),
        1 => const HistoryScreen(),
        _ => const SettingsScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: '扫码'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
