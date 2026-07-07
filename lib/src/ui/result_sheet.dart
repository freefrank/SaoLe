import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/theme.dart';
import '../core/scan_result.dart';
import '../services/platform/launcher.dart';
import '../services/platform/wifi_connect.dart';

/// 弹出结果底部面板：按 [ScanResult] 类型给出对应动作。
/// FIDO 例外：不弹面板，直接唤起系统认证流程。
Future<void> showResultSheet(BuildContext context, ScanResult result) async {
  if (result is FidoResult) {
    await const Launcher().open(result.raw);
    return;
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _ResultSheet(result: result),
  );
}

class _ResultSheet extends StatelessWidget {
  final ScanResult result;
  const _ResultSheet({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_title(result), style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText(result.raw,
                maxLines: 4, style: TextStyle(color: t.text, fontSize: 16)),
            const SizedBox(height: 16),
            ..._actions(context, result),
          ],
        ),
      ),
    );
  }

  String _title(ScanResult r) => switch (r) {
        UrlResult() => '网址',
        AppLinkResult() => '应用链接',
        WifiResult() => 'WiFi 网络',
        TelResult() => '电话',
        EmailResult() => '邮箱',
        GeoResult() => '位置',
        FidoResult() => 'FIDO 安全密钥',
        TextResult() => '文本',
      };

  List<Widget> _actions(BuildContext context, ScanResult r) {
    switch (r) {
      case UrlResult():
        return [
          _Primary('打开', Icons.open_in_browser, () => _open(context, r.raw)),
          _Sub('复制', () => _copy(context, r.raw)),
          _Sub('分享', () => _share(r.raw)),
        ];
      case AppLinkResult():
        return [
          _Primary('打开应用', Icons.open_in_new,
              () => _open(context, r.raw, fallbackMsg: '没有应用能打开此链接')),
          _Sub('复制', () => _copy(context, r.raw)),
        ];
      case WifiResult():
        return [
          _Primary('一键连接', Icons.wifi, () => _connectWifi(context, r)),
          _Sub('复制密码', () => _copy(context, r.password)),
          _Sub('复制名称', () => _copy(context, r.ssid)),
        ];
      case TelResult():
        return [
          _Primary('拨号', Icons.call, () => _open(context, 'tel:${r.number}')),
          _Sub('复制', () => _copy(context, r.number)),
        ];
      case EmailResult():
        return [
          _Primary('写邮件', Icons.email, () => _open(context, 'mailto:${r.address}')),
          _Sub('复制', () => _copy(context, r.address)),
        ];
      case GeoResult():
        return [
          _Primary('打开地图', Icons.map, () => _open(context, r.raw)),
          _Sub('复制', () => _copy(context, r.raw)),
        ];
      case FidoResult():
        // 正常不会走到（showResultSheet 已对 FIDO 直开）；保留作 exhaustive 兜底。
        return [
          _Primary('打开', Icons.key, () => _open(context, r.raw)),
          _Sub('复制', () => _copy(context, r.raw)),
        ];
      case TextResult():
        return [
          if (r.embeddedUrl != null)
            _Primary('打开链接', Icons.open_in_browser,
                () => _open(context, r.embeddedUrl!)),
          _Primary('复制', Icons.copy, () => _copy(context, r.raw)),
          _Sub('分享', () => _share(r.raw)),
        ];
    }
  }

  Future<void> _open(BuildContext context, String url, {String? fallbackMsg}) async {
    final ok = await const Launcher().open(url);
    if (!context.mounted) return;
    if (!ok) {
      _snack(context, fallbackMsg ?? '无法打开');
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _connectWifi(BuildContext context, WifiResult r) async {
    await Clipboard.setData(ClipboardData(text: r.password));
    final ok = await const WifiConnect().connect(
      ssid: r.ssid, password: r.password, security: r.security, hidden: r.hidden,
    );
    if (!context.mounted) return;
    _snack(context, ok ? '密码已复制，在系统面板确认连接' : 'WiFi 面板不可用，密码已复制');
    Navigator.of(context).pop();
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    _snack(context, '已复制');
    Navigator.of(context).pop();
  }

  Future<void> _share(String text) => Share.share(text);

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Primary extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _Primary(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
      );
}

class _Sub extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Sub(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton(onPressed: onTap, child: Text(label)),
      );
}
