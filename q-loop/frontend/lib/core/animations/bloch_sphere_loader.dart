import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class BlochSphereLoader extends StatefulWidget {
  final String label;
  const BlochSphereLoader({super.key, this.label = 'Quantum optimization in progress…'});
  @override
  State<BlochSphereLoader> createState() => _BlochSphereLoaderState();
}

class _BlochSphereLoaderState extends State<BlochSphereLoader> with TickerProviderStateMixin {
  late AnimationController _ring1, _ring2, _pulse, _particle;

  @override
  void initState() {
    super.initState();
    _ring1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
    _ring2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 3100))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _particle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _ring1.dispose(); _ring2.dispose(); _pulse.dispose(); _particle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        RepaintBoundary(
          child: SizedBox(
            width: 120, height: 120,
            child: AnimatedBuilder(
              animation: Listenable.merge([_ring1, _ring2, _pulse, _particle]),
              builder: (ctx, _) => CustomPaint(
                painter: _BlochSpherePainter(
                  ring1: _ring1.value,
                  ring2: _ring2.value,
                  pulse: _pulse.value,
                  particle: _particle.value,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.quantumAccent, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        const Text('QUBO · Simulated Annealing · 10,000 iterations',
          style: TextStyle(color: Color(0xFF484F58), fontSize: 10)),
      ]),
    );
  }
}

class _BlochSpherePainter extends CustomPainter {
  final double ring1, ring2, pulse, particle;
  _BlochSpherePainter({required this.ring1, required this.ring2, required this.pulse, required this.particle});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(cx, cy) - 8;

    // Glow sphere background
    final glowOpacity = 0.15 + pulse * 0.1;
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..color = AppColors.quantumPurple.withOpacity(glowOpacity)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));

    // Core sphere
    final gradient = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [
        AppColors.quantumPurple.withOpacity(0.7),
        const Color(0xFF0D1117),
      ],
    );
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..shader = gradient.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // Sphere outline glow
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..color = AppColors.quantumAccent.withOpacity(0.3 + pulse * 0.2)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    // Equatorial ring (ring1 rotates on Y axis — projected as an ellipse)
    final ring1Path = Path();
    const steps = 60;
    for (int i = 0; i <= steps; i++) {
      final theta = (i / steps) * 2 * math.pi;
      final rx = math.cos(theta) * r * 0.95;
      final ry = math.sin(theta) * r * 0.3; // squish for perspective
      final px = cx + rx;
      final py = cy + ry;
      if (i == 0) ring1Path.moveTo(px, py); else ring1Path.lineTo(px, py);
    }
    canvas.drawPath(ring1Path,
      Paint()..color = AppColors.quantumAccent.withOpacity(0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0);

    // Polar ring (ring2 — tilted 90°)
    final tilt2 = ring2 * 2 * math.pi;
    final ring2Path = Path();
    for (int i = 0; i <= steps; i++) {
      final theta = (i / steps) * 2 * math.pi;
      final x3d = math.cos(theta) * r * 0.95;
      final y3d = math.sin(theta) * r * 0.95;
      final px = cx + x3d * math.cos(tilt2);
      final py = cy + y3d * 0.25; // slight compression
      if (i == 0) ring2Path.moveTo(px, py); else ring2Path.lineTo(px, py);
    }
    canvas.drawPath(ring2Path,
      Paint()..color = AppColors.quantumPurple.withOpacity(0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0);

    // State vector (arrow)
    final angle = ring1 * 2 * math.pi;
    final vx = cx + math.sin(angle) * r * 0.6;
    final vy = cy - math.cos(angle) * r * 0.6;
    canvas.drawLine(Offset(cx, cy), Offset(vx, vy),
      Paint()..color = AppColors.quantumAccent
              ..strokeWidth = 2
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(Offset(vx, vy), 4,
      Paint()..color = AppColors.quantumAccent
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // Data particles orbiting
    for (int i = 0; i < 5; i++) {
      final t = (particle + i / 5) % 1.0;
      final pAngle = t * 2 * math.pi;
      final px2 = cx + math.cos(pAngle) * r * 0.85;
      final py2 = cy + math.sin(pAngle) * r * 0.25;
      canvas.drawCircle(Offset(px2, py2), 3,
        Paint()..color = AppColors.quantumAccent.withOpacity(0.8 - t * 0.3)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
