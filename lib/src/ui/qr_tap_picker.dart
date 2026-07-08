import 'package:flutter/material.dart';

import '../app/theme.dart';

/// 多码时在拍摄界面原地冻结的点选覆盖层：定格帧 cover 填满，叠加可点热区。
/// [targets] 的 rect 用图像像素坐标（与 [imageSize] 同坐标系）。
class FrozenQrOverlay extends StatelessWidget {
  final ImageProvider image;
  final Size imageSize;
  final List<({Rect rect, String value})> targets;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;
  final VoidCallback onRedetect;

  const FrozenQrOverlay({
    super.key,
    required this.image,
    required this.imageSize,
    required this.targets,
    required this.onPick,
    required this.onCancel,
    required this.onRedetect,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 描边按图像尺寸取相对值，cover 缩放后仍清晰。
    final stroke = (imageSize.shortestSide * 0.014).clamp(4.0, 48.0);
    // 150ms 淡入：从实时预览到定格不生硬。
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          // 定格帧 + 热区：cover 填满屏幕（像实时预览被定住），超出裁剪。
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: imageSize.width,
                height: imageSize.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image(image: image, fit: BoxFit.fill),
                    ),
                    for (final target in targets)
                      Positioned.fromRect(
                        rect: target.rect,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onPick(target.value),
                          child: Semantics(
                            button: true,
                            label: '选择二维码 ${target.value}',
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: t.accent.withValues(alpha: 0.25),
                                border: Border.all(
                                  color: t.accent,
                                  width: stroke,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 顶部浮层：提示 + 取消。
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '点选要用的二维码',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: '取消，继续扫码',
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onCancel,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 底部：再次深度检测（有时一帧检测不全，重跑静态分析补全）。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: onRedetect,
                    icon: const Icon(Icons.youtube_searched_for),
                    label: const Text('再次深度检测'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
