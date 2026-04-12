import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _driversPerformanceProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.driversPerformance);
  return res.data as List<dynamic>;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class DriverAnalyticsScreen extends ConsumerWidget {
  const DriverAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final driversAsync = ref.watch(_driversPerformanceProvider);

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
                  child: driversAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Error: $e',
                        style: const TextStyle(color: AppColors.error)),
                    ),
                    data: (drivers) => SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SummaryRow(drivers: drivers, isMobile: isMobile),
                          const SizedBox(height: 24),
                          Text('All Drivers',
                            style: TextStyle(
                              color: AppColors.surface(context) == AppColors.lightScaffoldBg
                                  ? AppColors.lightTextPrimary : AppColors.textPrimary,
                              fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 12),
                          if (drivers.isEmpty)
                            _EmptyState()
                          else
                            ...drivers.map((d) => _DriverRow(
                              driver: d as Map<String, dynamic>,
                            )),
                        ],
                      ),
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
            icon: Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        Text('Driver Performance', style: TextStyle(
          color: AppColors.surface(context) == AppColors.lightScaffoldBg
              ? AppColors.lightTextPrimary : AppColors.textPrimary,
          fontWeight: FontWeight.w600, fontSize: 18)),
      ]),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.drivers, required this.isMobile});
  final List<dynamic> drivers;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final totalDrivers = drivers.length;
    double avgOnTime = 0;
    double avgRating = 0;
    double totalDistance = 0;

    for (final d in drivers) {
      final driver = d as Map<String, dynamic>;
      avgOnTime += (driver['on_time_pct'] as num?)?.toDouble() ?? 0;
      avgRating += (driver['avg_rating'] as num?)?.toDouble() ?? 0;
      totalDistance += (driver['total_distance_km'] as num?)?.toDouble() ?? 0;
    }
    if (totalDrivers > 0) {
      avgOnTime /= totalDrivers;
      avgRating /= totalDrivers;
    }

    final cards = [
      _SummaryCard(label: 'Total Drivers', value: '$totalDrivers',
          icon: Icons.people, color: AppColors.primary),
      _SummaryCard(label: 'Avg On-Time %', value: '${avgOnTime.toStringAsFixed(1)}%',
          icon: Icons.schedule, color: AppColors.success),
      _SummaryCard(label: 'Avg Rating', value: avgRating.toStringAsFixed(2),
          icon: Icons.star, color: AppColors.warning),
      _SummaryCard(label: 'Total Distance', value: '${totalDistance.toStringAsFixed(0)} km',
          icon: Icons.straighten, color: AppColors.accent),
    ];

    if (isMobile) {
      return Column(
        children: [
          Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
        ],
      );
    }

    return Row(
      children: cards.map((c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: c,
        ),
      )).toList(),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(
                color: AppColors.surface(context) == AppColors.lightScaffoldBg
                    ? AppColors.lightTextPrimary : AppColors.textPrimary,
                fontWeight: FontWeight.w700, fontSize: 18)),
              Text(label, style: TextStyle(
                color: AppColors.labelText(context), fontSize: 11)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DriverRow extends ConsumerWidget {
  const _DriverRow({required this.driver});
  final Map<String, dynamic> driver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = driver['name'] as String? ?? 'Unknown';
    final email = driver['email'] as String? ?? '—';
    final totalShipments = driver['total_shipments'] as int? ?? 0;
    final onTimePct = (driver['on_time_pct'] as num?)?.toDouble() ?? 0;
    final delayed = driver['delayed'] as int? ?? 0;
    final avgRating = (driver['avg_rating'] as num?)?.toDouble() ?? 0;
    final totalDist = (driver['total_distance_km'] as num?)?.toDouble() ?? 0;
    final id = driver['id'] as String? ?? '';

    return GestureDetector(
      onTap: () => _showDriverDetail(context, ref, id, name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.sidebar(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider(context)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: AppColors.primary,
                fontWeight: FontWeight.w700, fontSize: 14),
            )),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(
                  color: AppColors.surface(context) == AppColors.lightScaffoldBg
                      ? AppColors.lightTextPrimary : AppColors.textPrimary,
                  fontWeight: FontWeight.w600, fontSize: 13)),
                Text(email, style: TextStyle(
                  color: AppColors.labelText(context), fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(children: [
              Text('$totalShipments', style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Shipments', style: TextStyle(
                color: AppColors.labelText(context), fontSize: 10)),
            ]),
          ),
          Expanded(
            flex: 1,
            child: Column(children: [
              Text('${onTimePct.toStringAsFixed(1)}%', style: TextStyle(
                color: onTimePct >= 90 ? AppColors.success
                    : onTimePct >= 75 ? AppColors.warning : AppColors.error,
                fontWeight: FontWeight.w600, fontSize: 13)),
              Text('On-Time', style: TextStyle(
                color: AppColors.labelText(context), fontSize: 10)),
            ]),
          ),
          Expanded(
            flex: 1,
            child: Column(children: [
              Text('$delayed', style: TextStyle(
                color: delayed > 0 ? AppColors.error : AppColors.success,
                fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Delayed', style: TextStyle(
                color: AppColors.labelText(context), fontSize: 10)),
            ]),
          ),
          Expanded(
            flex: 1,
            child: Column(children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: AppColors.warning, size: 12),
                  const SizedBox(width: 2),
                  Text(avgRating.toStringAsFixed(1), style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
              Text('Rating', style: TextStyle(
                color: AppColors.labelText(context), fontSize: 10)),
            ]),
          ),
          Expanded(
            flex: 1,
            child: Column(children: [
              Text('${totalDist.toStringAsFixed(0)} km', style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 12)),
              Text('Distance', style: TextStyle(
                color: AppColors.labelText(context), fontSize: 10)),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
        ]),
      ),
    );
  }

  Future<void> _showDriverDetail(
      BuildContext context, WidgetRef ref, String id, String name) async {
    if (id.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.driverHistory(id));
      final history = (res.data as List?) ?? [];
      Navigator.of(context).pop(); // dismiss loading
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.sidebar(context),
          title: Row(children: [
            Icon(Icons.person, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 480,
            height: 360,
            child: history.isEmpty
              ? Center(child: Text('No recent shipment history',
                  style: TextStyle(color: AppColors.labelText(context), fontSize: 13)))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => Divider(
                    color: AppColors.divider(context), height: 1),
                  itemBuilder: (_, i) {
                    final item = history[i] as Map<String, dynamic>;
                    final shipId = item['shipment_id'] as String? ?? '—';
                    final status = item['status'] as String? ?? 'unknown';
                    final date = item['delivered_at'] as String? ??
                        item['created_at'] as String? ?? '—';
                    final isDelayed = item['is_delayed'] as bool? ?? false;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.statusColor(status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            shipId.length > 20 ? '${shipId.substring(0, 20)}...' : shipId,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        _StatusChip(status),
                        const SizedBox(width: 8),
                        if (isDelayed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('DELAYED',
                              style: TextStyle(fontSize: 9, color: AppColors.warning,
                                fontWeight: FontWeight.w700)),
                          ),
                        const SizedBox(width: 8),
                        Text(date.length > 10 ? date.substring(0, 10) : date,
                          style: TextStyle(
                            color: AppColors.labelText(context), fontSize: 11)),
                      ]),
                    );
                  },
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to load driver history: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = AppColors.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(status.toUpperCase(),
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
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
          Icon(Icons.people_outline, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('No driver data yet',
            style: TextStyle(color: AppColors.textSub(context), fontSize: 15)),
          const SizedBox(height: 6),
          Text('Driver performance data will appear here once deliveries are tracked.',
            style: TextStyle(color: AppColors.labelText(context), fontSize: 13),
            textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
