library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

enum _VType { truck, minivan, auto, bike }

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _loop;
  late final AnimationController _accel;
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
    final size   = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.obsidian : const Color(0xFFF0F6FF);

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(children: [
        // ── Scene ───────────────────────────────────────────────────────────
        SizedBox(
          height: size.height * 0.62,
          width: size.width,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _accel]),
              builder: (_, __) => CustomPaint(
                size: Size(size.width, size.height * 0.62),
                painter: _ScenePainter(
                  loop:   _loop.value,
                  accel:  _accel.value,
                  isDark: isDark,
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
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.lightTextSecondary,
                    fontSize: 13,
                    letterSpacing: 0.6,
                  )),
                const SizedBox(height: 28),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.quantumAccent.withValues(alpha: 0.45),
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
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                      decorationColor: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
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
  final double loop;
  final double accel;
  final bool isDark;

  const _ScenePainter({
    required this.loop,
    required this.accel,
    required this.isDark,
  });

  static const _kVehicles = [
    (_VType.truck,   0.28, 0.00, 0.12),
    (_VType.minivan, 0.48, 1.40, 0.09),
    (_VType.auto,    0.66, 2.80, 0.14),
    (_VType.bike,    0.82, 0.90, 0.10),
  ];

  // Light-mode palette
  static const _lightBg1   = Color(0xFFF0F6FF);
  static const _lightBg2   = Color(0xFFE4EFFC);
  static const _lightRoad  = Color(0xFFCDD8E6);
  static const _lightLane  = Color(0xFFB0BEC9);
  static const _lightTree  = Color(0xFF1E4A2C);

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

  void _drawBg(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF05080F), Color(0xFF080E16), Color(0xFF0D1117)]
            : const [_lightBg1, _lightBg2, Color(0xFFDAEAF8)],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawQuantumNodes(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height * 0.52;
    final rng = math.Random(42);

    final nodes = List.generate(22, (i) {
      final rawX = (rng.nextDouble() + loop * 0.18) % 1.0;
      final rawY = rng.nextDouble() * 0.9;
      return Offset(rawX * w, rawY * h);
    });

    final nodeColor = isDark
        ? AppColors.quantumAccent
        : AppColors.primary;

    final linePaint = Paint()..strokeWidth = 0.5;
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final d = (nodes[i] - nodes[j]).distance;
        if (d < w * 0.22) {
          linePaint.color = nodeColor.withValues(
              alpha: (isDark ? 0.07 : 0.14) * (1 - d / (w * 0.22)));
          canvas.drawLine(nodes[i], nodes[j], linePaint);
        }
      }
    }

    final dotPaint = Paint()
      ..color = nodeColor.withValues(alpha: isDark ? 0.38 : 0.55);
    for (final n in nodes) {
      canvas.drawCircle(n, 1.8, dotPaint);
      canvas.drawCircle(n, 4,
        Paint()
          ..color = nodeColor.withValues(alpha: isDark ? 0.07 : 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
  }

  void _drawTrees(Canvas canvas, Size size, {required int layer}) {
    final w = size.width;
    final h = size.height;
    final roadY = h * 0.54;

    final speed   = layer == 0 ? 0.12 : 0.38;
    final tH      = layer == 0 ? h * 0.11 : h * 0.17;
    final tW      = layer == 0 ? w * 0.035 : w * 0.055;
    final yBase   = layer == 0 ? roadY - tH * 0.95 : roadY - tH;
    final count   = layer == 0 ? 14 : 9;

    final treeColor = isDark
        ? const Color(0xFF0E1F0E).withValues(alpha: layer == 0 ? 0.22 : 0.42)
        : _lightTree.withValues(alpha: layer == 0 ? 0.28 : 0.55);

    final treePaint = Paint()
      ..color = treeColor
      ..style = PaintingStyle.fill;

    final glowPaint = layer == 1
        ? (Paint()
          ..color = (isDark
              ? const Color(0xFF00D080)
              : const Color(0xFF1A6B3A)).withValues(alpha: isDark ? 0.06 : 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6))
        : null;

    for (int i = 0; i < count; i++) {
      final baseX = ((i / count + loop * speed) % 1.0) * (w + tW * 2) - tW;
      canvas.drawRect(
        Rect.fromLTWH(baseX + tW * 0.4, yBase + tH * 0.62, tW * 0.22, tH * 0.38),
        treePaint,
      );
      final crown = Path()
        ..moveTo(baseX + tW * 0.5, yBase)
        ..lineTo(baseX + tW, yBase + tH * 0.65)
        ..lineTo(baseX, yBase + tH * 0.65)
        ..close();
      canvas.drawPath(crown, treePaint);
      if (glowPaint != null) canvas.drawPath(crown, glowPaint);
    }
  }

  void _drawRoad(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final roadTop = h * 0.54;

    canvas.drawRect(
      Rect.fromLTWH(0, roadTop, w, h - roadTop),
      Paint()..color = isDark ? const Color(0xFF10161E) : _lightRoad,
    );

    canvas.drawLine(
      Offset(0, roadTop),
      Offset(w, roadTop),
      Paint()
        ..color = isDark ? const Color(0xFF253040) : const Color(0xFFABBBC9)
        ..strokeWidth = 1.5,
    );

    final divPaint = Paint()
      ..color = (isDark ? const Color(0xFF1C2A3A) : _lightLane)
          .withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (int lane = 1; lane <= 3; lane++) {
      final y = roadTop + (h - roadTop) * (lane / 4.0);
      canvas.drawLine(Offset(0, y), Offset(w, y), divPaint);
    }

    final dashPaint = Paint()
      ..color = (isDark ? const Color(0xFF2E4255) : const Color(0xFF8FA8BF))
          .withValues(alpha: 0.8)
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

  void _drawVehicles(Canvas canvas, Size size) {
    final w       = size.width;
    final h       = size.height;
    final roadTop = h * 0.54;
    final roadH   = h - roadTop;

    for (final v in _kVehicles) {
      final jitter = math.sin(loop * math.pi * 5 + v.$3) * v.$4;
      double xFrac = 0.32 + jitter;
      if (accel > 0) xFrac += accel * accel * 1.8;
      final x = w * xFrac;
      final y = roadTop + roadH * v.$2;
      final yBump = math.sin(loop * math.pi * 9 + v.$3) * 1.5;
      _drawVehicle(canvas, v.$1, Offset(x, y + yBump), size);
    }
  }

  void _drawVehicle(Canvas canvas, _VType type, Offset pos, Size size) {
    final s = size.width * 0.05;

    final fillColor = isDark
        ? AppColors.quantumAccent.withValues(alpha: 0.14)
        : AppColors.primary.withValues(alpha: 0.18);
    final glowAlpha = isDark ? 0.15 : 0.22;
    final strokeAlpha = isDark ? 0.88 : 0.95;

    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final glow = Paint()
      ..color = (isDark ? AppColors.quantumAccent : AppColors.primary)
          .withValues(alpha: glowAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    final stroke = Paint()
      ..color = (isDark ? AppColors.quantumAccent : AppColors.primary)
          .withValues(alpha: strokeAlpha)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case _VType.truck:   _truck(canvas, pos, s, fill, glow, stroke);
      case _VType.minivan: _minivan(canvas, pos, s, fill, glow, stroke);
      case _VType.auto:    _auto(canvas, pos, s, fill, glow, stroke);
      case _VType.bike:    _bike(canvas, pos, s, fill, glow, stroke);
    }
  }

  void _drawShape(Canvas canvas, Path path, Paint fill, Paint glow, Paint stroke) {
    canvas.drawPath(path, fill);
    canvas.drawPath(path, glow);
    canvas.drawPath(path, stroke);
  }

  void _drawLine(Canvas canvas, Path path, Paint glow, Paint stroke) {
    canvas.drawPath(path, glow);
    canvas.drawPath(path, stroke);
  }

  void _truck(Canvas canvas, Offset p, double s, Paint fill, Paint glow, Paint stroke) {
    // Cab
    _drawShape(canvas, Path()..addRRect(RRect.fromRectAndCorners(
      Rect.fromLTWH(p.dx, p.dy - s * 0.9, s, s * 0.9),
      topLeft: const Radius.circular(3), topRight: const Radius.circular(3),
    )), fill, glow, stroke);
    // Trailer
    _drawShape(canvas, Path()..addRect(
      Rect.fromLTWH(p.dx + s, p.dy - s * 0.75, s * 1.9, s * 0.75),
    ), fill, glow, stroke);
    // Cab window
    _drawShape(canvas, Path()..addRect(
      Rect.fromLTWH(p.dx + s * 0.12, p.dy - s * 0.78, s * 0.7, s * 0.42),
    ), fill, glow, stroke);
    // Wheels
    for (final c in [
      Offset(p.dx + s * 0.25, p.dy + s * 0.12),
      Offset(p.dx + s * 1.55, p.dy + s * 0.12),
      Offset(p.dx + s * 2.40, p.dy + s * 0.12),
    ]) {
      _drawShape(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s * 0.20)),
          fill, glow, stroke);
    }
    // Exhaust
    _drawLine(canvas, Path()
      ..moveTo(p.dx + s * 0.78, p.dy - s * 0.90)
      ..lineTo(p.dx + s * 0.78, p.dy - s * 1.12),
      glow, stroke);
  }

  void _minivan(Canvas canvas, Offset p, double s, Paint fill, Paint glow, Paint stroke) {
    // Body
    _drawShape(canvas, Path()..addRRect(RRect.fromRectAndCorners(
      Rect.fromLTWH(p.dx, p.dy - s * 0.82, s * 2.2, s * 0.82),
      topLeft: const Radius.circular(10), topRight: const Radius.circular(6),
      bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2),
    )), fill, glow, stroke);
    // Windows (three)
    for (final r in [
      Rect.fromLTWH(p.dx + s * 0.18, p.dy - s * 0.68, s * 0.52, s * 0.38),
      Rect.fromLTWH(p.dx + s * 0.82, p.dy - s * 0.68, s * 0.52, s * 0.38),
      Rect.fromLTWH(p.dx + s * 1.46, p.dy - s * 0.68, s * 0.44, s * 0.38),
    ]) {
      _drawShape(canvas, Path()..addRect(r), fill, glow, stroke);
    }
    // Wheels
    for (final c in [
      Offset(p.dx + s * 0.38, p.dy + s * 0.11),
      Offset(p.dx + s * 1.82, p.dy + s * 0.11),
    ]) {
      _drawShape(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s * 0.19)),
          fill, glow, stroke);
    }
  }

  void _auto(Canvas canvas, Offset p, double s, Paint fill, Paint glow, Paint stroke) {
    // Canopy body
    _drawShape(canvas, Path()..addRRect(RRect.fromRectAndCorners(
      Rect.fromLTWH(p.dx, p.dy - s * 0.68, s * 1.5, s * 0.68),
      topLeft: const Radius.circular(12), topRight: const Radius.circular(5),
      bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2),
    )), fill, glow, stroke);
    // Window
    _drawShape(canvas, Path()..addRect(
      Rect.fromLTWH(p.dx + s * 0.2, p.dy - s * 0.55, s * 0.6, s * 0.28),
    ), fill, glow, stroke);
    // Wheels (front + dual rear)
    for (final c in [
      Offset(p.dx + s * 0.22, p.dy + s * 0.13),
      Offset(p.dx + s * 1.15, p.dy + s * 0.13),
      Offset(p.dx + s * 1.38, p.dy + s * 0.13),
    ]) {
      _drawShape(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s * 0.16)),
          fill, glow, stroke);
    }
  }

  /// Motorbike with rider (replaces bicycle).
  void _bike(Canvas canvas, Offset p, double s, Paint fill, Paint glow, Paint stroke) {
    // Key anchors
    final fw  = Offset(p.dx + s * 0.28, p.dy + s * 0.04);  // front wheel
    final rw  = Offset(p.dx + s * 1.28, p.dy + s * 0.04);  // rear wheel
    const wr  = 0.28;  // wheel radius multiplier

    // ── Wheels ──
    for (final c in [fw, rw]) {
      _drawShape(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s * wr)),
          fill, glow, stroke);
      // Hub detail
      _drawLine(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s * 0.08)),
          glow, stroke);
    }

    // ── Fuel tank / body ──
    _drawShape(canvas, Path()..addRRect(RRect.fromRectAndCorners(
      Rect.fromLTWH(p.dx + s * 0.36, p.dy - s * 0.70, s * 0.68, s * 0.34),
      topLeft: Radius.circular(s * 0.14), topRight: Radius.circular(s * 0.10),
      bottomLeft: Radius.circular(s * 0.04), bottomRight: Radius.circular(s * 0.04),
    )), fill, glow, stroke);

    // ── Engine block ──
    _drawShape(canvas, Path()..addRRect(RRect.fromRectAndCorners(
      Rect.fromLTWH(p.dx + s * 0.42, p.dy - s * 0.40, s * 0.80, s * 0.44),
      topLeft: Radius.circular(s * 0.06), topRight: Radius.circular(s * 0.06),
      bottomLeft: Radius.circular(s * 0.04), bottomRight: Radius.circular(s * 0.04),
    )), fill, glow, stroke);

    // ── Front fork ──
    _drawLine(canvas, Path()
      ..moveTo(p.dx + s * 0.44, p.dy - s * 0.40)
      ..lineTo(fw.dx + s * 0.06, fw.dy - s * wr * 0.15),
      glow, stroke);

    // ── Handlebars ──
    _drawLine(canvas, Path()
      ..moveTo(p.dx + s * 0.20, p.dy - s * 0.60)
      ..lineTo(p.dx + s * 0.44, p.dy - s * 0.40)
      ..moveTo(p.dx + s * 0.20, p.dy - s * 0.60)
      ..lineTo(p.dx + s * 0.20, p.dy - s * 0.42),
      glow, stroke);

    // ── Rear frame ──
    _drawLine(canvas, Path()
      ..moveTo(p.dx + s * 1.05, p.dy - s * 0.36)
      ..lineTo(rw.dx, rw.dy - s * wr * 0.15)
      ..moveTo(p.dx + s * 1.05, p.dy - s * 0.36)
      ..lineTo(p.dx + s * 0.80, p.dy - s * 0.05),
      glow, stroke);

    // ── Exhaust pipe ──
    _drawLine(canvas, Path()
      ..moveTo(rw.dx - s * 0.08, p.dy - s * 0.06)
      ..lineTo(rw.dx + s * 0.20, p.dy + s * 0.18)
      ..lineTo(rw.dx + s * 0.36, p.dy + s * 0.18),
      glow, stroke);

    // ── Seat ──
    _drawLine(canvas, Path()
      ..moveTo(p.dx + s * 0.72, p.dy - s * 0.58)
      ..lineTo(p.dx + s * 1.20, p.dy - s * 0.52),
      glow, stroke);

    // ── Rider: helmet ──
    final helmetC = Offset(p.dx + s * 0.78, p.dy - s * 1.02);
    _drawShape(canvas,
      Path()..addOval(Rect.fromCircle(center: helmetC, radius: s * 0.22)),
      fill, glow, stroke);
    // Visor slit
    _drawLine(canvas, Path()
      ..moveTo(helmetC.dx - s * 0.13, helmetC.dy + s * 0.04)
      ..lineTo(helmetC.dx + s * 0.16, helmetC.dy + s * 0.04),
      glow, stroke);

    // ── Rider: torso (leaning forward) ──
    _drawLine(canvas, Path()
      ..moveTo(helmetC.dx, helmetC.dy + s * 0.22)
      ..lineTo(p.dx + s * 0.96, p.dy - s * 0.52),
      glow, stroke);

    // ── Rider: arms to handlebars ──
    _drawLine(canvas, Path()
      ..moveTo(helmetC.dx - s * 0.06, helmetC.dy + s * 0.30)
      ..lineTo(p.dx + s * 0.20, p.dy - s * 0.50),
      glow, stroke);

    // ── Rider: legs (bent, foot on peg) ──
    _drawLine(canvas, Path()
      ..moveTo(p.dx + s * 0.96, p.dy - s * 0.52)
      ..lineTo(p.dx + s * 1.20, p.dy - s * 0.08)
      ..lineTo(p.dx + s * 1.40, p.dy - s * 0.08),
      glow, stroke);
  }

  void _drawVignette(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgColor = isDark ? AppColors.obsidian : const Color(0xFFF0F6FF);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w * 0.12, h),
      Paint()..shader = LinearGradient(
        colors: [bgColor, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, w * 0.12, h)),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.88, 0, w * 0.12, h),
      Paint()..shader = LinearGradient(
        colors: [Colors.transparent, bgColor],
      ).createShader(Rect.fromLTWH(w * 0.88, 0, w * 0.12, h)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.78, w, h * 0.22),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, bgColor],
      ).createShader(Rect.fromLTWH(0, h * 0.78, w, h * 0.22)),
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.loop != loop || old.accel != accel || old.isDark != isDark;
}
