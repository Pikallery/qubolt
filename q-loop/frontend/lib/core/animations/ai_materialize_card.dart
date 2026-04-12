import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AiMaterializeCard extends StatefulWidget {
  final String text;
  final Widget? header;
  const AiMaterializeCard({super.key, required this.text, this.header});
  @override
  State<AiMaterializeCard> createState() => _AiMaterializeCardState();
}

class _AiMaterializeCardState extends State<AiMaterializeCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scanLine, _fade;
  String _displayed = '';
  Timer? _typeTimer;
  int _charIndex = 0;
  final _rand = math.Random();
  static const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%&*';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _scanLine = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5, curve: Curves.easeIn));
    _ctrl.forward();
    // Start typewriter after scan line reaches position
    Future.delayed(const Duration(milliseconds: 400), _startTypewriter);
  }

  void _startTypewriter() {
    _typeTimer = Timer.periodic(const Duration(milliseconds: 22), (timer) {
      if (_charIndex >= widget.text.length) {
        timer.cancel();
        return;
      }
      // Scramble phase: show random char for ~20ms then reveal real char
      final scrambled = _chars[_rand.nextInt(_chars.length)];
      setState(() => _displayed = widget.text.substring(0, _charIndex) + scrambled);
      Future.delayed(const Duration(milliseconds: 18), () {
        if (mounted) {
          setState(() {
            _displayed = widget.text.substring(0, _charIndex + 1);
            _charIndex++;
          });
        }
      });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); _typeTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) => Opacity(
        opacity: _fade.value,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.quantumAccent.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.quantumAccent.withOpacity(0.2 + _scanLine.value * 0.15)),
            boxShadow: [
              BoxShadow(
                color: AppColors.quantumAccent.withOpacity(0.08 + _ctrl.value * 0.06),
                blurRadius: 20, spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(children: [
              // Content
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (widget.header != null) ...[widget.header!, const SizedBox(height: 14)],
                  Text(
                    _displayed.isEmpty ? '' : _displayed,
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 13, height: 1.7, letterSpacing: 0.2,
                    ),
                  ),
                ]),
              ),
              // Scan line
              if (_scanLine.value < 0.95)
                Positioned(
                  top: _scanLine.value * 300, // sweeps down
                  left: 0, right: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        AppColors.quantumAccent.withOpacity(0.6),
                        AppColors.quantumAccent,
                        AppColors.quantumAccent.withOpacity(0.6),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
