import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ShipmentStatusChart extends StatelessWidget {
  const ShipmentStatusChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shipment Status',
              style: TextStyle(
                  color: AppColors.textMain(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 4),
          Text('Last 30 days',
              style: TextStyle(color: AppColors.textSub(context), fontSize: 11)),
          const SizedBox(height: 20),
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 50,
                sections: [
                  _section('Delivered', 0.62, AppColors.success),
                  _section('In Transit', 0.22, AppColors.accent),
                  _section('Pending', 0.10, AppColors.warning),
                  _section('Failed', 0.06, AppColors.error),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(spacing: 12, runSpacing: 6, children: [
            _Legend('Delivered', AppColors.success),
            _Legend('In Transit', AppColors.accent),
            _Legend('Pending', AppColors.warning),
            _Legend('Failed', AppColors.error),
          ]),
        ],
      ),
    );
  }

  PieChartSectionData _section(String title, double pct, Color color) {
    return PieChartSectionData(
      value: pct * 100,
      color: color,
      radius: 40,
      title: '${(pct * 100).toStringAsFixed(0)}%',
      titleStyle: const TextStyle(
          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(color: AppColors.textSub(context), fontSize: 11)),
    ]);
  }
}
