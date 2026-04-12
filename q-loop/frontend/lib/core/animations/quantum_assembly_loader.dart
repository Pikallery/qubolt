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

    // Main assembly: 0→1 over 2.8s
    _progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
      ..forward();

    // Particle tick at ~60fps
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();

    // Completion pulse (fires once near end)
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) _pulse.forward();
    });

    // Spawn 60 particles with random start positions off-screen
    _particles = List.generate(60, (i) => _AssemblyParticle.random(_rand));

    // Each tick, advance particles toward their target
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_progress, _particleCtrl, _pulse]),
        builder: (_, __) => SizedBox(
          width: 260,
          height: 200,
          child: CustomPaint(
            painter: _AssemblyPainter(
              vehicle: widget.vehicle,
              progress: _progress.value,
              pulse: _pulse.value,
              particles: _particles,
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
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Progress bar
                  SizedBox(
                    width: 120,
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _progress.value,
                        backgroundColor: const Color(0xFF1C2128),
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
  // Current position (0–1 normalized canvas coords)
  double x, y;
  // Target position on the vehicle outline (0–1 normalized)
  double tx, ty;
  // When this particle starts flying (progress threshold 0–1)
  double startAt;
  double opacity;
  double radius;
  bool landed;

  _AssemblyParticle({
    required this.x, required this.y,
    required this.tx, required this.ty,
    required this.startAt,
    required this.opacity,
    required this.radius,
  }) : landed = false;

  factory _AssemblyParticle.random(math.Random rng) {
    // Spawn from edges/corners
    final side = rng.nextInt(4);
    double sx, sy;
    switch (side) {
      case 0: sx = rng.nextDouble(); sy = -0.05; break; // top
      case 1: sx = 1.05; sy = rng.nextDouble(); break;  // right
      case 2: sx = rng.nextDouble(); sy = 1.05; break;  // bottom
      default: sx = -0.05; sy = rng.nextDouble();       // left
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
    if (progress < startAt) return;
    if (landed) return;

    final t = ((progress - startAt) / (1.0 - startAt)).clamp(0.0, 1.0);
    // Ease-in-out toward target
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

  const _AssemblyPainter({
    required this.vehicle,
    required this.progress,
    required this.pulse,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw particles
    _drawParticles(canvas, size);

    // Draw wireframe outline — revealed by progress (dash offset trick)
    _drawWireframe(canvas, size);

    // Pulse glow at completion
    if (pulse > 0) _drawCompletionPulse(canvas, size);
  }

  void _drawParticles(Canvas canvas, Size size) {
    for (final p in particles) {
      final px = p.x * size.width;
      final py = p.y * size.height * 0.78; // keep above label area
      final alpha = p.opacity * (p.landed ? 1.0 : 0.7);

      // Glow aura
      canvas.drawCircle(Offset(px, py), p.radius * 3.5,
        Paint()
          ..color = AppColors.quantumAccent.withValues(alpha: alpha * 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));

      // Core dot
      canvas.drawCircle(Offset(px, py), p.radius,
        Paint()..color = AppColors.quantumAccent.withValues(alpha: alpha));
    }
  }

  void _drawWireframe(Canvas canvas, Size size) {
    final path = _buildVehiclePath(size);

    // Compute total path length approximation via metric
    // approx total path length — used to gate reveal logic

    final paint = Paint()
      ..color = AppColors.quantumAccent.withValues(alpha: 0.85 * progress)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Glow pass
    final glowPaint = Paint()
      ..color = AppColors.quantumAccent.withValues(alpha: 0.22 * progress)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Simulate partial reveal by clipping to a diagonal scanline
    canvas.save();
    final clipRect = Rect.fromLTWH(0, 0, size.width * progress * 1.05, size.height);
    canvas.clipRect(clipRect);

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
    canvas.restore();

    // Scan line at the reveal frontier
    if (progress > 0 && progress < 1.0) {
      final scanX = size.width * progress * 1.05;
      canvas.drawLine(
        Offset(scanX, 0),
        Offset(scanX, size.height * 0.78),
        Paint()
          ..color = AppColors.quantumAccent.withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

  }

  // ignore: unused_element
  void _drawCompletionPulse(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.38;
    final maxR = size.width * 0.6;
    final r = maxR * pulse;
    final alpha = (1.0 - pulse) * 0.5;

    canvas.drawCircle(Offset(cx, cy), r,
      Paint()
        ..color = AppColors.quantumAccent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    canvas.drawCircle(Offset(cx, cy), r * 0.6,
      Paint()
        ..color = AppColors.quantumAccent.withValues(alpha: alpha * 0.4)
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

  // ── Vehicle wireframe paths (centered, scaled to size) ────────────────────

  Path _truckPath(Size size) {
    final w = size.width;
    final h = size.height * 0.72;
    final ox = w * 0.06;
    final oy = h * 0.18;
    final s = w * 0.1;

    return Path()
      // Cab
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox, oy + s * 0.1, s * 1.0, s * 1.0),
        topLeft: const Radius.circular(4), topRight: const Radius.circular(4)))
      // Cab window
      ..addRect(Rect.fromLTWH(ox + s * 0.12, oy + s * 0.2, s * 0.72, s * 0.46))
      // Trailer
      ..addRect(Rect.fromLTWH(ox + s, oy + s * 0.28, s * 2.6, s * 0.82))
      // Hitch
      ..moveTo(ox + s * 0.98, oy + s * 0.7)
      ..lineTo(ox + s * 1.02, oy + s * 0.7)
      // Front wheel
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 0.32, oy + s * 1.18), radius: s * 0.24))
      // Rear wheels
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 1.65, oy + s * 1.18), radius: s * 0.24))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 2.4, oy + s * 1.18), radius: s * 0.24))
      // Exhaust
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
      // Body shell
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox, oy, s * 2.9, s * 1.0),
        topLeft: const Radius.circular(14), topRight: const Radius.circular(8)))
      // Windshield
      ..moveTo(ox + s * 0.12, oy)
      ..lineTo(ox + s * 0.06, oy + s * 0.95)
      // Rear window
      ..moveTo(ox + s * 2.5, oy + s * 0.08)
      ..lineTo(ox + s * 2.84, oy + s * 0.95)
      // Window 1
      ..addRect(Rect.fromLTWH(ox + s * 0.26, oy + s * 0.12, s * 0.6, s * 0.5))
      // Window 2
      ..addRect(Rect.fromLTWH(ox + s * 1.02, oy + s * 0.12, s * 0.6, s * 0.5))
      // Window 3
      ..addRect(Rect.fromLTWH(ox + s * 1.76, oy + s * 0.12, s * 0.56, s * 0.5))
      // Wheels
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 0.48, oy + s * 1.08), radius: s * 0.24))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 2.38, oy + s * 1.08), radius: s * 0.24))
      // Door line
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
      // Canopy / roof
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox + s * 0.05, oy, s * 1.55, s * 0.72),
        topLeft: const Radius.circular(18), topRight: const Radius.circular(8)))
      // Passenger floor
      ..addRect(Rect.fromLTWH(ox + s * 0.05, oy + s * 0.7, s * 1.55, s * 0.22))
      // Front nose
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(ox - s * 0.2, oy + s * 0.42, s * 0.3, s * 0.5),
        topLeft: const Radius.circular(4), bottomLeft: const Radius.circular(4)))
      // Window opening
      ..addRect(Rect.fromLTWH(ox + s * 0.24, oy + s * 0.08, s * 0.66, s * 0.38))
      // Roof stripe
      ..moveTo(ox + s * 0.05, oy)
      ..lineTo(ox + s * 1.6, oy)
      // Front wheel (single)
      ..addOval(Rect.fromCircle(center: Offset(ox - s * 0.06, oy + s * 1.06), radius: s * 0.19))
      // Rear wheels (dual)
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 1.14, oy + s * 1.06), radius: s * 0.19))
      ..addOval(Rect.fromCircle(center: Offset(ox + s * 1.42, oy + s * 1.06), radius: s * 0.19))
      // Handlebar
      ..moveTo(ox - s * 0.1, oy + s * 0.22)
      ..lineTo(ox - s * 0.1, oy + s * 0.42);
  }

  Path _bikePath(Size size) {
    final w = size.width;
    final h = size.height * 0.72;
    final ox = w * 0.1;
    final oy = h * 0.18;
    final s = w * 0.1;

    final fw = Offset(ox + s * 0.4, oy + s * 0.96);
    final rw = Offset(ox + s * 1.82, oy + s * 0.96);
    final bb = Offset(ox + s * 1.06, oy + s * 0.62); // bottom bracket
    final seat = Offset(ox + s * 0.98, oy + s * 0.18);
    final head = Offset(ox + s * 0.46, oy + s * 0.32);

    return Path()
      // Wheels
      ..addOval(Rect.fromCircle(center: fw, radius: s * 0.34))
      ..addOval(Rect.fromCircle(center: rw, radius: s * 0.34))
      // Inner wheel detail
      ..addOval(Rect.fromCircle(center: fw, radius: s * 0.08))
      ..addOval(Rect.fromCircle(center: rw, radius: s * 0.08))
      // Chain stay (rear triangle base)
      ..moveTo(bb.dx, bb.dy)
      ..lineTo(rw.dx, rw.dy - s * 0.06)
      // Seat stay
      ..moveTo(seat.dx + s * 0.08, seat.dy)
      ..lineTo(rw.dx, rw.dy - s * 0.06)
      // Down tube
      ..moveTo(head.dx + s * 0.04, head.dy + s * 0.2)
      ..lineTo(bb.dx, bb.dy)
      // Top tube
      ..moveTo(head.dx + s * 0.04, head.dy + s * 0.2)
      ..lineTo(seat.dx, seat.dy)
      // Fork
      ..moveTo(head.dx, head.dy)
      ..lineTo(fw.dx + s * 0.06, fw.dy - s * 0.06)
      // Handlebar
      ..moveTo(head.dx - s * 0.14, head.dy - s * 0.08)
      ..lineTo(head.dx + s * 0.14, head.dy - s * 0.08)
      // Seat post
      ..moveTo(seat.dx, seat.dy)
      ..lineTo(bb.dx + s * 0.04, bb.dy)
      // Saddle
      ..moveTo(seat.dx - s * 0.12, seat.dy - s * 0.02)
      ..lineTo(seat.dx + s * 0.32, seat.dy - s * 0.02)
      // Crank arm
      ..moveTo(bb.dx - s * 0.18, bb.dy + s * 0.04)
      ..lineTo(bb.dx + s * 0.18, bb.dy - s * 0.04)
      // Pedals
      ..moveTo(bb.dx + s * 0.18, bb.dy - s * 0.04)
      ..lineTo(bb.dx + s * 0.28, bb.dy - s * 0.04)
      ..moveTo(bb.dx - s * 0.18, bb.dy + s * 0.04)
      ..lineTo(bb.dx - s * 0.28, bb.dy + s * 0.04);
  }

  @override
  bool shouldRepaint(covariant _AssemblyPainter old) =>
      old.progress != progress || old.pulse != pulse;
}
