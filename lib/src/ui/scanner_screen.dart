import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/history_entry.dart';
import '../core/scan_result.dart';
import '../services/history_store.dart';
import '../services/settings_store.dart';
import '../services/platform/beeper.dart';
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
  // normal + 超时：同一个码稍后可以再扫（noDuplicates 会永久屏蔽同值，
  // 直到扫到别的码为止）；连拍去重交给下面的 _sameCodeCooldown。
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 750,
    returnImage: true,
    cameraResolution: const Size(1920, 1080),
  );
  final _parser = const ScanResultParser();
  bool _busy = false;

  // 同值冷却：刚处理过的码在窗口内不再触发（防结果面板关掉又立刻弹回）。
  static const _sameCodeCooldown = Duration(seconds: 3);
  String? _lastHandled;
  DateTime _lastHandledAt = DateTime.fromMillisecondsSinceEpoch(0);

  // 连续扫描的本次计数（离开扫码页重置）；扫中光晕脉冲的触发计数。
  int _batchCount = 0;
  int _pulseTick = 0;

  // 变焦滑块随手机倾斜切换左右；双指捏合变焦；镜头切换（长焦/广角）。
  StreamSubscription<AccelerometerEvent>? _accelSub;
  bool _sliderOnLeft = false; // 默认右侧（右手拇指）
  double _zoomStart = 0; // 捏合起始变焦
  Set<CameraLensType> _lenses = const {}; // 设备支持的物理镜头
  CameraLensType _currentLens = CameraLensType.normal;

  // 多码冻结点选覆盖层的数据（非空时在拍摄界面原地冻结）。
  ({
    ImageProvider image,
    Size size,
    List<({Rect rect, String value})> targets,
    String path, // 冻结帧落盘路径，供"再次深度检测"复用
  })?
  _frozen;
  // 我们自己写盘的冻结帧路径（相册原图不归我们管），点选结束后删除。
  String? _tempFramePath;
  bool _lensesProbed = false;

  @override
  void initState() {
    super.initState();
    // 相机进入 running 后再查支持的镜头（代替固定延迟的竞态等待）。
    _controller.addListener(_onControllerChanged);
    // 重力/加速度：手机向哪侧倾，变焦滑块就到哪侧（就近拇指）。符号以实机为准。
    _accelSub =
        accelerometerEventStream(
          samplingPeriod: SensorInterval.uiInterval,
        ).listen((e) {
          // 竖持时 e.x > 0 ≈ 左倾、< 0 ≈ 右倾；±1.5 死区防抖。
          final onLeft = e.x > 1.5
              ? true
              : (e.x < -1.5 ? false : _sliderOnLeft);
          if (onLeft != _sliderOnLeft && mounted) {
            setState(() => _sliderOnLeft = onLeft);
          }
        });
  }

  void _onControllerChanged() {
    if (!_lensesProbed && _controller.value.isRunning) {
      _lensesProbed = true;
      _probeLenses();
    }
  }

  Future<void> _probeLenses() async {
    // running 之后原生侧镜头枚举仍可能晚一拍，留一个小缓冲。
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    try {
      final lenses = await _controller.getSupportedLenses();
      // 只有多于一个镜头才需要选择条；单/零镜头不显示。
      if (mounted && lenses.length > 1) {
        setState(() {
          _lenses = lenses;
          // 默认高亮：优先主摄，否则退到最广的可用镜头（兼容缺主摄的组合）。
          if (!lenses.contains(_currentLens)) {
            _currentLens = lenses.contains(CameraLensType.normal)
                ? CameraLensType.normal
                : (lenses.contains(CameraLensType.wide)
                      ? CameraLensType.wide
                      : CameraLensType.zoom);
          }
        });
      }
    } catch (_) {
      /* 不支持/查询失败：不显示镜头条 */
    }
  }

  // 镜头按等效焦距从广到长排序：超广角 → 主摄 → 长焦。
  List<CameraLensType> get _orderedLenses => [
    for (final l in [
      CameraLensType.wide,
      CameraLensType.normal,
      CameraLensType.zoom,
    ])
      if (_lenses.contains(l)) l,
  ];

  String _lensLabel(CameraLensType l) => switch (l) {
    CameraLensType.wide => '超广角',
    CameraLensType.normal => '主摄',
    CameraLensType.zoom => '长焦',
    CameraLensType.any => '自动',
  };

  void _selectLens(CameraLensType l) {
    _controller.switchCamera(SelectCamera(lensType: l));
    setState(() => _currentLens = l);
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _deleteTempFrame();
    super.dispose();
  }

  // 删除自己落盘的冻结帧（相机画面不留在磁盘上）。
  void _deleteTempFrame() {
    final p = _tempFramePath;
    _tempFramePath = null;
    if (p != null) {
      unawaited(File(p).delete().catchError((_) => File(p)));
    }
  }

  // 检测到码即处理：单码零延迟出结果；多码原地冻结点选（漏检用"再次深度检测"补）。
  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    final valid = capture.barcodes
        .where((b) => (b.rawValue?.isNotEmpty ?? false))
        .toList();
    if (valid.isEmpty) return;
    // 同值冷却：仍对着刚处理完的那个码 → 忽略，等移开或超时。
    if (valid.length == 1 &&
        valid.first.rawValue == _lastHandled &&
        DateTime.now().difference(_lastHandledAt) < _sameCodeCooldown) {
      return;
    }
    _busy = true;
    final codes = <String>{for (final b in valid) b.rawValue!}.toList();
    unawaited(
      _process(
        codes: codes,
        frameCapture: capture,
        galleryImage: null,
        sourcePath: null,
      ),
    );
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
        sourcePath: file.path,
      );
    } catch (_) {
      if (mounted) _toast('识别失败');
      _busy = false;
    }
  }

  // 统一入口：单个码直接出结果；多个码在拍摄界面原地冻结点选。
  // codes 已去重；frameCapture 提供角点；sourcePath 是可再检测的图像路径。
  Future<void> _process({
    required List<String> codes,
    required BarcodeCapture? frameCapture,
    required ImageProvider? galleryImage,
    required String? sourcePath,
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

    // 多码：在拍摄界面原地冻结点选。角点取自 frameCapture，仅 codes 里的、每值一次。
    final image =
        galleryImage ??
        (frameCapture?.image != null
            ? MemoryImage(frameCapture!.image!)
            : null);
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

    // 冻结帧落盘路径（相册用原图；实时把帧字节写临时文件），供"再次深度检测"。
    String? path = sourcePath;
    if (path == null && frameCapture?.image != null) {
      path = await _writeTempFrame(frameCapture!.image!);
      _tempFramePath = path;
    }

    if (image != null &&
        path != null &&
        frameCapture != null &&
        frameCapture.size != Size.zero &&
        targets.isNotEmpty) {
      // 原地冻结：亮出覆盖层，等用户点选/取消/再检测（回调里复位 _busy）。
      setState(() {
        _frozen = (
          image: image,
          size: frameCapture.size,
          targets: targets,
          path: path!,
        );
      });
      return;
    }

    // 无法冻结点选（极少见：无帧/无角点）：放弃本次，继续扫。
    _busy = false;
  }

  // 把实时帧字节写到临时文件，供 analyzeImage 再检测。
  Future<String> _writeTempFrame(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/saole_frozen_frame.jpg');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  // 再次深度检测：对冻结帧重跑 analyzeImage（静态图分析更充分），合并新码。
  Future<void> _redetect() async {
    final f = _frozen;
    if (f == null) return;
    try {
      final cap = await _controller.analyzeImage(f.path);
      if (!mounted || _frozen == null) return;
      final seen = {for (final t in _frozen!.targets) t.value};
      final more = <({Rect rect, String value})>[];
      if (cap != null) {
        for (final b in cap.barcodes) {
          final v = b.rawValue;
          if (v == null || v.isEmpty) continue;
          if (b.corners.length < 3) continue;
          if (seen.add(v)) {
            more.add((rect: _cornersToRect(b.corners), value: v));
          }
        }
      }
      if (more.isEmpty) {
        _toast('没有检测到更多二维码');
        return;
      }
      setState(() {
        _frozen = (
          image: _frozen!.image,
          size: _frozen!.size,
          targets: [..._frozen!.targets, ...more],
          path: _frozen!.path,
        );
      });
      _toast('又找到 ${more.length} 个');
    } catch (_) {
      if (mounted) _toast('检测失败');
    }
  }

  void _onFrozenPick(String value) {
    setState(() => _frozen = null);
    _deleteTempFrame();
    _handle(value); // 其 finally 复位 _busy（非 scanOnly）
  }

  void _onFrozenCancel() {
    setState(() => _frozen = null);
    _deleteTempFrame();
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
    _lastHandled = raw;
    _lastHandledAt = DateTime.now();
    try {
      final result = _parser.parse(raw);
      if (settings.haptics) HapticFeedback.mediumImpact();
      if (settings.beep) unawaited(const Beeper().beep());
      // 扫中反馈：屏幕边缘一圈主色光晕脉冲（配合震动/提示音的视觉确认）。
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        setState(() => _pulseTick++);
      }
      if (settings.keepHistory) {
        await context.read<HistoryStore>().add(
          HistoryEntry.fromScan(result, DateTime.now()),
        );
      }

      // FIDO：无条件直开（认证要快）；唤不起则弹面板兜底，不静默失败。
      if (result is FidoResult) {
        final ok = await const Launcher().open(result.raw);
        if (!ok && mounted) await showResultSheet(context, result);
        return;
      }
      // 自动打开（默认关，防钓鱼）：仅 http/https。自定义 scheme 的深链
      // （AppLink）攻击面大，始终走确认面板。失败兜底面板。
      if (settings.autoOpen && result is UrlResult) {
        final ok = await const Launcher().open(result.raw);
        if (!ok && mounted) await showResultSheet(context, result);
        return;
      }
      // 连续扫描（批量模式）：不弹面板打断，角落计数徽章常驻累加，继续扫。
      if (settings.continuous && !widget.scanOnly) {
        if (mounted) setState(() => _batchCount++);
        return;
      }

      if (!mounted) return;
      await showResultSheet(context, result);
    } finally {
      _finishOrResume();
    }
  }

  void _finishOrResume() {
    if (widget.scanOnly) {
      SystemNavigator.pop();
      return;
    }
    _busy = false;
  }

  void _toast(String msg) {
    // 顶掉未播完的旧提示：连续扫描时反馈必须跟手，不能排队。
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1500),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onScaleStart: (_) => _zoomStart = _controller.value.zoomScale,
          onScaleUpdate: (d) {
            if (d.pointerCount < 2) return; // 只响应双指捏合
            _controller.setZoomScale(
              (_zoomStart + (d.scale - 1)).clamp(0.0, 1.0),
            );
          },
          child: MobileScanner(
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
                    const Text(
                      '请在系统设置中授予相机权限，或改用相册识图。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _pickFromGallery,
                      child: const Text('从相册识别'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 扫中光晕：识别成功的瞬间屏幕边缘主色描边脉冲，快速淡出。
        if (_pulseTick > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_pulseTick),
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (context, v, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.85 * v),
                      width: 5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // 连续扫描计数徽章：常驻累加，代替逐次弹提示条。
        if (_frozen == null &&
            _batchCount > 0 &&
            context.watch<SettingsStore>().continuous)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '本次已扫 $_batchCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // 相册按钮：右下角（右手拇指顺手位）。
        if (_frozen == null)
          Positioned(
            right: 12,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 16),
              child: _RoundBtn(
                icon: Icons.photo_library,
                label: '从相册识别',
                onTap: _pickFromGallery,
              ),
            ),
          ),
        // 变焦滑块：位置随手机倾斜切到就近一侧（左倾左、右倾右），可拖动。
        if (_frozen == null)
          Positioned(
            left: _sliderOnLeft ? 6 : null,
            right: _sliderOnLeft ? null : 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: 200,
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, _) => Semantics(
                        label: '变焦',
                        child: Slider(
                          value: state.zoomScale.clamp(0.0, 1.0),
                          onChanged: (v) => _controller.setZoomScale(v),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // 底部中央：手电筒开关在上，镜头选择条（超广角/主摄/长焦）在下。
        // SafeArea：scanOnly 模式没有底部导航栏兜底，避免压到系统手势条。
        if (_frozen == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _controller,
                    builder: (context, state, _) {
                      final on = state.torchState == TorchState.on;
                      return _RoundBtn(
                        icon: on ? Icons.flash_on : Icons.flash_off,
                        label: on ? '关闭手电筒' : '打开手电筒',
                        // 开着时琥珀底黑图标，夜里一眼看出状态。
                        background: on ? Colors.amber : Colors.black54,
                        iconColor: on ? Colors.black : Colors.white,
                        onTap: () => _controller.toggleTorch(),
                      );
                    },
                  ),
                  if (_lenses.length > 1) ...[
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(28),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final lens in _orderedLenses)
                              _LensChip(
                                label: _lensLabel(lens),
                                selected: _currentLens == lens,
                                onTap: () => _selectLens(lens),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
              onRedetect: _redetect,
            ),
          ),
      ],
    );
  }
}

/// 镜头选择项：≥44dp 触控目标 + 水波反馈 + 选中态语义。
class _LensChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LensChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? Colors.white24 : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String label; // 无障碍/长按提示；纯图标按钮必须可被读屏读出
  final VoidCallback onTap;
  final Color background;
  final Color iconColor;
  const _RoundBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.background = Colors.black54,
    this.iconColor = Colors.white,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: iconColor),
        ),
      ),
    ),
  );
}
