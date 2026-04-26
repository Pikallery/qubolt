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
  List<Map<String, dynamic>> _cached = [];
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

  // Fetches count AND alerts together so the dialog opens instantly on tap
  Future<void> _poll() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.alertsPending);
      final alerts = List<Map<String, dynamic>>.from(res.data as List? ?? []);
      if (mounted) {
        setState(() {
          _cached = alerts;
          _count = alerts.length;
        });
      }
    } catch (_) {}
  }

  void _showAlerts() {
    final alerts = _cached;
    showDialog(
      context: context,
      builder: (_) => _AlertDialog(
        alerts: alerts,
        onDismiss: (id) async {
          try {
            final dio = ref.read(dioProvider);
            await dio.put(ApiConstants.alertDismiss(id));
          } catch (_) {}
          _poll();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, size: 22),
          color: AppColors.textSecondary,
          tooltip: 'Notifications',
          onPressed: _showAlerts,
        ),
        if (_count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _count > 99 ? '99+' : '$_count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _AlertDialog extends StatefulWidget {
  const _AlertDialog({required this.alerts, required this.onDismiss});
  final List<Map<String, dynamic>> alerts;
  final Future<void> Function(String id) onDismiss;

  @override
  State<_AlertDialog> createState() => _AlertDialogState();
}

class _AlertDialogState extends State<_AlertDialog> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.alerts);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: Row(children: [
        const Icon(Icons.notifications_outlined, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text('Notifications (${_items.length})',
            style: const TextStyle(fontSize: 15)),
      ]),
      content: SizedBox(
        width: 360,
        height: 300,
        child: _items.isEmpty
            ? const Center(
                child: Text('No new notifications',
                    style: TextStyle(color: AppColors.textSecondary)))
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: AppColors.border),
                itemBuilder: (_, i) {
                  final a = _items[i];
                  final title = a['title'] as String? ?? 'Notification';
                  final detail = a['detail'] as String?;
                  final createdAt = a['created_at'] as String? ?? '';
                  final id = a['id'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.notifications,
                        color: AppColors.warning, size: 18),
                    title: Text(title,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detail != null)
                          Text(detail,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                        Text(createdAt,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted)),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      color: AppColors.success,
                      tooltip: 'Dismiss',
                      onPressed: () async {
                        setState(() => _items.removeAt(i));
                        if (id.isNotEmpty) await widget.onDismiss(id);
                        if (_items.isEmpty && context.mounted) {
                          Navigator.pop(context);
                        }
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
    );
  }
}
