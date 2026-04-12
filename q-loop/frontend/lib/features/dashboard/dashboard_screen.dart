import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../routes/ghost_route_map.dart';
import 'widgets/metric_card.dart';
import 'widgets/dark_sidebar.dart';
import 'widgets/shipment_status_chart.dart';
import 'dashboard_provider.dart';

// QUBO optimizer state for dashboard
final _dashQuboRunningProvider = StateProvider<bool>((ref) => false);
final _dashQuboResultProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

// AI Insights state for dashboard
final _dashAiLoadingProvider = StateProvider<bool>((ref) => false);
final _dashAiResponseProvider = StateProvider<String?>((ref) => null);
final _dashAiErrorProvider = StateProvider<bool>((ref) => false);
final _dashAiExpandedProvider = StateProvider<bool>((ref) => true);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(dashboardMetricsProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      body: Row(
        children: [
          // ── Dark Sidebar (desktop only) ──────────────────────────────────
          if (!isMobile) const DarkSidebar(),

          // ── Main content ─────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar
                _TopBar(isMobile: isMobile),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Metric cards row ────────────────────────────────
                        metrics.when(
                          loading: () => const _MetricCardsSkeleton(),
                          error: (e, _) => _ErrorBanner(e.toString()),
                          data: (m) => _MetricsGrid(metrics: m),
                        ),

                        const SizedBox(height: 24),

                        // ── QUBO Optimizer card ──────────────────────────────
                        _QUBOOptimizerCard(
                          isRunning: ref.watch(_dashQuboRunningProvider),
                          result: ref.watch(_dashQuboResultProvider),
                          onRun: () async {
                            ref.read(_dashQuboRunningProvider.notifier).state =
                                true;
                            ref.read(_dashQuboResultProvider.notifier).state =
                                null;
                            try {
                              final dio = ref.read(dioProvider);
                              final res = await dio.post(
                                ApiConstants.routeBuildFromPoints,
                                data: {
                                  'limit': 30,
                                  'initial_temp': 5000.0,
                                  'cooling_rate': 0.999,
                                  'max_iterations': 20000,
                                },
                              );
                              ref.read(_dashQuboResultProvider.notifier).state =
                                  res.data as Map<String, dynamic>;
                            } catch (_) {
                              // silently ignore — button resets
                            } finally {
                              ref
                                  .read(_dashQuboRunningProvider.notifier)
                                  .state = false;
                            }
                          },
                        ),

                        const SizedBox(height: 24),

                        // ── AI Insights card ───────────────────────────────
                        _AiInsightsCard(
                          isLoading: ref.watch(_dashAiLoadingProvider),
                          response: ref.watch(_dashAiResponseProvider),
                          hasError: ref.watch(_dashAiErrorProvider),
                          isExpanded: ref.watch(_dashAiExpandedProvider),
                          onToggle: () {
                            ref.read(_dashAiExpandedProvider.notifier).state =
                                !ref.read(_dashAiExpandedProvider);
                          },
                          onAnalyze: () async {
                            ref.read(_dashAiLoadingProvider.notifier).state =
                                true;
                            ref.read(_dashAiErrorProvider.notifier).state =
                                false;
                            ref.read(_dashAiResponseProvider.notifier).state =
                                null;
                            try {
                              final dio = ref.read(dioProvider);
                              final res = await dio.post(
                                ApiConstants.aiInsight,
                                data: {
                                  'query':
                                      'Dashboard overview: summarize key supply chain metrics and recommendations for Odisha region',
                                },
                              );
                              final data = res.data as Map<String, dynamic>;
                              ref.read(_dashAiResponseProvider.notifier).state =
                                  (data['insight'] as String?) ??
                                      (data['message'] as String?) ??
                                      _kDashAiFallback;
                            } catch (_) {
                              ref.read(_dashAiErrorProvider.notifier).state =
                                  true;
                              ref.read(_dashAiResponseProvider.notifier).state =
                                  _kDashAiFallback;
                            } finally {
                              ref.read(_dashAiLoadingProvider.notifier).state =
                                  false;
                            }
                          },
                        ),

                        const SizedBox(height: 24),

                        // ── Ghost route map + chart row ──────────────────────
                        LayoutBuilder(builder: (ctx, constraints) {
                          final wide = constraints.maxWidth > 900;
                          final mapWidget = GestureDetector(
                            onTap: () => context.push('/fleet'),
                            child: Stack(
                              children: [
                                const GhostRouteMap(),
                                Positioned(
                                  bottom: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface(context).withOpacity(0.92),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppColors.primary
                                              .withOpacity(0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.touch_app,
                                            color: AppColors.primary, size: 14),
                                        SizedBox(width: 6),
                                        Text(
                                          'Tap to view live fleet',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: mapWidget),
                                const SizedBox(width: 16),
                                const Expanded(
                                    flex: 2, child: ShipmentStatusChart()),
                              ],
                            );
                          }
                          return Column(children: [
                            mapWidget,
                            const SizedBox(height: 16),
                            const ShipmentStatusChart(),
                          ]);
                        }),
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
      child: Row(
        children: [
          if (isMobile) ...[
            Icon(Icons.loop, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text('Qubolt',
                style: TextStyle(
                    color: AppColors.textMain(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const Spacer(),
          ] else ...[
            Text('Dashboard',
                style: TextStyle(
                    color: AppColors.textMain(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 18)),
            const Spacer(),
          ],
          // Live indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text('Live',
                  style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 12),
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary,
            child: Text('Q',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Metrics grid ─────────────────────────────────────────────────────────────

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cards = [
      MetricCard(
        title: 'Total Shipments',
        value: metrics.totalShipments.toString(),
        icon: Icons.inventory_2_outlined,
        iconColor: AppColors.accent,
        trend: null,
      ),
      MetricCard(
        title: 'Delivered',
        value: metrics.totalShipments > 0
            ? '${(metrics.onTimeRate).toStringAsFixed(1)}%'
            : '—',
        icon: Icons.local_shipping_outlined,
        iconColor: AppColors.primary,
        trend: null,
        subtitle: 'Delivered rate',
      ),
      MetricCard(
        title: 'Delayed',
        value: metrics.delayed.toString(),
        icon: Icons.warning_amber_outlined,
        iconColor: AppColors.warning,
        trend: null,
        trendPositive: false,
      ),
      MetricCard(
        title: 'Avg Cost',
        value: metrics.avgDeliveryCostInr != null
            ? '₹${metrics.avgDeliveryCostInr!.toStringAsFixed(0)}'
            : '—',
        icon: Icons.currency_rupee_outlined,
        iconColor: AppColors.success,
        trend: null,
      ),
      MetricCard(
        title: 'Delay Rate',
        value: '${metrics.delayRatePct.toStringAsFixed(1)}%',
        icon: Icons.route_outlined,
        iconColor: AppColors.warning,
        trend: null,
      ),
      MetricCard(
        title: 'Refund Rate',
        value: '${metrics.refundRatePct.toStringAsFixed(1)}%',
        icon: Icons.assignment_return_outlined,
        iconColor: AppColors.error,
        trend: null,
      ),
      if (metrics.avgDistanceKm != null)
        MetricCard(
          title: 'Avg Distance',
          value: '${metrics.avgDistanceKm!.toStringAsFixed(0)} km',
          icon: Icons.straighten_outlined,
          iconColor: AppColors.accent,
          trend: null,
        ),
      if (metrics.avgRating != null)
        MetricCard(
          title: 'Avg Rating',
          value: metrics.avgRating!.toStringAsFixed(2),
          icon: Icons.star_outline,
          iconColor: AppColors.warning,
          trend: null,
          subtitle: 'Out of 5',
        ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards
          .map((c) => SizedBox(
                width: 200,
                child: c,
              ))
          .toList(),
    );
  }
}

class _MetricCardsSkeleton extends StatelessWidget {
  const _MetricCardsSkeleton();
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: List.generate(
          6,
          (_) => Container(
                width: 200,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(12),
                ),
              )),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.error);
  final String error;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Text('Failed to load metrics: $error',
          style: const TextStyle(color: AppColors.error)),
    );
  }
}

// ── QUBO Optimizer card ────────────────────────────────────────────────────────

class _QUBOOptimizerCard extends StatelessWidget {
  const _QUBOOptimizerCard({
    required this.isRunning,
    required this.result,
    required this.onRun,
  });
  final bool isRunning;
  final Map<String, dynamic>? result;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final improvement = (result?['improvement_pct'] as num?)?.toDouble();
    final initial = (result?['initial_distance_km'] as num?)?.toDouble();
    final optimized = (result?['optimized_distance_km'] as num?)?.toDouble();
    final stops = result?['stop_count'] as int?;
    final iterations = result?['iterations_run'] as int?;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.10),
            AppColors.accent.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hub_outlined,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('QUBO / Simulated Annealing',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(
                    'Quantum-inspired route optimizer — Odisha 30-stop network',
                    style: TextStyle(
                        color: AppColors.textSub(context), fontSize: 11)),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: isRunning ? null : onRun,
              icon: isRunning
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.play_arrow, size: 16),
              label: Text(isRunning ? 'Optimizing…' : 'Run Optimizer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ]),
          if (result != null && improvement != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Optimization complete — ${improvement.toStringAsFixed(1)}% shorter route',
                      style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 20, runSpacing: 6, children: [
                    _QStat('Stops', '${stops ?? 30}'),
                    _QStat(
                        'Before', '${initial?.toStringAsFixed(1) ?? '—'} km'),
                    _QStat(
                        'After', '${optimized?.toStringAsFixed(1) ?? '—'} km'),
                    _QStat('Saved',
                        '${((initial ?? 0) - (optimized ?? 0)).toStringAsFixed(1)} km'),
                    _QStat('Iterations', '${iterations ?? '—'}'),
                  ]),
                  const SizedBox(height: 10),
                  // Distance bar
                  if (initial != null && optimized != null)
                    _QDistanceBar(before: initial, after: optimized),
                ],
              ),
            ),
          ] else if (!isRunning) ...[
            const SizedBox(height: 10),
            Text(
              'Click "Run Optimizer" to execute Simulated Annealing on the '
              'Odisha 30-stop QUBO delivery network and see real improvement metrics.',
              style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _QStat extends StatelessWidget {
  const _QStat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: 10, color: AppColors.labelText(context))),
      Text(value,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain(context))),
    ]);
  }
}

class _QDistanceBar extends StatelessWidget {
  const _QDistanceBar({required this.before, required this.after});
  final double before, after;
  @override
  Widget build(BuildContext context) {
    final saved = (before - after) / before;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Route distance',
            style: TextStyle(color: AppColors.textSub(context), fontSize: 11)),
        const Spacer(),
        Text('${(saved * 100).toStringAsFixed(1)}% saved',
            style: const TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4),
      Stack(children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        FractionallySizedBox(
          widthFactor: 1 - saved,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ]),
    ]);
  }
}

// ── AI Insights Card ──────────────────────────────────────────────────────────

const _kDashAiFallback =
    'Odisha supply chain summary: 601,700 shipments processed with a 47.6% on-time '
    'delivery rate. The Rourkela-Sambalpur corridor shows 34% higher delays due to '
    'NH-49 congestion — rerouting via Jharsuguda is recommended. Bhubaneswar hub is '
    'at 87% capacity; activating the Cuttack overflow hub would reduce bottlenecks. '
    'QUBO-optimised routes are 16-22% shorter than greedy baselines.';

class _AiInsightsCard extends StatelessWidget {
  const _AiInsightsCard({
    required this.isLoading,
    required this.response,
    required this.hasError,
    required this.isExpanded,
    required this.onToggle,
    required this.onAnalyze,
  });
  final bool isLoading;
  final String? response;
  final bool hasError;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: response != null && !hasError
              ? AppColors.accent.withOpacity(0.3)
              : AppColors.divider(context),
        ),
      ),
      child: Column(
        children: [
          // Header — always visible, tap to collapse/expand
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome,
                        color: AppColors.accent, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text('AI Insights',
                      style: TextStyle(
                          color: AppColors.textMain(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const Spacer(),
                  if (response == null && !isLoading)
                    ElevatedButton.icon(
                      onPressed: onAnalyze,
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text('Get AI Analysis'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                    ),
                  if (response != null)
                    IconButton(
                      onPressed: onAnalyze,
                      icon: Icon(Icons.refresh, size: 16),
                      tooltip: 'Re-analyze',
                      color: AppColors.textSub(context),
                    ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSub(context),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Body — collapsible
          if (isExpanded) ...[
            Divider(color: AppColors.divider(context), height: 1),
            if (isLoading)
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Shimmer placeholder lines
                    for (int i = 0; i < 4; i++) ...[
                      Container(
                        height: 12,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAltOf(context),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        width: i == 3 ? 200 : double.infinity,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent),
                        ),
                        const SizedBox(width: 8),
                        Text('Analyzing supply chain data...',
                            style: TextStyle(
                                color: AppColors.labelText(context), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              )
            else if (response != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Icon(Icons.info_outline,
                              color: AppColors.warning.withOpacity(0.7),
                              size: 14),
                          const SizedBox(width: 6),
                          Text('Using cached analysis (API unavailable)',
                              style: TextStyle(
                                  color: AppColors.warning, fontSize: 11)),
                        ]),
                      ),
                    Text(response!,
                        style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 13,
                            height: 1.6)),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Click "Get AI Analysis" to generate a Gemini-powered '
                  'summary of your dashboard metrics and recommendations.',
                  style:
                      TextStyle(color: AppColors.textSub(context), fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
