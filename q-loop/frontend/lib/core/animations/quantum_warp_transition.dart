import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class QuantumWarpOverlay extends StatefulWidget {
  final VoidCallback onComplete;
  const QuantumWarpOverlay({super.key, required this.onComplete});
  @override
  State<QuantumWarpOverlay> createState() => _QuantumWarpOverlayState();
}

class _QuantumWarpOverlayState extends State<QuantumWarpOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _ring, _fill, _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _ring = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeInOutCubic));
    _fill = CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 0.85, curve: Curves.easeIn));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0.85, 1.0, curve: Curves.easeOut));
    _ctrl.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        final size = MediaQuery.of(context).size;
        final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);
        return IgnorePointer(
          child: CustomPaint(
            size: Size(size.width, size.height),
            painter: _WarpPainter(
              ringProgress: _ring.value,
              fillProgress: _fill.value,
              fadeProgress: _fade.value,
              screenSize: size,
              maxRadius: maxRadius,
            ),
          ),
        );
      },
    );
  }
}

class _WarpPainter extends CustomPainter {
  final double ringProgress, fillProgress, fadeProgress, maxRadius;
  final Size screenSize;
  _WarpPainter({required this.ringProgress, required this.fillProgress, required this.fadeProgress, required this.screenSize, required this.maxRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;

    // Expanding ring
    final ringRadius = ringProgress * maxRadius * 0.55;
    final ringWidth = 3.0 + ringProgress * 6;
    canvas.drawCircle(Offset(cx, cy), ringRadius,
      Paint()..color = AppColors.quantumAccent.withOpacity((1 - ringProgress) * 0.9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = ringWidth
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));

    // Fill sweep
    if (fillProgress > 0) {
      final fillRadius = fillProgress * maxRadius;
      canvas.drawCircle(Offset(cx, cy), fillRadius,
        Paint()..color = AppColors.obsidian.withOpacity(fillProgress.clamp(0, 1)));
    }

    // Data streaks from edges to center
    if (ringProgress > 0.1) {
      for (int i = 0; i < 12; i++) {
        final angle = (i / 12) * 2 * math.pi + 0.3;
        final startR = maxRadius;
        final endR = maxRadius * (1 - ringProgress * 0.8);
        final sx = cx + math.cos(angle) * startR;
        final sy = cy + math.sin(angle) * startR;
        final ex = cx + math.cos(angle) * endR;
        final ey = cy + math.sin(angle) * endR;
        canvas.drawLine(Offset(sx, sy), Offset(ex, ey),
          Paint()..color = AppColors.quantumAccent.withOpacity(0.15 * ringProgress)
                  ..strokeWidth = 0.8 + (i % 3) * 0.4);
      }
    }

    // Fade out
    if (fadeProgress > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = AppColors.obsidian.withOpacity(fadeProgress));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
