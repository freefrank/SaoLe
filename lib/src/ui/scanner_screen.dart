import 'dart:async';
import 'dart:io';

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
import 'qr_tap_picker.dart';
import 'result_sheet.dart';

/// 扫码主界面。scanOnly=true 时为快捷入口（磁贴/小组件）：处理完即退出，不进主壳。
class ScannerScreen extends StatefulWidget {
  final bool scanOnly;
  const ScannerScreen({super.key, this.scanOnly = false});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: true,
    cameraResolution: const Size(1920, 1080),
  );
  final _parser = const ScanResultParser();
  bool _busy = false;

  // 多码累积窗口：首次检测到码后短暂多收集几帧，避免多码漏检。
  final Set<String> _pendingCodes = {};
  BarcodeCapture? _lastCapture; // 最后一帧，用于冻结图与角点
  Timer? _collectTimer;
  static const _collectWindow = Duration(milliseconds: 200);

  // 多码冻结点选覆盖层的数据（非空时在拍摄界面原地冻结）。
  ({
    ImageProvider image,
    Size size,
    List<({Rect rect, String value})> targets,
  })? _frozen;

  @override
  void dispose() {
    _collectTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    final valid =
        capture.barcodes.where((b) => (b.rawValue?.isNotEmpty ?? false));
    if (valid.isEmpty) return;
    // 累积这一帧的码，保留最新帧（用于冻结图/角点）。
    _pendingCodes.addAll(valid.map((b) => b.rawValue!));
    _lastCapture = capture;
    // 首次检测启动窗口，窗口内后续帧继续累积。
    _collectTimer ??= Timer(_collectWindow, _finishCollect);
  }

  void _finishCollect() {
    _collectTimer = null;
    if (!mounted || _busy) {
      _pendingCodes.clear();
      _lastCapture = null;
      return;
    }
    _busy = true;
    final codes = _pendingCodes.toList();
    final frame = _lastCapture;
    _pendingCodes.clear();
    _lastCapture = null;
    unawaited(_process(codes: codes, frameCapture: frame, galleryImage: null));
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    _busy = true;
    try {
      final capture = await _controller.analyzeImage(file.path);
      if (!mounted) return;
      final codes = capture == null
          ? <String>[]
          : <String>{
              for (final b in capture.barcodes)
                if (b.rawValue?.isNotEmpty ?? false) b.rawValue!,
            }.toList();
      if (codes.isEmpty) {
        _toast('图片里没找到二维码');
        _busy = false;
        return;
      }
      await _process(
        codes: codes,
        frameCapture: capture,
        galleryImage: FileImage(File(file.path)),
      );
    } catch (_) {
      if (mounted) _toast('识别失败');
      _busy = false;
    }
  }

  // 统一入口：单个码直接出结果；多个码在冻结画面上点选（回退文本列表）。
  // codes 已去重；frameCapture 提供冻结图与角点（实时=最后一帧，相册=该图）。
  Future<void> _process({
    required List<String> codes,
    required BarcodeCapture? frameCapture,
    required ImageProvider? galleryImage,
  }) async {
    if (codes.isEmpty) {
      _busy = false;
      return;
    }
    if (codes.length == 1) {
      await _handle(codes.first); // finally 复位 _busy（非 scanOnly）
      return;
    }

    if (!mounted) {
      _busy = false;
      return;
    }

    // 多码：优先冻结画面点选。角点取自 frameCapture，仅保留 codes 里的、且每值一次。
    final image = galleryImage ??
        (frameCapture?.image != null ? MemoryImage(frameCapture!.image!) : null);
    final codeSet = codes.toSet();
    final seen = <String>{};
    final targets = <({Rect rect, String value})>[
      if (frameCapture != null)
        for (final b in frameCapture.barcodes)
          if ((b.rawValue?.isNotEmpty ?? false) &&
              codeSet.contains(b.rawValue) &&
              b.corners.length >= 3 &&
              seen.add(b.rawValue!))
            (rect: _cornersToRect(b.corners), value: b.rawValue!),
    ];

    if (image != null &&
        frameCapture != null &&
        frameCapture.size != Size.zero &&
        targets.isNotEmpty) {
      // 原地冻结：亮出覆盖层，等用户点选/取消（回调里复位 _busy）。
      setState(() {
        _frozen = (image: image, size: frameCapture.size, targets: targets);
      });
      return;
    }

    // 无法冻结点选（极少见：无帧/无角点）：放弃本次，继续扫。
    _busy = false;
  }

  void _onFrozenPick(String value) {
    setState(() => _frozen = null);
    _handle(value); // 其 finally 复位 _busy（非 scanOnly）
  }

  void _onFrozenCancel() {
    setState(() => _frozen = null);
    _busy = false; // 继续扫，不退出
  }

  // 四角点 → 外接矩形（图像像素坐标）。
  Rect _cornersToRect(List<Offset> corners) {
    var minX = corners.first.dx, maxX = corners.first.dx;
    var minY = corners.first.dy, maxY = corners.first.dy;
    for (final c in corners) {
      if (c.dx < minX) minX = c.dx;
      if (c.dx > maxX) maxX = c.dx;
      if (c.dy < minY) minY = c.dy;
      if (c.dy > maxY) maxY = c.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
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
        if (_frozen == null)
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
        if (_frozen != null)
          Positioned.fill(
            child: FrozenQrOverlay(
              image: _frozen!.image,
              imageSize: _frozen!.size,
              targets: _frozen!.targets,
              onPick: _onFrozenPick,
              onCancel: _onFrozenCancel,
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
