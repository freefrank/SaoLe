import 'package:flutter/material.dart';

import '../app/theme.dart';

/// 一次检测到多个码时，在冻结画面上点选。返回选中的原始串；取消返回 null。
/// [targets] 的 rect 用图像像素坐标（与 [imageSize] 同坐标系）。
Future<String?> showQrTapPicker(
  BuildContext context, {
  required ImageProvider image,
  required Size imageSize,
  required List<({Rect rect, String value})> targets,
}) {
  // 高亮描边宽度按图像尺寸取相对值，缩放后仍清晰可见。
  final stroke = (imageSize.shortestSide * 0.014).clamp(4.0, 48.0);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    builder: (context) {
      final t = context.tokens;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('点选要用的二维码',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
              ),
              Flexible(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
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
                                onTap: () =>
                                    Navigator.pop(context, target.value),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: t.accent.withValues(alpha: 0.25),
                                    border: Border.all(
                                        color: t.accent, width: stroke),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
