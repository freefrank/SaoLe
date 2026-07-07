import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/history_entry.dart';
import '../core/scan_result.dart';
import '../services/history_store.dart';
import '../services/settings_store.dart';
import '../services/platform/launcher.dart';
import 'result_sheet.dart';

/// 扫码主界面。scanOnly=true 时为快捷入口（磁贴/小组件）：处理完即退出，不进主壳。
class ScannerScreen extends StatefulWidget {
  final bool scanOnly;
  const ScannerScreen({super.key, this.scanOnly = false});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  final _parser = const ScanResultParser();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    _busy = true;
    await _handle(code);
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    _busy = true;
    try {
      final result = await _controller.analyzeImage(file.path);
      final code = result?.barcodes
          .map((b) => b.rawValue)
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      if (!mounted) return;
      if (code == null) {
        _toast('图片里没找到二维码');
        _busy = false;
        return;
      }
      await _handle(code); // 其 finally 会复位 _busy（非 scanOnly）
    } catch (_) {
      if (mounted) _toast('识别失败');
      _busy = false;
    }
  }

  Future<void> _handle(String raw) async {
    final settings = context.read<SettingsStore>();
    try {
      final result = _parser.parse(raw);
      if (settings.haptics) HapticFeedback.mediumImpact();
      if (settings.keepHistory) {
        await context
            .read<HistoryStore>()
            .add(HistoryEntry.fromScan(result, DateTime.now()));
      }

      // FIDO：无条件直开（认证要快）；唤不起则弹面板兜底，不静默失败。
      if (result is FidoResult) {
        final ok = await const Launcher().open(result.raw);
        if (!ok && mounted) await showResultSheet(context, result);
        return;
      }
      // 自动打开（默认关，防钓鱼）：仅 URL/AppLink；失败兜底面板。
      if (settings.autoOpen &&
          (result is UrlResult || result is AppLinkResult)) {
        final ok = await const Launcher().open(result.raw);
        if (!ok && mounted) await showResultSheet(context, result);
        return;
      }

      if (!mounted) return;
      await showResultSheet(context, result);
    } finally {
      _finishOrResume(settings);
    }
  }

  void _finishOrResume(SettingsStore settings) {
    if (widget.scanOnly) {
      SystemNavigator.pop();
      return;
    }
    _busy = false;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography, size: 48),
                  const SizedBox(height: 12),
                  const Text('无法访问相机', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('请在系统设置中授予相机权限，或改用相册识图。',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(
                      onPressed: _pickFromGallery, child: const Text('从相册识别')),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 12,
          child: Row(
            children: [
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) {
                  final on = state.torchState == TorchState.on;
                  return _RoundBtn(
                    icon: on ? Icons.flash_on : Icons.flash_off,
                    onTap: () => _controller.toggleTorch(),
                  );
                },
              ),
              const SizedBox(width: 8),
              _RoundBtn(icon: Icons.photo_library, onTap: _pickFromGallery),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: Colors.white)),
        ),
      );
}
