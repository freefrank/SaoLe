import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/settings_store.dart';

/// 设置界面：开关 + 亮度偏好 + 版本信息。
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
            subtitle: const Text('仅 http/https 网址；默认关闭以防钓鱼'),
            value: s.autoOpen,
            onChanged: (v) => s.autoOpen = v,
          ),
          SwitchListTile(
            title: const Text('震动反馈'),
            value: s.haptics,
            onChanged: (v) => s.haptics = v,
          ),
          SwitchListTile(
            title: const Text('提示音'),
            value: s.beep,
            onChanged: (v) => s.beep = v,
          ),
          SwitchListTile(
            title: const Text('记录历史'),
            value: s.keepHistory,
            onChanged: (v) => s.keepHistory = v,
          ),
          SwitchListTile(
            title: const Text('连续扫描'),
            subtitle: const Text('扫到即记入历史并继续，不弹结果面板'),
            value: s.continuous,
            onChanged: (v) => s.continuous = v,
          ),
          const Divider(),
          const ListTile(title: Text('外观')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            // M3 惯用分段按钮：三个选项一目了然，少一次展开点击。
            child: SegmentedButton<SaoBrightness>(
              segments: const [
                ButtonSegment(
                  value: SaoBrightness.system,
                  label: Text('跟随系统'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: SaoBrightness.light,
                  label: Text('浅色'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: SaoBrightness.dark,
                  label: Text('深色'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {s.brightness},
              onSelectionChanged: (v) => s.brightness = v.first,
            ),
          ),
          const Divider(),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => ListTile(
              title: const Text('版本'),
              trailing: Text(
                snap.hasData
                    ? '${snap.data!.version} (${snap.data!.buildNumber})'
                    : '',
                style: TextStyle(color: context.tokens.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
