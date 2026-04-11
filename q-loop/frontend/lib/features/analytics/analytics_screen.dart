import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _regionProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio
      .get(ApiConstants.analyticsByRegion, queryParameters: {'limit': 10});
  return res.data as List<dynamic>;
});

final _vehicleProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.analyticsByVehicle);
  return res.data as List<dynamic>;
});

final _platformProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.analyticsByPlatform);
  return res.data as List<dynamic>;
});

final _modeProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.analyticsByMode);
  return res.data as List<dynamic>;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: AppColors.surface(context),
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(isMobile: isMobile),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Row 1: by-vehicle + by-mode
                        LayoutBuilder(builder: (ctx, c) {
                          if (c.maxWidth > 700) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _VehicleChart(ref: ref)),
                                const SizedBox(width: 16),
                                Expanded(child: _ModeChart(ref: ref)),
                              ],
                            );
                          }
                          return Column(children: [
                            _VehicleChart(ref: ref),
                            const SizedBox(height: 16),
                            _ModeChart(ref: ref),
                          ]);
                        }),
                        const SizedBox(height: 24),
                        // Row 2: by-platform
                        _PlatformChart(ref: ref),
                        const SizedBox(height: 24),
                        // Row 3: by-region table
                        _RegionTable(ref: ref),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isMobile});
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        border: Border(bottom: BorderSide(color: AppColors.divider(context))),
      ),
      child: Row(children: [
        if (isMobile) ...[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        Text('Analytics',
            style: TextStyle(
                color: AppColors.surface(context) == AppColors.lightScaffoldBg
                    ? AppColors.lightTextPrimary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
      ]),
    );
  }
}

// ── Chart card wrapper ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.height = 260});
  final String title;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: AppColors.surface(context) == AppColors.lightScaffoldBg
                      ? AppColors.lightTextPrimary
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 16),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

// ── Vehicle type bar chart ────────────────────────────────────────────────────

class _VehicleChart extends StatelessWidget {
  const _VehicleChart({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_vehicleProvider);
    return _Card(
      title: 'Shipments by Vehicle Type',
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('$e',
                style: const TextStyle(color: AppColors.error, fontSize: 12))),
        data: (list) {
          final colors = [
            AppColors.primary,
            AppColors.accent,
            AppColors.success,
            AppColors.warning,
            AppColors.error,
            const Color(0xFF8B5CF6)
          ];
          return BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (list.isEmpty
                ? 1
                : (list
                        .map((r) => (r['total'] as num).toDouble())
                        .reduce((a, b) => a > b ? a : b)) *
                    1.2),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) {
                  final r = list[group.x] as Map<String, dynamic>;
                  return BarTooltipItem(
                      '${r['vehicle_type']}\n${r['total']} shipments\n${r['delay_rate_pct']}% delayed',
                      const TextStyle(color: Colors.white, fontSize: 11));
                },
              ),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  if (v.toInt() >= list.length) return const SizedBox();
                  final label =
                      (list[v.toInt()]['vehicle_type'] as String?) ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label.replaceAll('_', '\n'),
                        style: const TextStyle(fontSize: 9),
                        textAlign: TextAlign.center),
                  );
                },
                reservedSize: 32,
              )),
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(list.length, (i) {
              final r = list[i] as Map<String, dynamic>;
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: (r['total'] as num).toDouble(),
                  color: colors[i % colors.length],
                  width: 22,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]);
            }),
          ));
        },
      ),
    );
  }
}

// ── Delivery mode pie chart ───────────────────────────────────────────────────

class _ModeChart extends StatelessWidget {
  const _ModeChart({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_modeProvider);
    return _Card(
      title: 'Shipments by Delivery Mode',
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('$e',
                style: const TextStyle(color: AppColors.error, fontSize: 12))),
        data: (list) {
          final colors = [
            AppColors.primary,
            AppColors.accent,
            AppColors.success,
            AppColors.warning
          ];
          final total = list.fold<double>(
              0, (sum, r) => sum + (r['total'] as num).toDouble());
          return Row(children: [
            Expanded(
              child: PieChart(PieChartData(
                sections: List.generate(list.length, (i) {
                  final r = list[i] as Map<String, dynamic>;
                  final val = (r['total'] as num).toDouble();
                  return PieChartSectionData(
                    value: val,
                    color: colors[i % colors.length],
                    radius: 70,
                    title: '${(val / total * 100).toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  );
                }),
                sectionsSpace: 2,
                centerSpaceRadius: 30,
              )),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(list.length, (i) {
                final r = list[i] as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(r['delivery_mode'] as String? ?? '—',
                        style: const TextStyle(fontSize: 11)),
                  ]),
                );
              }),
            ),
          ]);
        },
      ),
    );
  }
}

// ── Platform comparison bar chart ─────────────────────────────────────────────

class _PlatformChart extends StatelessWidget {
  const _PlatformChart({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_platformProvider);
    return _Card(
      title: 'Platform Performance (Delay % vs Refund %)',
      height: 220,
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('$e',
                style: const TextStyle(color: AppColors.error, fontSize: 12))),
        data: (list) => BarChart(BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 100,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, rodIndex) {
                final r = list[group.x] as Map<String, dynamic>;
                final label = rodIndex == 0 ? 'Delay' : 'Refund';
                return BarTooltipItem(
                    '${r['platform']}\n$label: ${rod.toY.toStringAsFixed(1)}%',
                    const TextStyle(color: Colors.white, fontSize: 11));
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                if (v.toInt() >= list.length) return const SizedBox();
                final label = (list[v.toInt()]['platform'] as String?) ?? '';
                final short =
                    label.length > 10 ? '${label.substring(0, 9)}…' : label;
                return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(short, style: const TextStyle(fontSize: 9)));
              },
              reservedSize: 28,
            )),
            leftTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.textSecondary)),
              reservedSize: 30,
            )),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => FlLine(
                color: AppColors.border.withOpacity(0.3), strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(list.length, (i) {
            final r = list[i] as Map<String, dynamic>;
            return BarChartGroupData(x: i, barsSpace: 4, barRods: [
              BarChartRodData(
                  toY: (r['delay_rate_pct'] as num).toDouble(),
                  color: AppColors.warning,
                  width: 14,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3))),
              BarChartRodData(
                  toY: (r['refund_rate_pct'] as num).toDouble(),
                  color: AppColors.error,
                  width: 14,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3))),
            ]);
          }),
        )),
      ),
    );
  }
}

// ── Region table ──────────────────────────────────────────────────────────────

class _RegionTable extends StatelessWidget {
  const _RegionTable({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_regionProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Regions by Volume',
              style: TextStyle(
                  color: AppColors.surface(context) == AppColors.lightScaffoldBg
                      ? AppColors.lightTextPrimary
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 12),
          data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e',
                style: const TextStyle(color: AppColors.error, fontSize: 12)),
            data: (list) => Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border: Border(
                          bottom:
                              BorderSide(color: AppColors.divider(context)))),
                  children: [
                    'Region',
                    'Shipments',
                    'Delayed %',
                    'Avg Distance',
                    'Avg Cost'
                  ]
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(h,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.labelText(context))),
                          ))
                      .toList(),
                ),
                ...list.map((r) {
                  final row = r as Map<String, dynamic>;
                  final delayPct = (row['delay_rate_pct'] as num).toDouble();
                  return TableRow(children: [
                    _Cell(row['region'] as String? ?? '—'),
                    _Cell('${row['total']}'),
                    _Cell('${delayPct.toStringAsFixed(1)}%',
                        color: delayPct > 80
                            ? AppColors.error
                            : delayPct > 50
                                ? AppColors.warning
                                : AppColors.success),
                    _Cell(row['avg_distance_km'] != null
                        ? '${(row['avg_distance_km'] as num).toStringAsFixed(0)} km'
                        : '—'),
                    _Cell(row['avg_cost_inr'] != null
                        ? '₹${(row['avg_cost_inr'] as num).toStringAsFixed(0)}'
                        : '—'),
                  ]);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      );
}
