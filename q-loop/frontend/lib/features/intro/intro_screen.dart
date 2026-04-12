library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

// ── Vehicle types for the race ─────────────────────────────────────────────

enum _VType { truck, minivan, auto, bike }

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with TickerProviderStateMixin {
  late final AnimationController _loop;   // continuous scene loop
  late final AnimationController _accel;  // tap → accelerate off-screen
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _loop  = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _accel = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  }

  @override
  void dispose() {
    _loop.dispose();
    _accel.dispose();
    super.dispose();
  }

  Future<void> _onGetStarted() async {
    if (_started) return;
    setState(() => _started = true);
    await _accel.animateTo(1.0, curve: Curves.easeIn);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: Column(children: [
        // ── Scene (top ~62%) ────────────────────────────────────────────────
        SizedBox(
          height: size.height * 0.62,
          width: size.width,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _accel]),
              builder: (_, __) => CustomPaint(
                size: Size(size.width, size.height * 0.62),
                painter: _ScenePainter(
                  loop: _loop.value,
                  accel: _accel.value,
                ),
              ),
            ),
          ),
        ),

        // ── CTA section ─────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [AppColors.quantumAccent, Color(0xFF7000FF)],
                  ).createShader(bounds),
                  child: const Text('QUBOLT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                    )),
                ),
                const SizedBox(height: 6),
                Text('Quantum-Powered Last-Mile Logistics',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    letterSpacing: 0.6,
                  )),
                const SizedBox(height: 28),
                // Glowing CTA button
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.quantumAccent.withOpacity(0.45),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _started ? null : _onGetStarted,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.quantumAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                        disabledBackgroundColor: AppColors.quantumAccent,
                      ),
                      child: const Text('Get Started  →',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: 1.2,
                          color: Colors.black,
                        )),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: Text('Already have an account? Sign in',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.textSecondary,
                    )),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Scene Painter ──────────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  final double loop;   // 0–1 continuous
  final double accel;  // 0–1 on tap

  const _ScenePainter({required this.loop, required this.accel});

  // Vehicle configs: (type, laneYFrac, jitterPhase, jitterAmp, colorTint)
  static const _kVehicles = [
    (_VType.truck,   0.28, 0.00, 0.12),
    (_VType.minivan, 0.48, 1.40, 0.09),
    (_VType.auto,    0.66, 2.80, 0.14),
    (_VType.bike,    0.82, 0.90, 0.10),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _drawBg(canvas, size);
    _drawQuantumNodes(canvas, size);
    _drawTrees(canvas, size, layer: 0);
    _drawTrees(canvas, size, layer: 1);
    _drawRoad(canvas, size);
    _drawVehicles(canvas, size);
    _drawVignette(canvas, size);
  }

  // ── Background ─────────────────────────────────────────────────────────────
  void _drawBg(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF05080F), Color(0xFF080E16), Color(0xFF0D1117)],
        stops: [0, 0.45, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  // ── Quantum data nodes ─────────────────────────────────────────────────────
  void _drawQuantumNodes(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height * 0.52;
    const seed = 42;
    final rng = math.Random(seed);

    final nodes = List.generate(22, (i) {
      final rawX = (rng.nextDouble() + loop * 0.18) % 1.0;
      final rawY = rng.nextDouble() * 0.9;
      return Offset(rawX * w, rawY * h);
    });

    final linePaint = Paint()..strokeWidth = 0.5;
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final d = (nodes[i] - nodes[j]).distance;
        if (d < w * 0.22) {
          linePaint.color = AppColors.quantumAccent
              .withOpacity(0.07 * (1 - d / (w * 0.22)));
          canvas.drawLine(nodes[i], nodes[j], linePaint);
        }
      }
    }

    final dotPaint = Paint()..color = AppColors.quantumAccent.withOpacity(0.35);
    for (final n in nodes) {
      canvas.drawCircle(n, 1.8, dotPaint);
      // Tiny glow
      canvas.drawCircle(n, 4,
        Paint()
          ..color = AppColors.quantumAccent.withOpacity(0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
  }

  // ── Trees ──────────────────────────────────────────────────────────────────
  void _drawTrees(Canvas canvas, Size size, {required int layer}) {
    final w = size.width;
    final h = size.height;
    final roadY = h * 0.54;

    final speed   = layer == 0 ? 0.12 : 0.38;
    final tH      = layer == 0 ? h * 0.11 : h * 0.17;
    final tW      = layer == 0 ? w * 0.035 : w * 0.055;
    final yBase   = layer == 0 ? roadY - tH * 0.95 : roadY - tH;
    final opacity = layer == 0 ? 0.22 : 0.42;
    final count   = layer == 0 ? 14 : 9;

    final treePaint = Paint()
      ..color = const Color(0xFF0E1F0E).withOpacity(opacity)
      ..style = PaintingStyle.fill;

    // Subtle green edge glow for near trees
    final glowPaint = layer == 1
        ? (Paint()
          ..color = const Color(0xFF00D080).withOpacity(0.05)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6))
        : null;

    for (int i = 0; i < count; i++) {
      final baseX = ((i / count + loop * speed) % 1.0) * (w + tW * 2) - tW;

      // Trunk
      canvas.drawRect(
        Rect.fromLTWH(baseX + tW * 0.4, yBase + tH * 0.62, tW * 0.22, tH * 0.38),
        treePaint,
      );

      // Crown (triangle)
      final crown = Path()
        ..moveTo(baseX + tW * 0.5, yBase)
        ..lineTo(baseX + tW, yBase + tH * 0.65)
        ..lineTo(baseX, yBase + tH * 0.65)
        ..close();
      canvas.drawPath(crown, treePaint);

      if (glowPaint != null) canvas.drawPath(crown, glowPaint);
    }
  }

  // ── Road ───────────────────────────────────────────────────────────────────
  void _drawRoad(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final roadTop = h * 0.54;

    // Road surface
    canvas.drawRect(
      Rect.fromLTWH(0, roadTop, w, h - roadTop),
      Paint()..color = const Color(0xFF10161E),
    );

    // Road top edge
    canvas.drawLine(
      Offset(0, roadTop),
      Offset(w, roadTop),
      Paint()..color = const Color(0xFF253040)..strokeWidth = 1.5,
    );

    // Three lane dividers
    final divPaint = Paint()
      ..color = const Color(0xFF1C2A3A).withOpacity(0.6)
      ..strokeWidth = 1;
    for (int lane = 1; lane <= 3; lane++) {
      final y = roadTop + (h - roadTop) * (lane / 4.0);
      canvas.drawLine(Offset(0, y), Offset(w, y), divPaint);
    }

    // Scrolling dashes on center lane
    final dashPaint = Paint()
      ..color = const Color(0xFF2E4255).withOpacity(0.8)
      ..strokeWidth = 2;
    final dashLen = w * 0.07;
    final gapLen  = w * 0.05;
    final step    = dashLen + gapLen;
    final offset  = loop * step * 4;
    final midY    = roadTop + (h - roadTop) * 0.5;

    double x = -(offset % step);
    while (x < w + dashLen) {
      canvas.drawLine(Offset(x, midY), Offset(x + dashLen, midY), dashPaint);
      x += step;
    }
  }

  // ── Vehicles ───────────────────────────────────────────────────────────────
  void _drawVehicles(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final roadTop = h * 0.54;
    final roadH   = h - roadTop;

    for (final v in _kVehicles) {
      // Competition jitter: each vehicle surges ahead/drops back at different rates
      final jitter = math.sin(loop * math.pi * 5 + v.$3) * v.$4;
      double xFrac = 0.32 + jitter;

      // On acceleration: shoot off screen to the right
      if (accel > 0) xFrac += accel * accel * 1.8;

      final x = w * xFrac;
      final y = roadTop + roadH * v.$2;

      // Road-bump vertical jitter
      final yBump = math.sin(loop * math.pi * 9 + v.$3) * 1.5;

      _drawVehicle(canvas, v.$1, Offset(x, y + yBump), size);
    }
  }

  void _drawVehicle(Canvas canvas, _VType type, Offset pos, Size size) {
    final s = size.width * 0.05;

    // Glow
    final glow = Paint()
      ..color = AppColors.quantumAccent.withOpacity(0.13)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    // Stroke
    final stroke = Paint()
      ..color = AppColors.quantumAccent.withOpacity(0.88)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case _VType.truck:   _truck(canvas, pos, s, glow, stroke);
      case _VType.minivan: _minivan(canvas, pos, s, glow, stroke);
      case _VType.auto:    _auto(canvas, pos, s, glow, stroke);
      case _VType.bike:    _bike(canvas, pos, s, glow, stroke);
    }
  }

  void _truck(Canvas canvas, Offset p, double s, Paint glow, Paint stroke) {
    final paths = [
      // Cab
      Path()..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(p.dx, p.dy - s * 0.9, s, s * 0.9),
        topLeft: const Radius.circular(3), topRight: const Radius.circular(3),
      )),
      // Trailer
      Path()..addRect(Rect.fromLTWH(p.dx + s, p.dy - s * 0.75, s * 1.9, s * 0.75)),
      // Wheels
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 0.25, p.dy + s * 0.12), radius: s * 0.2)),
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 1.55, p.dy + s * 0.12), radius: s * 0.2)),
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 2.4, p.dy + s * 0.12), radius: s * 0.2)),
      // Cab window
      Path()..addRect(Rect.fromLTWH(p.dx + s * 0.12, p.dy - s * 0.78, s * 0.7, s * 0.42)),
    ];
    for (final path in paths) {
      canvas.drawPath(path, glow);
      canvas.drawPath(path, stroke);
    }
  }

  void _minivan(Canvas canvas, Offset p, double s, Paint glow, Paint stroke) {
    final paths = [
      // Body
      Path()..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(p.dx, p.dy - s * 0.82, s * 2.2, s * 0.82),
        topLeft: const Radius.circular(10), topRight: const Radius.circular(6),
        bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2),
      )),
      // Windows
      Path()
        ..addRect(Rect.fromLTWH(p.dx + s * 0.18, p.dy - s * 0.68, s * 0.52, s * 0.38))
        ..addRect(Rect.fromLTWH(p.dx + s * 0.82, p.dy - s * 0.68, s * 0.52, s * 0.38))
        ..addRect(Rect.fromLTWH(p.dx + s * 1.46, p.dy - s * 0.68, s * 0.44, s * 0.38)),
      // Wheels
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 0.38, p.dy + s * 0.11), radius: s * 0.19)),
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 1.82, p.dy + s * 0.11), radius: s * 0.19)),
    ];
    for (final path in paths) {
      canvas.drawPath(path, glow);
      canvas.drawPath(path, stroke);
    }
  }

  void _auto(Canvas canvas, Offset p, double s, Paint glow, Paint stroke) {
    // Smaller, 3-wheeled, canopy top
    final paths = [
      // Body
      Path()..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(p.dx, p.dy - s * 0.68, s * 1.5, s * 0.68),
        topLeft: const Radius.circular(12), topRight: const Radius.circular(5),
        bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2),
      )),
      // Front wheel
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 0.22, p.dy + s * 0.13), radius: s * 0.16)),
      // Rear wheels (dual)
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 1.15, p.dy + s * 0.13), radius: s * 0.16)),
      Path()..addOval(Rect.fromCircle(center: Offset(p.dx + s * 1.38, p.dy + s * 0.13), radius: s * 0.16)),
      // Canopy stripe
      Path()
        ..moveTo(p.dx + s * 0.05, p.dy - s * 0.68)
        ..lineTo(p.dx + s * 1.45, p.dy - s * 0.68),
      // Window opening
      Path()..addRect(Rect.fromLTWH(p.dx + s * 0.2, p.dy - s * 0.55, s * 0.6, s * 0.28)),
    ];
    for (final path in paths) {
      canvas.drawPath(path, glow);
      canvas.drawPath(path, stroke);
    }
  }

  void _bike(Canvas canvas, Offset p, double s, Paint glow, Paint stroke) {
    // Two wheels + diamond frame
    final fw = Offset(p.dx + s * 0.25, p.dy + s * 0.02);
    final rw = Offset(p.dx + s * 1.10, p.dy + s * 0.02);
    final seat = Offset(p.dx + s * 0.65, p.dy - s * 0.55);

    final paths = [
      Path()..addOval(Rect.fromCircle(center: fw, radius: s * 0.26)),
      Path()..addOval(Rect.fromCircle(center: rw, radius: s * 0.26)),
      // Frame
      Path()
        ..moveTo(fw.dx, fw.dy - s * 0.04)
        ..lineTo(seat.dx, seat.dy)
        ..lineTo(rw.dx, rw.dy - s * 0.04)
        ..moveTo(seat.dx, seat.dy)
        ..lineTo(fw.dx + s * 0.1, fw.dy - s * 0.06),
      // Handlebar
      Path()
        ..moveTo(seat.dx - s * 0.1, seat.dy)
        ..lineTo(p.dx + s * 0.38, p.dy - s * 0.68),
      // Seat
      Path()
        ..moveTo(seat.dx - s * 0.05, seat.dy - s * 0.02)
        ..lineTo(seat.dx + s * 0.32, seat.dy - s * 0.02),
    ];
    for (final path in paths) {
      canvas.drawPath(path, glow);
      canvas.drawPath(path, stroke);
    }
  }

  // ── Vignette ───────────────────────────────────────────────────────────────
  void _drawVignette(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Left fade
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w * 0.12, h),
      Paint()..shader = LinearGradient(
        colors: [AppColors.obsidian, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, w * 0.12, h)),
    );

    // Right fade
    canvas.drawRect(
      Rect.fromLTWH(w * 0.88, 0, w * 0.12, h),
      Paint()..shader = LinearGradient(
        colors: [Colors.transparent, AppColors.obsidian],
      ).createShader(Rect.fromLTWH(w * 0.88, 0, w * 0.12, h)),
    );

    // Bottom blend into CTA
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.78, w, h * 0.22),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, AppColors.obsidian],
      ).createShader(Rect.fromLTWH(0, h * 0.78, w, h * 0.22)),
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.loop != loop || old.accel != accel;
}
