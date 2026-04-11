import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _routesProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.routes);
  return res.data as List<dynamic>;
});

final _buildingRouteProvider = StateProvider<bool>((ref) => false);
final _buildResultProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

// ── Screen ────────────────────────────────────────────────────────────────────

class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final routes = ref.watch(_routesProvider);
    final isBuilding = ref.watch(_buildingRouteProvider);
    final buildResult = ref.watch(_buildResultProvider);

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
                        // ── Optimizer card ───────────────────────────────────
                        _OptimizerCard(
                          isBuilding: isBuilding,
                          buildResult: buildResult,
                          onBuild: () => _buildRoute(context, ref),
                        ),
                        const SizedBox(height: 24),
                        // ── Route list ───────────────────────────────────────
                        Text('Saved Routes',
                            style: TextStyle(
                                color: AppColors.surface(context) ==
                                        AppColors.lightScaffoldBg
                                    ? AppColors.lightTextPrimary
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        const SizedBox(height: 12),
                        routes.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('Error: $e',
                              style: const TextStyle(color: AppColors.error)),
                          data: (list) => list.isEmpty
                              ? _EmptyState()
                              : Column(
                                  children: list
                                      .map((r) => _RouteCard(
                                          route: r as Map<String, dynamic>,
                                          ref: ref))
                                      .toList(),
                                ),
                        ),
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

  Future<void> _buildRoute(BuildContext context, WidgetRef ref) async {
    ref.read(_buildingRouteProvider.notifier).state = true;
    ref.read(_buildResultProvider.notifier).state = null;
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.routeBuildFromPoints,
          data: {'limit': 30, 'max_iterations': 15000});
      ref.read(_buildResultProvider.notifier).state =
          res.data as Map<String, dynamic>;
      ref.invalidate(_routesProvider);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      ref.read(_buildingRouteProvider.notifier).state = false;
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
        Text('Routes & Optimizer',
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

class _OptimizerCard extends StatelessWidget {
  const _OptimizerCard({
    required this.isBuilding,
    required this.buildResult,
    required this.onBuild,
  });
  final bool isBuilding;
  final Map<String, dynamic>? buildResult;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.route, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Simulated Annealing Optimizer',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: isBuilding ? null : onBuild,
              icon: isBuilding
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.play_arrow, size: 16),
              label:
                  Text(isBuilding ? 'Optimizing…' : 'Build & Optimize Route'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
              'Builds a route from 30 Rourkela delivery points and runs SA to minimize total distance.',
              style:
                  TextStyle(color: AppColors.labelText(context), fontSize: 13)),
          if (buildResult != null) ...[
            const SizedBox(height: 16),
            _OptimizationResult(buildResult!),
          ],
        ],
      ),
    );
  }
}

class _OptimizationResult extends StatelessWidget {
  const _OptimizationResult(this.r);
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final improvement = (r['improvement_pct'] as num?)?.toDouble() ?? 0.0;
    final initial = (r['initial_distance_km'] as num?)?.toDouble() ?? 0.0;
    final optimized = (r['optimized_distance_km'] as num?)?.toDouble() ?? 0.0;
    final stops = r['stop_count'] as int? ?? 0;
    final iterations = r['iterations_run'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 16),
            const SizedBox(width: 6),
            Text(
                'Route optimized — ${improvement.toStringAsFixed(1)}% improvement',
                style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _Stat('Stops', '$stops'),
            _Stat('Initial', '${initial.toStringAsFixed(1)} km'),
            _Stat('Optimized', '${optimized.toStringAsFixed(1)} km'),
            _Stat('Saved', '${(initial - optimized).toStringAsFixed(1)} km'),
            _Stat('Iterations', '$iterations'),
          ]),
          const SizedBox(height: 10),
          // Show ordered stops
          ...(r['ordered_stops'] as List? ?? []).take(8).map((s) {
            final stop = s as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                      child: Text('${stop['sequence']}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 8),
                Text('${stop['area'] ?? '—'} (${stop['pincode'] ?? '—'})',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Text(
                    '${(stop['latitude'] as num).toStringAsFixed(4)}, '
                    '${(stop['longitude'] as num).toStringAsFixed(4)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.labelText(context),
                        fontFamily: 'monospace')),
              ]),
            );
          }),
          if ((r['ordered_stops'] as List? ?? []).length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '… and ${(r['ordered_stops'] as List).length - 8} more stops',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.labelText(context))),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: 11, color: AppColors.labelText(context))),
      Text(value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.ref});
  final Map<String, dynamic> route;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final status = route['status'] as String? ?? 'draft';
    final distKm = (route['total_distance_km'] as num?)?.toDouble();
    final saIter = route['sa_iterations'] as int?;
    final saFinal = (route['sa_final_cost'] as num?)?.toDouble();
    final id = route['id'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Row(children: [
        const Icon(Icons.route_outlined, color: AppColors.primary, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(id.length > 20 ? '${id.substring(0, 20)}…' : id,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 16, children: [
              if (distKm != null)
                Text('${distKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              if (saIter != null)
                Text('$saIter iterations',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              if (saFinal != null)
                Text('SA cost: ${saFinal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ]),
        ),
        _StatusChip(status),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.auto_awesome, size: 16),
          tooltip: 'AI Explain',
          color: AppColors.accent,
          onPressed: () => _aiExplain(context, ref, id),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 16),
          tooltip: 'Re-optimize',
          color: AppColors.primary,
          onPressed: () => _reOptimize(context, ref, id),
        ),
      ]),
    );
  }

  Future<void> _aiExplain(
      BuildContext context, WidgetRef ref, String id) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.aiRouteExplain(id));
      final data = res.data as Map<String, dynamic>;
      final explanation = (data['explanation'] as String?) ??
          (data['insight'] as String?) ??
          'No explanation available.';
      Navigator.of(context).pop(); // dismiss loading
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Row(children: [
            Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
            SizedBox(width: 8),
            Text('AI Route Analysis', style: TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Text(explanation,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.6)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('AI analysis unavailable: $e'),
        backgroundColor: AppColors.warning,
      ));
    }
  }

  Future<void> _reOptimize(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.routeOptimizeSync(id), data: {
        'initial_temp': 5000,
        'cooling_rate': 0.999,
        'max_iterations': 20000
      });
      final pct = (res.data['improvement_pct'] as num?)?.toDouble() ?? 0.0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Re-optimized: ${pct.toStringAsFixed(1)}% improvement'),
        backgroundColor: AppColors.success,
      ));
      ref.invalidate(_routesProvider);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'active'
        ? AppColors.success
        : status == 'completed'
            ? AppColors.primary
            : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          const Icon(Icons.route_outlined,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('No routes yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
              'Click "Build & Optimize Route" above to create your first optimized route.',
              style:
                  TextStyle(color: AppColors.labelText(context), fontSize: 13),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
