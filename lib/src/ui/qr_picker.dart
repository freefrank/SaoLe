import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/scan_result.dart';

/// 一次检测到多个二维码时，让用户选一个。返回选中的原始串；取消返回 null。
Future<String?> showQrPickerSheet(BuildContext context, List<String> codes) {
  const parser = ScanResultParser();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final t = context.tokens;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('检测到 ${codes.length} 个码，选一个',
                    style: TextStyle(color: t.muted, fontSize: 13)),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: codes.length,
                itemBuilder: (context, i) {
                  final code = codes[i];
                  final r = parser.parse(code);
                  return ListTile(
                    leading: Icon(_iconFor(r)),
                    title: Text(_labelFor(r)),
                    subtitle: Text(code,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, code),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

IconData _iconFor(ScanResult r) => switch (r) {
      UrlResult() => Icons.link,
      AppLinkResult() => Icons.open_in_new,
      WifiResult() => Icons.wifi,
      TelResult() => Icons.call,
      EmailResult() => Icons.email,
      GeoResult() => Icons.map,
      FidoResult() => Icons.key,
      TextResult() => Icons.notes,
    };

String _labelFor(ScanResult r) => switch (r) {
      UrlResult() => '网址',
      AppLinkResult() => '应用链接',
      WifiResult() => 'WiFi 网络',
      TelResult() => '电话',
      EmailResult() => '邮箱',
      GeoResult() => '位置',
      FidoResult() => 'FIDO 安全密钥',
      TextResult() => '文本',
    };
