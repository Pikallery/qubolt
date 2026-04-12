// Quantum particle background — glowing #00E5B0 qubits drifting on a dark canvas
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class QuantumParticleBackground extends StatefulWidget {
  final Widget child;
  const QuantumParticleBackground({super.key, required this.child});
  @override
  State<QuantumParticleBackground> createState() => _QuantumParticleBgState();
}

class _Particle {
  double x, y, vx, vy, radius, opacity;
  _Particle({required this.x, required this.y, required this.vx, required this.vy, required this.radius, required this.opacity});
}

class _QuantumParticleBgState extends State<QuantumParticleBackground> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_Particle> _particles;
  Offset _mouse = Offset.zero;
  Size _size = Size.zero;
  final _rand = math.Random();

  void _initParticles(Size size) {
    _size = size;
    _particles = List.generate(60, (_) => _Particle(
      x: _rand.nextDouble() * size.width,
      y: _rand.nextDouble() * size.height,
      vx: (_rand.nextDouble() - 0.5) * 0.3,
      vy: (_rand.nextDouble() - 0.5) * 0.3,
      radius: _rand.nextDouble() * 2.5 + 0.5,
      opacity: _rand.nextDouble() * 0.5 + 0.1,
    ));
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_tick)
      ..repeat();
  }

  void _tick() {
    if (_size == Size.zero) return;
    for (final p in _particles) {
      // Repulse from mouse
      final dx = p.x - _mouse.dx;
      final dy = p.y - _mouse.dy;
      final dist = math.sqrt(dx*dx + dy*dy);
      if (dist < 80 && dist > 0) {
        p.vx += (dx / dist) * 0.4;
        p.vy += (dy / dist) * 0.4;
      }
      // Dampen
      p.vx *= 0.98;
      p.vy *= 0.98;
      // Clamp speed
      final speed = math.sqrt(p.vx*p.vx + p.vy*p.vy);
      if (speed > 1.2) { p.vx *= 1.2/speed; p.vy *= 1.2/speed; }
      p.x += p.vx;
      p.y += p.vy;
      // Wrap edges
      if (p.x < -5) p.x = _size.width + 5;
      if (p.x > _size.width + 5) p.x = -5;
      if (p.y < -5) p.y = _size.height + 5;
      if (p.y > _size.height + 5) p.y = -5;
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      if (_size == Size.zero || (_size.width != constraints.maxWidth || _size.height != constraints.maxHeight)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _initParticles(Size(constraints.maxWidth, constraints.maxHeight)));
        });
      }
      return MouseRegion(
        onHover: (e) => setState(() => _mouse = e.localPosition),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (ctx, _) => CustomPaint(
              painter: _ParticlePainter(_particles, _size),
              child: widget.child,
            ),
          ),
        ),
      );
    });
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final Size canvasSize;
  _ParticlePainter(this.particles, this.canvasSize);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = AppColors.quantumAccent.withOpacity(p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(p.x, p.y), p.radius, paint);
      // Inner bright dot
      canvas.drawCircle(Offset(p.x, p.y), p.radius * 0.4,
        Paint()..color = AppColors.quantumAccent.withOpacity(p.opacity * 1.5));
    }
    // Draw faint connection lines between nearby particles
    final linePaint = Paint()..strokeWidth = 0.3;
    for (int i = 0; i < particles.length; i++) {
      for (int j = i+1; j < particles.length; j++) {
        final dx = particles[i].x - particles[j].x;
        final dy = particles[i].y - particles[j].y;
        final dist = math.sqrt(dx*dx + dy*dy);
        if (dist < 80) {
          linePaint.color = AppColors.quantumAccent.withOpacity(0.08 * (1 - dist/80));
          canvas.drawLine(Offset(particles[i].x, particles[i].y), Offset(particles[j].x, particles[j].y), linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
