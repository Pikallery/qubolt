import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.trend,
    this.trendPositive = true,
    this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final double? trend;       // e.g. 12.5 means +12.5%
  final bool trendPositive;  // true = green for positive, false = red for positive
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              if (trend != null) _TrendBadge(trend: trend!, positive: trendPositive),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(
            color: AppColors.textMain(context),
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          )),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(
            color: AppColors.textSub(context), fontSize: 12)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(
              color: AppColors.labelText(context), fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend, required this.positive});
  final double trend;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    // A positive value is "good" if positive=true, "bad" if positive=false
    final isGood = positive ? trend > 0 : trend < 0;
    final color = isGood ? AppColors.success : AppColors.error;
    final arrow = trend >= 0 ? '↑' : '↓';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$arrow ${trend.abs().toStringAsFixed(1)}%',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
