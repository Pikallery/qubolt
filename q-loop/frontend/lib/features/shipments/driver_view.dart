import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart'
    show Dio, FormData, MultipartFile, Options, ResponseType;
import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/widgets/api_error_widget.dart';
import '../auth/domain/auth_provider.dart';
import '../comms/chat_screen.dart';
import '../comms/comms_provider.dart';

// ── Session earnings provider ─────────────────────────────────────────────────

/// Tracks deliveries completed this session so the Earnings tab updates live.
final _sessionDeliveriesProvider =
    StateProvider<List<Map<String, dynamic>>>((ref) => []);

double _calcEarnings(Map<String, dynamic> s) {
  final dist = (s['distance_km'] as num?)?.toDouble() ?? 15.0;
  final priority = (s['priority'] as String?)?.toLowerCase() ?? 'medium';
  double base = dist * 8; // ₹8 per km
  if (priority == 'high') base *= 1.5;
  if (priority == 'low') base *= 0.85;
  return base;
}

/// Driver view — Rapido-style with 4 tabs:
///   1. My Deliveries  — pending shipment list + QR codes
///   2. Route Map      — live animated flutter_map of today's route
///   3. Earnings       — daily/weekly earnings ledger
///   4. Contact        — call/SMS Hub and Manager
class DriverView extends ConsumerStatefulWidget {
  const DriverView({super.key});

  @override
  ConsumerState<DriverView> createState() => _DriverViewState();
}

class _DriverViewState extends ConsumerState<DriverView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _alertCount = 0;
  Timer? _alertTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _pollAlerts();
    _alertTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _pollAlerts());
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _pollAlerts() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.alertsCount);
      final count = (res.data as Map<String, dynamic>)['count'] as int? ?? 0;
      if (mounted) setState(() => _alertCount = count);
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
          title: const Text('Task Alerts', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 360,
            height: 300,
            child: alerts.isEmpty
                ? const Center(
                    child: Text('No pending alerts',
                        style: TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppColors.border),
                    itemBuilder: (_, i) {
                      final a = alerts[i];
                      final payload =
                          a['payload'] as Map<String, dynamic>? ?? {};
                      final msg = payload['message'] as String? ??
                          a['channel'] as String? ??
                          'New alert';
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.notifications,
                            color: AppColors.warning, size: 18),
                        title: Text(msg, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(a['created_at'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textMuted)),
                        trailing: IconButton(
                          icon:
                              const Icon(Icons.check_circle_outline, size: 18),
                          color: AppColors.success,
                          onPressed: () async {
                            final id = a['id'] as String? ?? '';
                            if (id.isNotEmpty) {
                              try {
                                await dio.put(ApiConstants.alertDismiss(id));
                              } catch (_) {}
                            }
                            Navigator.pop(context);
                            _pollAlerts();
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

  Future<void> _launchNavigation(Map<String, dynamic> shipment) async {
    final region = shipment['region'] as String? ?? 'Bhubaneswar';
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent('$region, Odisha')}&travelmode=driving';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _captureDeliveryPhoto(Map<String, dynamic> shipment) async {
    final shipmentId = shipment['id'] as String? ?? '';
    if (shipmentId.isEmpty) return;
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    try {
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'shipment_id': shipmentId,
        'photo_type': 'delivery',
        'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
      });
      await dio.post(ApiConstants.photoUpload, data: formData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo uploaded successfully'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final driverId =
        'DRV-OD-TRUCK-${(auth.userId ?? '').hashCode.abs() % 9000 + 1000}';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.sidebarBg,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.local_shipping_outlined,
                  color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('Driver Hub',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ]),
            Text(driverId,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace')),
          ],
        ),
        actions: [
          // Alerts bell
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, size: 22),
                color: AppColors.textSecondary,
                onPressed: _showAlerts,
              ),
              if (_alertCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: AppColors.error, shape: BoxShape.circle),
                    child: Text('$_alertCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
          // Live status indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withOpacity(0.4)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              _PulseDot(),
              SizedBox(width: 5),
              Text('On Duty',
                  style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          // Settings / logout menu
          PopupMenuButton<String>(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined,
                color: AppColors.textSecondary, size: 20),
            color: AppColors.cardBg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.border)),
            onSelected: (value) async {
              if (value == 'logout') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.cardBg,
                    title: const Text('Sign out?',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 16)),
                    content: const Text(
                        'You will be returned to the login screen.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out',
                              style: TextStyle(color: AppColors.error))),
                    ],
                  ),
                );
                if (confirm != true) return;
                await ref.read(authNotifierProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 16, color: AppColors.error),
                  SizedBox(width: 10),
                  Text('Sign Out',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Deliveries'),
            Tab(text: 'Route Map'),
            Tab(text: 'Earnings'),
            Tab(text: 'Contact'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DeliveriesTab(),
          _RouteMapTab(),
          _EarningsTab(),
          _DriverContactTab(),
        ],
      ),
    );
  }
}

// ── Tab 1: Deliveries ─────────────────────────────────────────────────────────

class _DeliveriesTab extends ConsumerStatefulWidget {
  const _DeliveriesTab();

  @override
  ConsumerState<_DeliveriesTab> createState() => _DeliveriesTabState();
}

class _DeliveriesTabState extends ConsumerState<_DeliveriesTab> {
  List<Map<String, dynamic>> _shipments = [];
  bool _loading = true;
  String? _error;
  final _acceptedOrders = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final userId = ref.read(authNotifierProvider).userId;
      final res = await dio.get(ApiConstants.shipments, queryParameters: {
        'page_size': 50,
        if (userId != null) 'assigned_driver_id': userId,
      });
      setState(() {
        _shipments = List<Map<String, dynamic>>.from(res.data['items'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showQR(String id) {
    showDialog(context: context, builder: (_) => _QRDialog(shipmentId: id));
  }

  Future<void> _launchNavigation(Map<String, dynamic> shipment) async {
    final region = shipment['region'] as String? ?? 'Bhubaneswar';
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent('$region, Odisha')}&travelmode=driving';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _captureDeliveryPhoto(Map<String, dynamic> shipment) async {
    final shipmentId = shipment['id'] as String? ?? '';
    if (shipmentId.isEmpty) return;
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    try {
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'shipment_id': shipmentId,
        'photo_type': 'delivery',
        'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
      });
      await dio.post(ApiConstants.photoUpload, data: formData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo uploaded successfully'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return ApiErrorWidget(error: _error!, onRetry: _load);
    }
    if (_shipments.isEmpty) {
      return _EmptyDeliveries();
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: Column(
        children: [
          // Summary strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.sidebarBg,
            child: Row(children: [
              _MiniStat('Assigned', '${_shipments.length}', AppColors.accent),
              _MiniStat(
                  'Pending',
                  '${_shipments.where((s) => s['status'] == 'pending').length}',
                  AppColors.warning),
              _MiniStat(
                  'Delivered',
                  '${_shipments.where((s) => s['status'] == 'delivered').length}',
                  AppColors.success),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _shipments.length,
              itemBuilder: (_, i) {
                final s = _shipments[i];
                final id = s['id'] as String? ?? '';
                final auth = ref.read(authNotifierProvider);
                final driverId =
                    'DRV-OD-TRUCK-${(auth.userId ?? '').hashCode.abs() % 9000 + 1000}';
                final isAccepted = _acceptedOrders.contains(id);
                final status = s['status'] as String? ?? 'pending';
                final isPending =
                    status == 'pending' || status == 'assigned';
                return _ShipmentCard(
                  shipment: s,
                  isAccepted: isAccepted,
                  limitReached: isPending && !isAccepted && _limitReached(driverId),
                  onShowQR: () => _showQR(id),
                  onMarkDelivered: () => _markArrivedAtHub(id),
                  onNavigate: () => _launchNavigation(s),
                  onPhoto: () => _captureDeliveryPhoto(s),
                  onAccept: isPending && !isAccepted ? () => _acceptOrder(id) : null,
                  onCancel: isAccepted ? () => _cancelOrder(id) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markArrivedAtHub(String id) async {
    try {
      final dio = ref.read(dioProvider);
      // Post a driver_arrived event — hub operator sees it in their transit tab
      // and clicks "Confirm Arrival" to finalise as delivered.
      await dio.post(ApiConstants.shipmentEvents(id), data: {
        'event_type': 'driver_arrived',
        'note': 'Driver has arrived at hub with package',
      });
      // Add to session earnings so the Earnings tab updates live
      final shipment = _shipments.firstWhere(
        (s) => s['id'] == id,
        orElse: () => {},
      );
      if (shipment.isNotEmpty) {
        ref.read(_sessionDeliveriesProvider.notifier).state = [
          ...ref.read(_sessionDeliveriesProvider),
          shipment,
        ];
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hub notified — awaiting confirmation'),
          backgroundColor: AppColors.success,
        ));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _acceptOrder(String id) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(ApiConstants.shipment(id), data: {'status': 'in_transit'});
      setState(() => _acceptedOrders.add(id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Accept failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _cancelOrder(String id) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(ApiConstants.shipment(id), data: {'status': 'pending'});
      setState(() => _acceptedOrders.remove(id));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cancel failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  /// Returns true if this driver has reached the order limit for their vehicle type.
  bool _limitReached(String driverId) {
    final id = driverId.toUpperCase();
    final acceptedCount = _acceptedOrders.length;
    if (id.contains('TRUCK') || id.contains('VAN')) {
      // max 1 long-distance accepted at a time
      return acceptedCount >= 1;
    }
    if (id.contains('BIKE')) {
      // max 2 long-distance
      return acceptedCount >= 2;
    }
    return false;
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w700)),
        Text(label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ]),
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.shipment,
    required this.onShowQR,
    required this.onMarkDelivered,
    this.onNavigate,
    this.onPhoto,
    this.onAccept,
    this.onCancel,
    this.isAccepted = false,
    this.limitReached = false,
  });
  final Map<String, dynamic> shipment;
  final VoidCallback onShowQR;
  final VoidCallback onMarkDelivered;
  final VoidCallback? onNavigate;
  final VoidCallback? onPhoto;
  final VoidCallback? onAccept;
  final VoidCallback? onCancel;
  final bool isAccepted;
  final bool limitReached;

  String _estimateEarnings(Map<String, dynamic> s) {
    final dist = (s['distance_km'] as num?)?.toDouble() ?? 15.0;
    final priority = (s['priority'] as String?)?.toLowerCase() ?? 'medium';
    double base = dist * 8; // Rs 8 per km base rate
    if (priority == 'high') base *= 1.5;
    if (priority == 'low') base *= 0.85;
    return base.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final status = shipment['status'] ?? 'pending';
    final priority = shipment['priority'] ?? 'medium';
    final priorityColors = {
      'high': AppColors.error,
      'medium': AppColors.warning,
      'low': AppColors.success,
    };
    final priorityColor =
        priorityColors[priority.toLowerCase()] ?? AppColors.textMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                shipment['external_id'] ??
                    shipment['id']?.toString().substring(0, 8) ??
                    '—',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: priorityColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(priority.toUpperCase(),
                  style: TextStyle(
                      color: priorityColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Hub drop-off destination banner
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.warehouse_outlined,
                size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            const Text('Drop at Hub: ',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 11)),
            Expanded(
              child: Text(
                '${shipment['region'] ?? 'Bhubaneswar'} Regional Hub',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
        _InfoRow(Icons.category_outlined,
            shipment['package_type']?.toString() ?? 'General'),
        const SizedBox(height: 3),
        _InfoRow(Icons.map_outlined,
            shipment['region']?.toString() ?? 'Unknown region'),
        const SizedBox(height: 3),
        _InfoRow(Icons.directions_car_outlined,
            shipment['vehicle_type']?.toString() ?? 'Any vehicle'),
        const SizedBox(height: 12),
        // Earnings estimate
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.success.withOpacity(0.12),
                AppColors.primary.withOpacity(0.08)
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.success.withOpacity(0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.currency_rupee,
                size: 14, color: AppColors.success),
            const SizedBox(width: 4),
            Text(
              'Earn: \u20B9${_estimateEarnings(shipment)}',
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${shipment['distance_km'] ?? '~15'} km',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ]),
        ),
        // Accept / Cancel / Limit row
        if (onAccept != null || onCancel != null || limitReached || isAccepted) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (limitReached)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.block, size: 12, color: AppColors.warning),
                  SizedBox(width: 5),
                  Text('Order Limit Reached',
                      style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            if (onAccept != null && !limitReached)
              ElevatedButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.check_circle_outline, size: 14),
                label: const Text('Accept', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ),
            if (onCancel != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 14),
                label: const Text('Cancel', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
            if (isAccepted && onCancel == null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, size: 12, color: AppColors.success),
                  SizedBox(width: 4),
                  Text('Accepted',
                      style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ]),
        ],
        const SizedBox(height: 4),
        Row(children: [
          _StatusChip(status),
          const Spacer(),
          // Navigate button
          if (onNavigate != null)
            IconButton(
              icon: const Icon(Icons.navigation_outlined, size: 18),
              color: AppColors.accent,
              tooltip: 'Navigate',
              onPressed: onNavigate,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          if (onNavigate != null) const SizedBox(width: 4),
          // Photo proof button
          if (onPhoto != null)
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              color: AppColors.primary,
              tooltip: 'Photo proof',
              onPressed: onPhoto,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          if (onPhoto != null) const SizedBox(width: 4),
          if (status == 'in_transit') ...[
            OutlinedButton.icon(
              onPressed: onMarkDelivered,
              icon: const Icon(Icons.warehouse_rounded, size: 14),
              label: const Text('Arrived at Hub',
                  style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: onShowQR,
            icon: const Icon(Icons.qr_code, size: 14),
            label: const Text('QR Code', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Tab 2: Route Map ──────────────────────────────────────────────────────────

// Region → LatLng lookup
const _regionCoords = {
  'Bhubaneswar': LatLng(20.2961, 85.8315),
  'Cuttack': LatLng(20.4625, 85.8830),
  'Rourkela': LatLng(22.2270, 84.8536),
  'Sambalpur': LatLng(21.4669, 83.9717),
  'Berhampur': LatLng(19.3150, 84.7941),
  'Balasore': LatLng(21.4942, 86.9355),
  'Puri': LatLng(19.8106, 85.8315),
  'Angul': LatLng(20.8380, 85.1010),
  'Koraput': LatLng(18.8135, 82.7123),
};

const _kHubOrigin = LatLng(20.2961, 85.8315); // Bhubaneswar HQ

class _RouteMapTab extends ConsumerStatefulWidget {
  const _RouteMapTab();

  @override
  ConsumerState<_RouteMapTab> createState() => _RouteMapTabState();
}

class _RouteMapTabState extends ConsumerState<_RouteMapTab> {
  Timer? _locationTimer;
  Timer? _refreshTimer;
  bool _locationSharing = false;
  bool _tollFree = false;
  String? _selectedOrderId;
  List<LatLng>? _routePoints; // road-following polyline from Mapbox Directions
  bool _routeLoading = false;

  List<Map<String, dynamic>> _acceptedShipments = [];

  @override
  void initState() {
    super.initState();
    _startLocationSharing();
    _loadAccepted();
    // Poll for newly-assigned orders every 30 s so map auto-updates
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadAccepted());
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAccepted() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/shipments',
          queryParameters: {'status': 'in_transit', 'page_size': 20});
      if (!mounted) return;
      final items =
          List<Map<String, dynamic>>.from(res.data['items'] ?? []);
      final prevId = _selectedOrderId;
      setState(() {
        _acceptedShipments = items;
        if (items.isNotEmpty &&
            (prevId == null ||
                !items.any((s) => s['id'] == prevId))) {
          _selectedOrderId = items.first['id'] as String?;
        }
      });
      // Fetch road route whenever the selected order changes
      if (_selectedOrderId != prevId || _routePoints == null) {
        final sel = items.isEmpty
            ? null
            : items.firstWhere(
                (s) => s['id'] == _selectedOrderId,
                orElse: () => items.first,
              );
        if (sel != null) {
          final region = sel['region'] as String? ?? 'Cuttack';
          final dest =
              _regionCoords[region] ?? const LatLng(20.4625, 85.8830);
          _fetchRoute(_kHubOrigin, dest);
        }
      }
    } catch (_) {}
  }

  /// Fetch a road-following polyline from the Mapbox Directions API.
  Future<void> _fetchRoute(LatLng origin, LatLng dest) async {
    if (_routeLoading) return;
    setState(() => _routeLoading = true);
    try {
      final mapboxDio = Dio();
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '${origin.longitude},${origin.latitude};'
          '${dest.longitude},${dest.latitude}'
          '?geometries=geojson&overview=full'
          '&access_token=${ApiConstants.mapboxToken}';
      final response = await mapboxDio.get(url);
      final data = response.data as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final coords =
            (routes[0]['geometry']['coordinates'] as List)
                .map((c) => LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ))
                .toList();
        if (mounted) setState(() => _routePoints = coords);
      }
    } catch (_) {
      // Fall back to straight line — no crash
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  Future<void> _postLocation() async {
    const lat = 20.4625;
    const lon = 85.8830;
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiConstants.commsLocation, data: {
        'lat': lat,
        'lon': lon,
        'speed_kmh': 42.0,
        'status': 'en_route',
      });
      if (mounted && !_locationSharing) {
        setState(() => _locationSharing = true);
      }
    } catch (_) {}
  }

  void _startLocationSharing() {
    _postLocation();
    _locationTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _postLocation());
  }

  /// Fallback straight-line route when Mapbox is unavailable.
  List<LatLng> _buildFallbackRoute(LatLng dest) {
    final midLat = (_kHubOrigin.latitude + dest.latitude) / 2;
    final midLon = (_kHubOrigin.longitude + dest.longitude) / 2;
    return [_kHubOrigin, LatLng(midLat, midLon), dest];
  }

  /// Euclidean-degree approximation → km (sufficient for display at ~20°N)
  double _distKm(LatLng a, LatLng b) {
    final dlat = (b.latitude - a.latitude).abs();
    final dlon = (b.longitude - a.longitude).abs();
    // 1 deg lat ≈ 111 km, 1 deg lon ≈ 88 km at ~20°N
    return math.sqrt((dlat * 111) * (dlat * 111) + (dlon * 88) * (dlon * 88));
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? selected = _acceptedShipments.isEmpty
        ? null
        : _acceptedShipments.firstWhere(
            (s) => s['id'] == _selectedOrderId,
            orElse: () => _acceptedShipments.first,
          );

    final region = selected?['region'] as String? ?? 'Cuttack';
    final dest = _regionCoords[region] ?? const LatLng(20.4625, 85.8830);
    final route = _routePoints ?? _buildFallbackRoute(dest);
    final distKm = _distKm(_kHubOrigin, dest);
    final etaMin = (distKm / 50 * 60).round(); // assume 50 km/h avg

    // Map center between hub and dest
    final centerLat = (_kHubOrigin.latitude + dest.latitude) / 2;
    final centerLon = (_kHubOrigin.longitude + dest.longitude) / 2;

    return Column(
      children: [
        // ── Top stats strip ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.sidebarBg,
          child: Row(children: [
            Expanded(
                child: _RouteStatBox(
                    'Distance',
                    '${distKm.toStringAsFixed(1)} km',
                    Icons.straighten)),
            Expanded(
                child: _RouteStatBox(
                    'ETA', '$etaMin min', Icons.access_time)),
            Expanded(
                child: _RouteStatBox(
                    'Orders',
                    '${_acceptedShipments.length}',
                    Icons.local_shipping_outlined)),
            // Location sharing indicator
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (_locationSharing
                        ? AppColors.success
                        : AppColors.textMuted)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (_locationSharing
                            ? AppColors.success
                            : AppColors.textMuted)
                        .withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _locationSharing
                      ? Icons.location_on
                      : Icons.location_off,
                  size: 12,
                  color: _locationSharing
                      ? AppColors.success
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  _locationSharing ? 'Live' : 'Off',
                  style: TextStyle(
                      fontSize: 10,
                      color: _locationSharing
                          ? AppColors.success
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ]),
        ),

        // ── Order selector + Toll-free toggle ─────────────────────────────
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.cardBg,
          child: Row(children: [
            const Icon(Icons.route, color: AppColors.primary, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: _acceptedShipments.isEmpty
                  ? Text('No accepted orders — accept orders in Deliveries tab',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11))
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedOrderId ??
                            _acceptedShipments.first['id'] as String?,
                        dropdownColor: AppColors.cardBg,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 12),
                        isExpanded: true,
                        items: _acceptedShipments.map((s) {
                          final label = s['external_id'] as String? ??
                              (s['id'] as String?)
                                  ?.substring(0, 10) ??
                              '—';
                          final reg =
                              s['region'] as String? ?? 'Unknown';
                          return DropdownMenuItem<String>(
                            value: s['id'] as String?,
                            child: Text('$label → $reg',
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedOrderId = v;
                            _routePoints = null; // clear stale route
                          });
                          final sel = _acceptedShipments.firstWhere(
                              (s) => s['id'] == v,
                              orElse: () => _acceptedShipments.first);
                          final r = sel['region'] as String? ?? 'Cuttack';
                          final d = _regionCoords[r] ??
                              const LatLng(20.4625, 85.8830);
                          _fetchRoute(_kHubOrigin, d);
                        },
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Toll-Free',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _tollFree = !_tollFree),
                child: Container(
                  width: 36,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _tollFree
                        ? AppColors.primary
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Align(
                    alignment: _tollFree
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 16,
                      height: 16,
                      margin:
                          const EdgeInsets.symmetric(horizontal: 2),
                      decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),

        // ── Map ────────────────────────────────────────────────────────────
        Expanded(
          child: Container(
            color: const Color(0xFF0A1628),
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(centerLat, centerLon),
                    initialZoom: 7.5,
                    interactionOptions:
                        const InteractionOptions(
                            flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}?access_token=${ApiConstants.mapboxToken}',
                      userAgentPackageName: 'com.qloop.app',
                      tileSize: 512,
                      zoomOffset: -1,
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          color: _tollFree
                              ? AppColors.success
                              : AppColors.ghostRouteSolid,
                          strokeWidth: 3.5,
                          pattern: _tollFree
                              ? const StrokePattern.solid()
                              : const StrokePattern.solid(),
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Hub marker
                        Marker(
                          point: _kHubOrigin,
                          width: 34,
                          height: 34,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.warehouse,
                                color: Colors.white, size: 16),
                          ),
                        ),
                        // Destination marker
                        Marker(
                          point: dest,
                          width: 34,
                          height: 34,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent
                                      .withValues(alpha: 0.5),
                                  blurRadius: 10,
                                )
                              ],
                            ),
                            child: const Icon(Icons.flag,
                                color: Colors.white, size: 16),
                          ),
                        ),
                        // Driver (hub position for demo)
                        Marker(
                          point: _kHubOrigin,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.success
                                      .withValues(alpha: 0.6),
                                  blurRadius: 12,
                                )
                              ],
                            ),
                            child: const Icon(Icons.local_shipping,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Distance / ETA info card at top of map
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      if (_routeLoading)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary),
                        )
                      else
                        const Icon(Icons.route,
                            color: AppColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Bhubaneswar Hub → $region Regional Hub',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_routePoints != null)
                              const Text('Road route',
                                  style: TextStyle(
                                      color: AppColors.success,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600))
                            else if (!_routeLoading)
                              const Text('Straight-line fallback',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 9)),
                          ],
                        ),
                      ),
                      Text(
                        '${distKm.toStringAsFixed(1)} km  •  $etaMin min',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11),
                      ),
                      if (_tollFree) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('TOLL-FREE',
                              style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ]),
                  ),
                ),

                // Legend
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _MapLegend(
                            color: AppColors.primary,
                            label: 'Origin Hub (BBW)'),
                        const SizedBox(height: 3),
                        _MapLegend(
                            color: AppColors.accent,
                            label: '$region Regional Hub'),
                        const SizedBox(height: 3),
                        const _MapLegend(
                            color: AppColors.success,
                            label: 'Your Location'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteStatBox extends StatelessWidget {
  const _RouteStatBox(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: AppColors.primary, size: 16),
      const SizedBox(height: 3),
      Text(value,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700)),
      Text(label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ]);
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
    ]);
  }
}

// ── Tab 3: Earnings ───────────────────────────────────────────────────────────

class _EarningsTab extends ConsumerStatefulWidget {
  const _EarningsTab();

  @override
  ConsumerState<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends ConsumerState<_EarningsTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.driverMyEarnings);
      if (mounted) setState(() { _data = res.data as Map<String, dynamic>; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _txRow({
    required String date,
    required String desc,
    required double amount,
    required bool isIncome,
    bool isNew = false,
  }) {
    final color = isIncome ? AppColors.success : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isNew ? AppColors.success.withValues(alpha: 0.06) : AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isNew ? AppColors.success.withValues(alpha: 0.3) : AppColors.border,
        ),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), shape: BoxShape.circle,
          ),
          child: Icon(isIncome ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(desc, style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              if (isNew)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(4)),
                  child: const Text('NEW', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w800)),
                ),
            ]),
            Text(date, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        ),
        Text(
          '${isIncome ? '+' : '-'}₹${amount.toStringAsFixed(0)}',
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionDeliveries = ref.watch(_sessionDeliveriesProvider);
    final sessionTotal = sessionDeliveries.fold(0.0, (sum, s) => sum + _calcEarnings(s));

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final apiToday = (_data?['today'] as num?)?.toDouble() ?? 0.0;
    final apiWeek  = (_data?['this_week'] as num?)?.toDouble() ?? 0.0;
    final apiPending = (_data?['pending_payout'] as num?)?.toDouble() ?? 0.0;
    final apiTxns = (_data?['transactions'] as List?) ?? [];

    final totalWeek    = apiWeek + sessionTotal;
    final todayEarning = apiToday + sessionTotal;
    final pendingPayout = (apiPending - sessionTotal).clamp(0.0, double.infinity);

    final now = DateTime.now();
    final timeStamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Summary card ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.accent.withValues(alpha: 0.1)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                const Text('This Week', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text('₹${totalWeek.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.primary, fontSize: 36, fontWeight: FontWeight.w800)),
                if (sessionTotal > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '+₹${sessionTotal.toStringAsFixed(0)} from ${sessionDeliveries.length} new deliver${sessionDeliveries.length == 1 ? 'y' : 'ies'} today',
                      style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _EarningsStat('Today', '₹${todayEarning.toStringAsFixed(0)}', AppColors.success)),
                  Container(width: 1, height: 40, color: AppColors.border),
                  Expanded(child: _EarningsStat('Pending Payout', '₹${pendingPayout.toStringAsFixed(0)}', AppColors.warning)),
                ]),
              ]),
            ),

            const SizedBox(height: 20),
            const Text('Transaction History',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),

            // Session deliveries (newest, not yet in DB)
            ...sessionDeliveries.reversed.map((s) => _txRow(
              date: 'Today $timeStamp',
              desc: s['external_id'] as String? ?? (s['id'] as String?)?.substring(0, 10) ?? 'PKG',
              amount: _calcEarnings(s),
              isIncome: true,
              isNew: true,
            )),

            // Real historical transactions from DB
            if (apiTxns.isEmpty && sessionDeliveries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('No deliveries yet', style: TextStyle(color: AppColors.textMuted))),
              )
            else
              ...apiTxns.map((t) {
                final tx = t as Map<String, dynamic>;
                return _txRow(
                  date: tx['date'] as String? ?? '',
                  desc: tx['desc'] as String? ?? '',
                  amount: (tx['amount'] as num?)?.toDouble() ?? 0.0,
                  isIncome: tx['is_income'] as bool? ?? true,
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _EarningsStat extends StatelessWidget {
  const _EarningsStat(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: color, fontSize: 16, fontWeight: FontWeight.w700)),
    ]);
  }
}

// ── Tab 4: Contact ────────────────────────────────────────────────────────────

class _DriverContactTab extends ConsumerWidget {
  const _DriverContactTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(chatUsersProvider);

    return contacts.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, __) => _ContactList(
          contacts: const [],
          onRefresh: () => ref.invalidate(chatUsersProvider)),
      data: (list) => _ContactList(
        contacts: list,
        onRefresh: () => ref.invalidate(chatUsersProvider),
      ),
    );
  }
}

class _ContactList extends ConsumerWidget {
  const _ContactList({required this.contacts, required this.onRefresh});
  final List<Map<String, dynamic>> contacts;
  final VoidCallback onRefresh;

  Future<void> _sos(BuildContext context, WidgetRef ref) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiConstants.commsCall, data: {'use_voip': true});
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('SOS alert sent to all contacts'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleColors = <String, Color>{
      'gatekeeper': AppColors.accent,
      'manager': AppColors.primary,
      'admin': AppColors.warning,
      'superadmin': AppColors.error,
    };

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // SOS banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.sos, color: AppColors.error, size: 26),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Emergency SOS',
                          style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text('Alert all contacts immediately',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ]),
              ),
              ElevatedButton(
                onPressed: () => _sos(context, ref),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('SOS',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          if (contacts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline,
                      size: 48, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text('No contacts available',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
                  SizedBox(height: 4),
                  Text('Hub operators and managers will appear here',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12),
                      textAlign: TextAlign.center),
                ]),
              ),
            )
          else ...[
            Text('${contacts.length} Contact${contacts.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ...contacts.map((u) {
              final role = (u['role'] as String?) ?? 'user';
              final color = roleColors[role] ?? AppColors.textSecondary;
              final name = (u['name'] as String?) ?? 'Unknown';
              final email = (u['email'] as String?) ?? '';
              final customId = (u['custom_id'] as String?) ?? '';
              final userId = (u['id'] as String?) ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: color.withOpacity(0.15),
                    child: Icon(_roleIcon(role), color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          if (email.isNotEmpty)
                            Text(email,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11)),
                          Text(customId,
                              style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontFamily: 'monospace')),
                        ]),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                        role == 'gatekeeper' &&
                                (u['organization_name'] as String?)
                                        ?.isNotEmpty ==
                                    true
                            ? (u['organization_name'] as String).toUpperCase()
                            : _roleBadge(role),
                        style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          recipientId: userId,
                          recipientName: name,
                          recipientRole: role,
                          recipientCustomId: customId,
                          recipientOrg: u['organization_name'] as String?,
                        ),
                      ));
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 14),
                    label: const Text('Chat'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: color == AppColors.primary
                          ? Colors.black
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'gatekeeper':
        return Icons.warehouse_outlined;
      case 'manager':
      case 'admin':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outlined;
    }
  }

  String _roleBadge(String role) {
    switch (role) {
      case 'gatekeeper':
        return 'HUB OPS';
      case 'manager':
        return 'MANAGER';
      case 'admin':
        return 'ADMIN';
      default:
        return role.toUpperCase();
    }
  }
}

// ── QR Dialog ─────────────────────────────────────────────────────────────────

class _QRDialog extends ConsumerStatefulWidget {
  const _QRDialog({required this.shipmentId});
  final String shipmentId;

  @override
  ConsumerState<_QRDialog> createState() => _QRDialogState();
}

class _QRDialogState extends ConsumerState<_QRDialog> {
  bool _loading = true;
  String? _error;
  Uint8List? _pngBytes;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      // Backend returns PNG bytes whose QR encodes the full signed JSON payload
      // (tid, sid, uid, iat, exp, tok, sig). We must display THIS PNG — not
      // regenerate a client-side QR — otherwise the hub scanner won't get the
      // sig field needed for HMAC validation.
      final res = await ref.read(dioProvider).get<List<int>>(
            ApiConstants.qrGenerate(widget.shipmentId),
            options: Options(responseType: ResponseType.bytes),
          );
      if (!mounted) return;
      setState(() {
        _pngBytes = Uint8List.fromList(res.data ?? const []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load QR: ${e.toString().split(':').last.trim()}';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Pickup QR Code',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Show this to Hub — single use, 5 min',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          // Earnings badge above QR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.15),
                  AppColors.primary.withOpacity(0.1)
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.currency_rupee, size: 16, color: AppColors.success),
              SizedBox(width: 4),
              Text(
                'You earn \u20B9150 - \u20B9220 for this delivery',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 32),
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
              ]),
            )
          else if (_pngBytes != null && _pngBytes!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Image.memory(
                _pngBytes!,
                width: 220,
                height: 220,
                gaplessPlayback: true,
                filterQuality: FilterQuality.none,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'ID: ${widget.shipmentId.length > 8 ? widget.shipmentId.substring(0, 8) : widget.shipmentId}...',
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceAlt,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text('Close'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 13, color: AppColors.textMuted),
      const SizedBox(width: 6),
      Text(text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    ]);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyDeliveries extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline,
            size: 56, color: AppColors.success.withOpacity(0.4)),
        const SizedBox(height: 12),
        const Text('All deliveries done!',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16)),
        const SizedBox(height: 4),
        const Text('No pending deliveries assigned.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ]),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration:
          const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
    );
  }
}
