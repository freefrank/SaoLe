import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/settings_store.dart';

/// 设置界面：开关 + 亮度偏好。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('扫到即自动打开'),
            subtitle: const Text('仅网址/应用链接；默认关闭以防钓鱼'),
            value: s.autoOpen, onChanged: (v) => s.autoOpen = v,
          ),
          SwitchListTile(title: const Text('震动反馈'), value: s.haptics, onChanged: (v) => s.haptics = v),
          SwitchListTile(title: const Text('提示音'), value: s.beep, onChanged: (v) => s.beep = v),
          SwitchListTile(title: const Text('记录历史'), value: s.keepHistory, onChanged: (v) => s.keepHistory = v),
          SwitchListTile(
            title: const Text('连续扫描'),
            subtitle: const Text('处理完一个继续扫下一个'),
            value: s.continuous, onChanged: (v) => s.continuous = v,
          ),
          const Divider(),
          ListTile(
            title: const Text('外观'),
            trailing: DropdownButton<SaoBrightness>(
              value: s.brightness,
              onChanged: (v) => v == null ? null : s.brightness = v,
              items: const [
                DropdownMenuItem(value: SaoBrightness.system, child: Text('跟随系统')),
                DropdownMenuItem(value: SaoBrightness.dark, child: Text('深色')),
                DropdownMenuItem(value: SaoBrightness.light, child: Text('浅色')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
