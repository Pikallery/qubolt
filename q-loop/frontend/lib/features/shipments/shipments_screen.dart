import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../../core/widgets/api_error_widget.dart';
import '../auth/domain/auth_provider.dart';
import '../dashboard/widgets/dark_sidebar.dart';

// ── Provider ──────────────────────────────────────────────────────────────────
// Key is a stable string "page|status|region" to avoid Map reference equality bug

final _shipmentsProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, key) async {
    final parts = key.split('|');
    final page = int.tryParse(parts[0]) ?? 1;
    final status = parts[1].isEmpty ? null : parts[1];
    final region = parts[2].isEmpty ? null : parts[2];
    final dio = ref.read(dioProvider);
    final res = await dio.get(ApiConstants.shipments, queryParameters: {
      'page': page,
      'page_size': 50,
      if (status != null) 'status': status,
      if (region != null) 'region': region,
    });
    return res.data as Map<String, dynamic>;
  },
);

// ── Screen ────────────────────────────────────────────────────────────────────

class ShipmentsScreen extends ConsumerStatefulWidget {
  const ShipmentsScreen({super.key});

  @override
  ConsumerState<ShipmentsScreen> createState() => _ShipmentsScreenState();
}

class _ShipmentsScreenState extends ConsumerState<ShipmentsScreen> {
  int _page = 1;
  String? _statusFilter;
  String? _regionFilter;
  final _regionCtrl = TextEditingController();

  // Stable string key: "page|status|region" — avoids Map reference equality bug
  String get _providerKey =>
      '$_page|${_statusFilter ?? ''}|${_regionFilter ?? ''}';

  @override
  void dispose() {
    _regionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final data = ref.watch(_shipmentsProvider(_providerKey));

    return Scaffold(
      backgroundColor: AppColors.surface(context),
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(isMobile: isMobile),
                _FilterBar(
                  statusFilter: _statusFilter,
                  regionCtrl: _regionCtrl,
                  onStatusChanged: (v) => setState(() {
                    _statusFilter = v;
                    _page = 1;
                  }),
                  onRegionSubmitted: (v) => setState(() {
                    _regionFilter = v.isEmpty ? null : v;
                    _page = 1;
                  }),
                ),
                Expanded(
                  child: data.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ApiErrorWidget(
                      error: e,
                      onRetry: () =>
                          ref.invalidate(_shipmentsProvider(_providerKey)),
                    ),
                    data: (d) {
                      final items = (d['items'] as List?) ?? [];
                      final total = d['total'] as int? ?? 0;
                      final hasNext = d['has_next'] as bool? ?? false;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 8),
                            child: Row(
                              children: [
                                Text('$total shipments',
                                    style: TextStyle(
                                        color: AppColors.labelText(context),
                                        fontSize: 13)),
                                const Spacer(),
                                Text('Page $_page',
                                    style: TextStyle(
                                        color: AppColors.labelText(context),
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => Divider(
                                  color: AppColors.divider(context), height: 1),
                              itemBuilder: (_, i) => _ShipmentRow(
                                  items[i] as Map<String, dynamic>),
                            ),
                          ),
                          _Pagination(
                            page: _page,
                            hasNext: hasNext,
                            onPrev: _page > 1
                                ? () => setState(() => _page--)
                                : null,
                            onNext:
                                hasNext ? () => setState(() => _page++) : null,
                          ),
                        ],
                      );
                    },
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
      child: Row(
        children: [
          if (isMobile) ...[
            IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
          ],
          Text('Shipments',
              style: TextStyle(
                  color: AppColors.surface(context) == AppColors.lightScaffoldBg
                      ? AppColors.lightTextPrimary
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 18)),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.statusFilter,
    required this.regionCtrl,
    required this.onStatusChanged,
    required this.onRegionSubmitted,
  });
  final String? statusFilter;
  final TextEditingController regionCtrl;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String> onRegionSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        border: Border(bottom: BorderSide(color: AppColors.divider(context))),
      ),
      child: Row(
        children: [
          // Status filter
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: statusFilter,
              hint: Text('All statuses', style: TextStyle(fontSize: 13)),
              dropdownColor: AppColors.cardBg,
              style:
                  TextStyle(color: AppColors.textMain(context), fontSize: 13),
              items: const [
                DropdownMenuItem(value: null, child: Text('All statuses')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(
                    value: 'in_transit', child: Text('In Transit')),
                DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                DropdownMenuItem(value: 'failed', child: Text('Failed')),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          const SizedBox(width: 16),
          // Region filter
          SizedBox(
            width: 180,
            height: 36,
            child: TextField(
              controller: regionCtrl,
              style: TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Filter by region…',
                hintStyle: TextStyle(
                    color: AppColors.labelText(context), fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppColors.divider(context)),
                ),
              ),
              onSubmitted: onRegionSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentRow extends ConsumerWidget {
  const _ShipmentRow(this.s);
  final Map<String, dynamic> s;

  void _showProofOfDelivery(BuildContext context, WidgetRef ref, String id) {
    showDialog<void>(
      context: context,
      builder: (_) => _ProofOfDeliveryDialog(shipmentId: id, ref: ref),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = s['status'] as String? ?? 'unknown';
    final isDelayed = s['is_delayed'] as bool? ?? false;
    final shipmentId = s['id'] as String? ?? '';
    return InkWell(
      onTap: shipmentId.isNotEmpty
          ? () => _showProofOfDelivery(context, ref, shipmentId)
          : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.statusColor(status),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // External ID
          Expanded(
            flex: 3,
            child: Text(
              (s['external_id'] as String? ?? s['id'] as String? ?? '—')
                          .length >
                      24
                  ? '${(s['external_id'] as String? ?? '').substring(0, 20)}…'
                  : (s['external_id'] as String? ?? s['id'] as String? ?? '—'),
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Region
          Expanded(
            flex: 2,
            child: Text(s['region'] as String? ?? '—',
                style: TextStyle(
                    fontSize: 13, color: AppColors.labelText(context))),
          ),
          // Vehicle
          Expanded(
            flex: 2,
            child: Row(children: [
              Icon(_vehicleIcon(s['vehicle_type'] as String?),
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(s['vehicle_type'] as String? ?? '—',
                  style: TextStyle(fontSize: 12)),
            ]),
          ),
          // Mode
          Expanded(
            flex: 2,
            child: Text(s['delivery_mode'] as String? ?? '—',
                style: TextStyle(
                    fontSize: 12, color: AppColors.labelText(context))),
          ),
          // Driver assigned
          Expanded(
            flex: 2,
            child: Builder(builder: (ctx) {
              final role = ref.read(authNotifierProvider).role ?? '';
              if (role != 'manager' && role != 'admin' && role != 'superadmin') {
                return const SizedBox.shrink();
              }
              final driverId = s['assigned_driver_id'] as String?;
              if (driverId == null || driverId.isEmpty) {
                return Text('Unassigned',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic));
              }
              return Row(children: [
                const Icon(Icons.person_rounded,
                    size: 12, color: AppColors.success),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    driverId.substring(0, 8),
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]);
            }),
          ),
          // Distance
          Expanded(
            flex: 1,
            child: Text(
              s['distance_km'] != null ? '${s['distance_km']} km' : '—',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          // Assign Driver button (manager/admin only)
          if (shipmentId.isNotEmpty) Builder(
            builder: (ctx) {
              final role = ref.read(authNotifierProvider).role ?? '';
              if (role != 'manager' && role != 'admin' && role != 'superadmin') {
                return const SizedBox.shrink();
              }
              final alreadyAssigned =
                  (s['assigned_driver_id'] as String?)?.isNotEmpty ?? false;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton.icon(
                  onPressed: () =>
                      _AssignDriverDialog.show(ctx, ref, shipmentId),
                  icon: Icon(
                    alreadyAssigned
                        ? Icons.swap_horiz_rounded
                        : Icons.person_add_outlined,
                    size: 14,
                  ),
                  label: Text(
                    alreadyAssigned ? 'Reassign' : 'Assign',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              );
            },
          ),
          // AI ETA button
          if (status != 'delivered' && shipmentId.isNotEmpty)
            InkWell(
              onTap: () => _predictEta(context, ref, shipmentId),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Tooltip(
                  message: 'AI ETA Prediction',
                  child: Icon(Icons.schedule,
                      size: 16, color: AppColors.accent.withOpacity(0.8)),
                ),
              ),
            ),
          if (status != 'delivered' && shipmentId.isNotEmpty)
            const SizedBox(width: 4),
          // Status chip
          _StatusChip(status: status),
          const SizedBox(width: 8),
          // Delayed badge
          if (isDelayed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('DELAYED',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700)),
            ),
        ],
        ),
      ),
    );
  }

  Future<void> _predictEta(
      BuildContext context, WidgetRef ref, String id) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(ApiConstants.aiEtaPredict(id));
      final data = res.data as Map<String, dynamic>;
      final eta = data['eta'] as String? ??
          data['predicted_eta'] as String? ??
          'Unknown';
      final confidence = (data['confidence'] as num?)?.toDouble();
      final explanation = data['explanation'] as String? ?? '';
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Row(children: [
            Icon(Icons.schedule, color: AppColors.accent, size: 18),
            SizedBox(width: 8),
            Text('AI ETA Prediction', style: TextStyle(fontSize: 15)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estimated arrival: $eta',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (confidence != null) ...[
                const SizedBox(height: 8),
                Text('Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        color: AppColors.textSub(context), fontSize: 13)),
              ],
              if (explanation.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(explanation,
                    style: TextStyle(
                        color: AppColors.textSub(context),
                        fontSize: 13,
                        height: 1.5)),
              ],
            ],
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
        content: Text('ETA prediction unavailable: $e'),
        backgroundColor: AppColors.warning,
      ));
    }
  }

  IconData _vehicleIcon(String? type) {
    switch (type) {
      case 'bike':
      case 'scooter':
      case 'ev_bike':
        return Icons.two_wheeler;
      case 'truck':
        return Icons.local_shipping;
      case 'van':
      case 'ev_van':
        return Icons.airport_shuttle;
      default:
        return Icons.directions_car;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
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
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination(
      {required this.page,
      required this.hasNext,
      required this.onPrev,
      required this.onNext});
  final int page;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            color: onPrev != null ? AppColors.primary : AppColors.textSecondary,
          ),
          Text('  Page $page  ',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            color: onNext != null ? AppColors.primary : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

// ── Proof of Delivery dialog ──────────────────────────────────────────────────

class _ProofOfDeliveryDialog extends StatefulWidget {
  const _ProofOfDeliveryDialog({required this.shipmentId, required this.ref});
  final String shipmentId;
  final WidgetRef ref;

  @override
  State<_ProofOfDeliveryDialog> createState() => _ProofOfDeliveryDialogState();
}

class _ProofOfDeliveryDialogState extends State<_ProofOfDeliveryDialog> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
  }

  Future<void> _fetchPhotos() async {
    try {
      final dio = widget.ref.read(dioProvider);
      final res = await dio.get(ApiConstants.shipmentPhotos(widget.shipmentId));
      final list = List<Map<String, dynamic>>.from(res.data as List? ?? []);
      if (mounted) setState(() { _photos = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.photo_camera_outlined,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Proof of Delivery',
                      style: TextStyle(
                          color: AppColors.textMain(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close,
                      color: AppColors.labelText(context), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                'Shipment ${widget.shipmentId.length > 20 ? "${widget.shipmentId.substring(0, 18)}…" : widget.shipmentId}',
                style: TextStyle(
                    color: AppColors.labelText(context),
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return ApiErrorWidget(error: _error!, onRetry: _fetchPhotos);
    }
    if (_photos.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.photo_outlined,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No photos uploaded yet',
              style: TextStyle(
                  color: AppColors.textSub(context),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Driver uploads proof of delivery on completion',
              style:
                  TextStyle(color: AppColors.labelText(context), fontSize: 12)),
        ]),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 4 / 3,
      ),
      itemCount: _photos.length,
      itemBuilder: (_, i) {
        final photo = _photos[i];
        final photoId = photo['id'] as String? ?? '';
        final filename = photo['filename'] as String? ?? 'Photo ${i + 1}';
        final uploadedAt = photo['uploaded_at'] as String?;
        String timeStr = '';
        if (uploadedAt != null) {
          try {
            final dt = DateTime.parse(uploadedAt).toLocal();
            timeStr = '${dt.day}/${dt.month}/${dt.year}';
          } catch (_) {}
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(fit: StackFit.expand, children: [
            _PhotoTile(photoId: photoId, dioRef: widget.ref),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                    if (timeStr.isNotEmpty)
                      Text(timeStr,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 9)),
                  ],
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// Fetches a single photo as bytes and renders it.
class _PhotoTile extends StatefulWidget {
  const _PhotoTile({required this.photoId, required this.dioRef});
  final String photoId;
  final WidgetRef dioRef;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = widget.dioRef.read(dioProvider);
      final res = await dio.get<List<int>>(
        ApiConstants.photoFile(widget.photoId),
        options: Options(responseType: ResponseType.bytes),
      );
      if (mounted && res.data != null) {
        setState(() {
          _bytes = Uint8List.fromList(res.data!);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: AppColors.surfaceAltOf(context),
        child: const Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    if (_bytes == null) {
      return Container(
        color: AppColors.surfaceAltOf(context),
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              color: AppColors.labelText(context), size: 28),
        ),
      );
    }
    return Image.memory(_bytes!, fit: BoxFit.cover);
  }
}

// ── Assign Driver Dialog ──────────────────────────────────────────────────────

class _AssignDriverDialog extends StatefulWidget {
  const _AssignDriverDialog({required this.shipmentId});
  final String shipmentId;

  static void show(BuildContext context, WidgetRef ref, String shipmentId) {
    showDialog<void>(
      context: context,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _AssignDriverDialog(shipmentId: shipmentId),
      ),
    );
  }

  @override
  State<_AssignDriverDialog> createState() => _AssignDriverDialogState();
}

class _AssignDriverDialogState extends State<_AssignDriverDialog> {
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;
  String? _selectedDriverId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _fetchDrivers();
  }

  Future<void> _fetchDrivers() async {
    try {
      // Access dio via a consumer - use direct access from ProviderScope
      final container = ProviderScope.containerOf(context);
      final dio = container.read(dioProvider);
      final res = await dio.get(ApiConstants.userDrivers);
      final list = List<Map<String, dynamic>>.from(res.data as List? ?? []);
      if (mounted) setState(() { _drivers = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign() async {
    if (_selectedDriverId == null) return;
    setState(() => _submitting = true);
    try {
      final container = ProviderScope.containerOf(context);
      final dio = container.read(dioProvider);
      await dio.post(
        ApiConstants.shipmentAssignDriver(widget.shipmentId),
        data: {'driver_id': _selectedDriverId},
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Driver assigned and notified'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to assign: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(children: [
        Icon(Icons.person_add_outlined, color: AppColors.primary, size: 18),
        SizedBox(width: 8),
        Text('Assign Driver', style: TextStyle(fontSize: 15)),
      ]),
      content: SizedBox(
        width: 340,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _drivers.isEmpty
                ? const Text('No active drivers found.',
                    style: TextStyle(color: AppColors.textSecondary))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select a driver to assign to this shipment:',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedDriverId,
                        dropdownColor: AppColors.cardBg,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        hint: const Text('Choose driver', style: TextStyle(fontSize: 13)),
                        items: _drivers.map((d) {
                          final name = d['full_name'] as String? ?? d['email'] as String? ?? '—';
                          final id = d['id'] as String;
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(name, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedDriverId = v),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_selectedDriverId == null || _submitting) ? null : _assign,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitting
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Assign', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
