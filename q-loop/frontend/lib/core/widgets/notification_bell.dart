import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../constants/api_constants.dart';
import '../constants/app_colors.dart';
import '../network/dio_client.dart';

class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  int _count = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.alertsCount);
      final count = (res.data as Map<String, dynamic>)['count'] as int? ?? 0;
      if (mounted) setState(() => _count = count);
    } catch (_) {}
  }

  Future<void> _showAlerts() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.alertsPending);
      final alerts = List<Map<String, dynamic>>.from(res.data as List? ?? []);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Row(children: [
            Icon(Icons.notifications_outlined, color: AppColors.primary, size: 18),
            SizedBox(width: 8),
            Text('Notifications', style: TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(
            width: 360,
            height: 300,
            child: alerts.isEmpty
                ? const Center(
                    child: Text('No new notifications',
                        style: TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.border),
                    itemBuilder: (_, i) {
                      final a = alerts[i];
                      final payload = a['payload'] as Map<String, dynamic>? ?? {};
                      final msg = payload['message'] as String? ??
                          a['channel'] as String? ?? 'New alert';
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.notifications,
                            color: AppColors.warning, size: 18),
                        title: Text(msg, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(a['created_at'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textMuted)),
                        trailing: IconButton(
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          color: AppColors.success,
                          onPressed: () async {
                            final id = a['id'] as String? ?? '';
                            if (id.isNotEmpty) {
                              try {
                                await dio.put(ApiConstants.alertDismiss(id));
                              } catch (_) {}
                            }
                            if (mounted) Navigator.pop(context);
                            _poll();
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, size: 22),
          color: AppColors.textSecondary,
          tooltip: 'Notifications',
          onPressed: _showAlerts,
        ),
        if (_count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: AppColors.error, shape: BoxShape.circle),
              child: Text('$_count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }
}
