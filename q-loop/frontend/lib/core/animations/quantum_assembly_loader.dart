library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

enum VehicleType { truck, minivan, auto, bike }

class QuantumAssemblyLoader extends StatefulWidget {
  final VehicleType vehicle;
  final String label;
  const QuantumAssemblyLoader({super.key, required this.vehicle, this.label = ''});

  @override
  State<QuantumAssemblyLoader> createState() => _QuantumAssemblyLoaderState();
}

class _QuantumAssemblyLoaderState extends State<QuantumAssemblyLoader>
    with TickerProviderStateMixin {
  late final AnimationController _progress;
  late final AnimationController _particleCtrl;
  late final AnimationController _pulse;
  late final List<_AssemblyParticle> _particles;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
      ..forward();
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) _pulse.forward();
    });
    _particles = List.generate(60, (i) => _AssemblyParticle.random(_rand));
    _particleCtrl.addListener(_tickParticles);
  }

  void _tickParticles() {
    final p = _progress.value;
    for (final particle in _particles) {
      particle.advance(p, _rand);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _particleCtrl.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_progress, _particleCtrl, _pulse]),
        builder: (_, __) => SizedBox(
          width: 260,
          height: 200,
          child: CustomPaint(
            painter: _AssemblyPainter(
              vehicle:  widget.vehicle,
              progress: _progress.value,
              pulse:    _pulse.value,
              particles: _particles,
              isDark:   isDark,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    _progress.value >= 1.0
                        ? 'Vehicle Assembled!'
                        : widget.label.isNotEmpty
                            ? widget.label
                            : 'Assembling ${widget.vehicle.name}…',
                    style: TextStyle(
                      color: _progress.value >= 1.0
                          ? AppColors.quantumAccent
                          : isDark
                              ? AppColors.textSecondary
                              : AppColors.lightTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 120,
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _progress.value,
                        backgroundColor: isDark
                            ? const Color(0xFF1C2128)
                            : const Color(0xFFDDE6F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.quantumAccent.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Particle ─────────────────────────────────────────────────────────────────

class _AssemblyParticle {
  double x, y, tx, ty, startAt, opacity, radius;
  bool landed;

  _AssemblyParticle({
    required this.x, required this.y,
    required this.tx, required this.ty,
    required this.startAt,
    required this.opacity,
    required this.radius,
  }) : landed = false;

  factory _AssemblyParticle.random(math.Random rng) {
    final side = rng.nextInt(4);
    double sx, sy;
    switch (side) {
      case 0: sx = rng.nextDouble(); sy = -0.05; break;
      case 1: sx = 1.05; sy = rng.nextDouble(); break;
      case 2: sx = rng.nextDouble(); sy = 1.05; break;
      default: sx = -0.05; sy = rng.nextDouble();
    }
    return _AssemblyParticle(
      x: sx, y: sy,
      tx: 0.3 + rng.nextDouble() * 0.4,
      ty: 0.25 + rng.nextDouble() * 0.5,
      startAt: rng.nextDouble() * 0.85,
      opacity: rng.nextDouble() * 0.5 + 0.4,
      radius: rng.nextDouble() * 1.8 + 0.8,
    );
  }

  void advance(double progress, math.Random rng) {
    if (progress < startAt || landed) return;
    final t = ((progress - startAt) / (1.0 - startAt)).clamp(0.0, 1.0);
    final ease = t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
    x = x + (tx - x) * ease * 0.18;
    y = y + (ty - y) * ease * 0.18;
    if ((x - tx).abs() < 0.005 && (y - ty).abs() < 0.005) {
      x = tx; y = ty; landed = true;
    }
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _AssemblyPainter extends CustomPainter {
  final VehicleType vehicle;
  final double progress;
  final double pulse;
  final List<_AssemblyParticle> particles;
  final bool isDark;

  const _AssemblyPainter({
    required this.vehicle,
    required this.progress,
    required this.pulse,
    required this.particles,
    required this.isDark,
  });

  Color get _accent => AppColors.quantumAccent;

  @override
  void paint(Canvas canvas, Size size) {
    _drawParticles(canvas, size);
    _drawWireframe(canvas, size);
    if (pulse > 0) _drawCompletionPulse(canvas, size);
  }

  void _drawParticles(Canvas canvas, Size size) {
    for (final p in particles) {
      final px = p.x * size.width;
      final py = p.y * size.height * 0.78;
      final alpha = p.opacity * (p.landed ? 1.0 : 0.7);

      canvas.drawCircle(Offset(px, py), p.radius * 3.5,
        Paint()
          ..color = _accent.withValues(alpha: alpha * (isDark ? 0.18 : 0.25))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(Offset(px, py), p.radius,
        Paint()..color = _accent.withValues(alpha: alpha));
    }
  }

  void _drawWireframe(Canvas canvas, Size size) {
    final path = _buildVehiclePath(size);

    // Semi-transparent fill — gives vehicles body so they don't look transparent
    final fillPaint = Paint()
      ..color = _accent.withValues(alpha: 0.10 * progress)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = _accent.withValues(alpha: 0.88 * progress)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = _accent.withValues(alpha: (isDark ? 0.22 : 0.30) * progress)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.save();
    final clipRect = Rect.fromLTWH(0, 0, size.width * progress * 1.05, size.height);
    canvas.clipRect(clipRect);

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, strokePaint);
    canvas.restore();

    // Scanline frontier
    if (progress > 0 && progress < 1.0) {
      final scanX = size.width * progress * 1.05;
      canvas.drawLine(
        Offset(scanX, 0),
        Offset(scanX, size.height * 0.78),
        Paint()
          ..color = _accent.withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  void _drawCompletionPulse(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.38;
    final maxR = size.width * 0.6;
    final r = maxR * pulse;
    final alpha = (1.0 - pulse) * 0.5;
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()
        ..color = _accent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(Offset(cx, cy), r * 0.6,
      Paint()
        ..color = _accent.withValues(alpha: alpha * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
  }

  Path _buildVehiclePath(Size size) {
    switch (vehicle) {
      case VehicleType.truck:   return _truckPath(size);
      case VehicleType.minivan: return _minivanPath(size);
      case VehicleType.auto:    return _autoPath(size);
      case VehicleType.bike:    return _bikePath(size);
    }
  }

  // ── Vehicle wireframe paths ────────────────────────────────────────────────

  Path _truckPath(Size size) {
    final w = size.width;
    final h = size.height * 0.72;
    final ox = w * 0.06;
    final oy = h * 0.18;
    final s = w * 0.1;

    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox, oy + s * 0.1, s * 1.0, s * 1.0),
        topLeft: const Radius.circular(4), topRight: const Radius.circular(4)))
      ..addRect(Rect.fromLTWH(ox + s * 0.12, oy + s * 0.2, s * 0.72, s * 0.46))
      ..addRect(Rect.fromLTWH(ox + s, oy + s * 0.28, s * 2.6, s * 0.82))
      ..moveTo(ox + s * 0.98, oy + s * 0.7)
      ..lineTo(ox + s * 1.02, oy + s * 0.7)
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 0.32, oy + s * 1.18), radius: s * 0.24))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 1.65, oy + s * 1.18), radius: s * 0.24))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 2.40, oy + s * 1.18), radius: s * 0.24))
      ..moveTo(ox + s * 0.78, oy + s * 0.1)
      ..lineTo(ox + s * 0.78, oy - s * 0.22);
  }

  Path _minivanPath(Size size) {
    final w = size.width;
    final h = size.height * 0.72;
    final ox = w * 0.08;
    final oy = h * 0.22;
    final s = w * 0.092;

    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox, oy, s * 2.9, s * 1.0),
        topLeft: const Radius.circular(14), topRight: const Radius.circular(8)))
      ..moveTo(ox + s * 0.12, oy)
      ..lineTo(ox + s * 0.06, oy + s * 0.95)
      ..moveTo(ox + s * 2.5, oy + s * 0.08)
      ..lineTo(ox + s * 2.84, oy + s * 0.95)
      ..addRect(Rect.fromLTWH(ox + s * 0.26, oy + s * 0.12, s * 0.60, s * 0.50))
      ..addRect(Rect.fromLTWH(ox + s * 1.02, oy + s * 0.12, s * 0.60, s * 0.50))
      ..addRect(Rect.fromLTWH(ox + s * 1.76, oy + s * 0.12, s * 0.56, s * 0.50))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 0.48, oy + s * 1.08), radius: s * 0.24))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 2.38, oy + s * 1.08), radius: s * 0.24))
      ..moveTo(ox + s * 0.92, oy + s * 0.02)
      ..lineTo(ox + s * 0.92, oy + s * 0.98);
  }

  Path _autoPath(Size size) {
    final w = size.width;
    final h = size.height * 0.72;
    final ox = w * 0.14;
    final oy = h * 0.22;
    final s = w * 0.1;

    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox + s * 0.05, oy, s * 1.55, s * 0.72),
        topLeft: const Radius.circular(18), topRight: const Radius.circular(8)))
      ..addRect(Rect.fromLTWH(ox + s * 0.05, oy + s * 0.7, s * 1.55, s * 0.22))
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox - s * 0.2, oy + s * 0.42, s * 0.3, s * 0.5),
        topLeft: const Radius.circular(4), bottomLeft: const Radius.circular(4)))
      ..addRect(Rect.fromLTWH(ox + s * 0.24, oy + s * 0.08, s * 0.66, s * 0.38))
      ..moveTo(ox + s * 0.05, oy)
      ..lineTo(ox + s * 1.60, oy)
      ..addOval(Rect.fromCircle(center: Offset(ox - s * 0.06, oy + s * 1.06), radius: s * 0.19))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 1.14, oy + s * 1.06), radius: s * 0.19))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 1.42, oy + s * 1.06), radius: s * 0.19))
      ..moveTo(ox - s * 0.1, oy + s * 0.22)
      ..lineTo(ox - s * 0.1, oy + s * 0.42);
  }

  /// Motorbike with rider — replaces the old bicycle path.
  Path _bikePath(Size size) {
    final w  = size.width;
    final h  = size.height * 0.72;
    final ox = w * 0.09;
    final oy = h * 0.22;
    final s  = w * 0.12;

    // Key geometry
    final fwc = Offset(ox + s * 0.42, oy + s * 1.02);   // front wheel center
    final rwc = Offset(ox + s * 1.88, oy + s * 1.02);   // rear wheel center
    final fwr = s * 0.34;                                  // wheel radius

    final headTop  = Offset(ox + s * 0.58, oy + s * 0.28);  // head tube
    final seatBase = Offset(ox + s * 1.32, oy + s * 0.32);  // seat attachment

    // Rider
    final helmetC  = Offset(ox + s * 0.66, oy - s * 0.12);

    return Path()
      // ── Wheels ──────────────────────────────────────────────────────────────
      ..addOval(Rect.fromCircle(center: fwc, radius: fwr))
      ..addOval(Rect.fromCircle(center: fwc, radius: fwr * 0.22))
      ..addOval(Rect.fromCircle(center: rwc, radius: fwr))
      ..addOval(Rect.fromCircle(center: rwc, radius: fwr * 0.22))
      // Spoke lines (front wheel)
      ..moveTo(fwc.dx, fwc.dy - fwr * 0.88)
      ..lineTo(fwc.dx, fwc.dy + fwr * 0.88)
      ..moveTo(fwc.dx - fwr * 0.88, fwc.dy)
      ..lineTo(fwc.dx + fwr * 0.88, fwc.dy)
      // Spoke lines (rear wheel)
      ..moveTo(rwc.dx, rwc.dy - fwr * 0.88)
      ..lineTo(rwc.dx, rwc.dy + fwr * 0.88)
      ..moveTo(rwc.dx - fwr * 0.88, rwc.dy)
      ..lineTo(rwc.dx + fwr * 0.88, rwc.dy)

      // ── Fuel tank ───────────────────────────────────────────────────────────
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox + s * 0.52, oy + s * 0.04, s * 0.66, s * 0.30),
        topLeft: Radius.circular(s * 0.18), topRight: Radius.circular(s * 0.12),
        bottomLeft: Radius.circular(s * 0.04), bottomRight: Radius.circular(s * 0.04),
      ))

      // ── Engine / lower body ─────────────────────────────────────────────────
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox + s * 0.56, oy + s * 0.32, s * 0.84, s * 0.50),
        topLeft: Radius.circular(s * 0.08), topRight: Radius.circular(s * 0.06),
        bottomLeft: Radius.circular(s * 0.06), bottomRight: Radius.circular(s * 0.06),
      ))

      // ── Front fork ──────────────────────────────────────────────────────────
      ..moveTo(headTop.dx, headTop.dy + s * 0.30)
      ..lineTo(fwc.dx + s * 0.06, fwc.dy - fwr * 0.12)

      // ── Handlebars ──────────────────────────────────────────────────────────
      ..moveTo(ox + s * 0.26, oy + s * 0.12)
      ..lineTo(headTop.dx, headTop.dy + s * 0.30)
      ..moveTo(ox + s * 0.26, oy + s * 0.12)
      ..lineTo(ox + s * 0.26, oy + s * 0.38)

      // ── Rear frame ──────────────────────────────────────────────────────────
      ..moveTo(seatBase.dx + s * 0.40, seatBase.dy)
      ..lineTo(rwc.dx, rwc.dy - fwr * 0.15)
      ..moveTo(seatBase.dx + s * 0.40, seatBase.dy)
      ..lineTo(ox + s * 1.16, oy + s * 0.82)
      ..lineTo(rwc.dx, rwc.dy - fwr * 0.15)

      // ── Chain (bottom) ──────────────────────────────────────────────────────
      ..moveTo(ox + s * 1.38, oy + s * 0.80)
      ..lineTo(rwc.dx - s * 0.05, rwc.dy - fwr * 0.10)

      // ── Exhaust ─────────────────────────────────────────────────────────────
      ..moveTo(ox + s * 1.56, oy + s * 0.66)
      ..lineTo(rwc.dx + s * 0.14, oy + s * 0.94)
      ..lineTo(rwc.dx + s * 0.34, oy + s * 0.94)

      // ── Headlight ───────────────────────────────────────────────────────────
      ..addOval(Rect.fromCircle(
        center: Offset(fwc.dx + s * 0.02, headTop.dy + s * 0.18),
        radius: s * 0.10,
      ))

      // ── Seat ────────────────────────────────────────────────────────────────
      ..moveTo(seatBase.dx - s * 0.08, seatBase.dy - s * 0.04)
      ..lineTo(seatBase.dx + s * 0.50, seatBase.dy - s * 0.04)

      // ── Rider: helmet ────────────────────────────────────────────────────────
      ..addOval(Rect.fromCircle(center: helmetC, radius: s * 0.26))
      // Helmet visor slit
      ..moveTo(helmetC.dx - s * 0.16, helmetC.dy + s * 0.05)
      ..lineTo(helmetC.dx + s * 0.18, helmetC.dy + s * 0.05)
      // Helmet glare
      ..moveTo(helmetC.dx - s * 0.10, helmetC.dy - s * 0.13)
      ..lineTo(helmetC.dx + s * 0.04, helmetC.dy - s * 0.21)

      // ── Rider: torso (leaning forward) ───────────────────────────────────────
      ..moveTo(helmetC.dx + s * 0.02, helmetC.dy + s * 0.26)
      ..lineTo(seatBase.dx, seatBase.dy)

      // ── Rider: arms ──────────────────────────────────────────────────────────
      ..moveTo(helmetC.dx + s * 0.02, helmetC.dy + s * 0.36)
      ..lineTo(ox + s * 0.26, oy + s * 0.24)

      // ── Rider: leg (bent at knee, foot on peg) ───────────────────────────────
      ..moveTo(seatBase.dx, seatBase.dy)
      ..lineTo(ox + s * 1.52, oy + s * 0.76)
      ..lineTo(ox + s * 1.74, oy + s * 0.76)

      // ── Rider: back leg (visible on other side) ──────────────────────────────
      ..moveTo(seatBase.dx + s * 0.14, seatBase.dy + s * 0.04)
      ..lineTo(ox + s * 1.64, oy + s * 0.82);
  }

  @override
  bool shouldRepaint(covariant _AssemblyPainter old) =>
      old.progress != progress || old.pulse != pulse || old.isDark != isDark;
}
