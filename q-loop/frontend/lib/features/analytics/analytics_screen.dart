import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../../core/widgets/api_error_widget.dart';
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

final _behavioralEntropyProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.analyticsBehavioralEntropy);
  return res.data as Map<String, dynamic>;
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
                        // Row 0: Wave-Function / Behavioral Entropy
                        _WaveFunctionChart(ref: ref),
                        const SizedBox(height: 24),
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
        error: (e, _) => ApiErrorWidget(error: e, compact: true),
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
        error: (e, _) => ApiErrorWidget(error: e, compact: true),
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
        error: (e, _) => ApiErrorWidget(error: e, compact: true),
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
            error: (e, _) => ApiErrorWidget(error: e, compact: true),
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

// ── Wave-Function / Behavioral Entropy Chart ──────────────────────────────────

class _WaveFunctionChart extends StatefulWidget {
  const _WaveFunctionChart({required this.ref});
  final WidgetRef ref;

  @override
  State<_WaveFunctionChart> createState() => _WaveFunctionChartState();
}

class _WaveFunctionChartState extends State<_WaveFunctionChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.ref.watch(_behavioralEntropyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider(context)),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: AppColors.quantumAccent.withValues(alpha: 0.06),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(children: [
            AnimatedBuilder(
              animation: _shimmer,
              builder: (_, child) => ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    AppColors.quantumAccent,
                    const Color(0xFF7000FF),
                    AppColors.quantumAccent,
                  ],
                  stops: [
                    (_shimmer.value - 0.3).clamp(0.0, 1.0),
                    _shimmer.value.clamp(0.0, 1.0),
                    (_shimmer.value + 0.3).clamp(0.0, 1.0),
                  ],
                ).createShader(bounds),
                child: child!,
              ),
              child: Text(
                'Wave-Function  ·  Behavioral Entropy',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.quantumAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.quantumAccent.withValues(alpha: 0.35)),
              ),
              child: const Text('OBSERVER EFFECT',
                  style: TextStyle(
                      color: AppColors.quantumAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'ETA accuracy: Quantum Optimization (predicted) vs fleet baseline (actual)',
            style: TextStyle(
                color: AppColors.labelText(context),
                fontSize: 11),
          ),
          const SizedBox(height: 16),

          data.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.quantumAccent)),
            ),
            error: (e, _) => SizedBox(
              height: 200,
              child: ApiErrorWidget(error: e, compact: true),
            ),
            data: (d) {
              final predicted =
                  (d['predicted'] as List).map((v) => (v as num).toDouble()).toList();
              final actual =
                  (d['actual'] as List).map((v) => (v as num).toDouble()).toList();
              final entropy = (d['entropy_score'] as num).toDouble();
              final interpretation = d['interpretation'] as String? ?? '';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 110,
                        clipData: const FlClipData.all(),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: AppColors.divider(context)
                                .withValues(alpha: 0.4),
                            strokeWidth: 0.5,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: 25,
                              getTitlesWidget: (v, _) => Text(
                                '${v.toInt()}%',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: AppColors.labelText(context)),
                              ),
                            ),
                          ),
                          bottomTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (spots) => spots.map((s) {
                              final label =
                                  s.barIndex == 0 ? 'Quantum' : 'Baseline';
                              return LineTooltipItem(
                                '$label\n${s.y.toStringAsFixed(1)}%',
                                TextStyle(
                                  color: s.barIndex == 0
                                      ? AppColors.quantumAccent
                                      : AppColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        lineBarsData: [
                          // Predicted (quantum) — neon teal with glow gradient
                          LineChartBarData(
                            spots: List.generate(
                              predicted.length,
                              (i) => FlSpot(i.toDouble(), predicted[i]),
                            ),
                            isCurved: true,
                            curveSmoothness: 0.35,
                            color: AppColors.quantumAccent,
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.quantumAccent
                                      .withValues(alpha: isDark ? 0.22 : 0.15),
                                  AppColors.quantumAccent
                                      .withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                          // Actual (baseline) — electric blue
                          LineChartBarData(
                            spots: List.generate(
                              actual.length,
                              (i) => FlSpot(i.toDouble(), actual[i]),
                            ),
                            isCurved: true,
                            curveSmoothness: 0.35,
                            color: AppColors.accent,
                            barWidth: 1.8,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            dashArray: [6, 4],
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.accent
                                      .withValues(alpha: isDark ? 0.10 : 0.07),
                                  AppColors.accent.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Legend + entropy score
                  Row(children: [
                    _WaveLegendDot(
                        color: AppColors.quantumAccent, label: 'Quantum (predicted)'),
                    const SizedBox(width: 16),
                    _WaveLegendDot(
                        color: AppColors.accent, label: 'Baseline (actual)', dashed: true),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _entropyColor(entropy)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _entropyColor(entropy)
                                .withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'Entropy: ${entropy.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: _entropyColor(entropy),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    interpretation,
                    style: TextStyle(
                        color: AppColors.labelText(context), fontSize: 11),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Color _entropyColor(double e) {
    if (e < 10) return AppColors.success;
    if (e > 25) return AppColors.quantumAccent;
    return AppColors.warning;
  }
}

class _WaveLegendDot extends StatelessWidget {
  const _WaveLegendDot(
      {required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 24,
        height: 2,
        child: dashed
            ? CustomPaint(painter: _DashPainter(color: color))
            : DecoratedBox(decoration: BoxDecoration(color: color)),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontSize: 11, color: AppColors.labelText(context))),
    ]);
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + 4).clamp(0, size.width), size.height / 2), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}
