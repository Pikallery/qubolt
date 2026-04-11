/// Geofence Zone Manager — view all zones on a live map, seed Odisha zones,
/// auto-assign shipments, and check if a lat/lon is inside a zone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _zonesProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get(ApiConstants.geofenceZones);
    return (res.data as List?) ?? [];
  } catch (_) {
    return [];
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class GeofenceScreen extends ConsumerStatefulWidget {
  const GeofenceScreen({super.key});

  @override
  ConsumerState<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends ConsumerState<GeofenceScreen> {
  bool _seeding = false;
  bool _assigning = false;
  Map<String, dynamic>? _checkResult;

  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  Future<void> _seedOdisha() async {
    setState(() => _seeding = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiConstants.geofenceSeedOdisha);
      ref.invalidate(_zonesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Odisha geofence zones seeded'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Seed failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _autoAssign() async {
    setState(() => _assigning = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.geofenceAutoAssign);
      final count = (res.data as Map<String, dynamic>?)?['assigned'] as int? ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Auto-assigned $count shipments to zones'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Auto-assign failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _checkPoint() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    if (lat == null || lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter valid lat / lon'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.geofenceCheck, data: {
        'lat': lat,
        'lon': lon,
      });
      setState(() => _checkResult = res.data as Map<String, dynamic>?);
    } catch (e) {
      setState(() => _checkResult = {'error': e.toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final zonesAsync = ref.watch(_zonesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  isMobile: isMobile,
                  seeding: _seeding,
                  assigning: _assigning,
                  onSeed: _seedOdisha,
                  onAutoAssign: _autoAssign,
                ),
                Expanded(
                  child: zonesAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                    error: (e, _) => _ErrorState(error: e.toString()),
                    data: (zones) => isMobile
                        ? _MobileLayout(
                            zones: zones,
                            latCtrl: _latCtrl,
                            lonCtrl: _lonCtrl,
                            checkResult: _checkResult,
                            onCheck: _checkPoint,
                          )
                        : _DesktopLayout(
                            zones: zones,
                            latCtrl: _latCtrl,
                            lonCtrl: _lonCtrl,
                            checkResult: _checkResult,
                            onCheck: _checkPoint,
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

// ── Top Bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isMobile,
    required this.seeding,
    required this.assigning,
    required this.onSeed,
    required this.onAutoAssign,
  });
  final bool isMobile, seeding, assigning;
  final VoidCallback onSeed, onAutoAssign;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        if (isMobile) ...[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                size: 18, color: AppColors.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        const Icon(Icons.location_on_outlined,
            color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Geofence Zones',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 18)),
        ),
        // Auto-assign button
        OutlinedButton.icon(
          onPressed: assigning ? null : onAutoAssign,
          icon: assigning
              ? const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent))
              : const Icon(Icons.auto_fix_high, size: 15),
          label: Text(assigning ? 'Assigning…' : 'Auto-Assign'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: const BorderSide(color: AppColors.accent),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
        const SizedBox(width: 8),
        // Seed button
        ElevatedButton.icon(
          onPressed: seeding ? null : onSeed,
          icon: seeding
              ? const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.download_outlined, size: 15),
          label: Text(seeding ? 'Seeding…' : 'Seed Odisha'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      ]),
    );
  }
}

// ── Layouts ───────────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.zones,
    required this.latCtrl,
    required this.lonCtrl,
    required this.checkResult,
    required this.onCheck,
  });
  final List<dynamic> zones;
  final TextEditingController latCtrl, lonCtrl;
  final Map<String, dynamic>? checkResult;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left panel — zone list + point check
        SizedBox(
          width: 320,
          child: _SidePanel(
            zones: zones,
            latCtrl: latCtrl,
            lonCtrl: lonCtrl,
            checkResult: checkResult,
            onCheck: onCheck,
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        // Right panel — map
        Expanded(child: _GeoMap(zones: zones)),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.zones,
    required this.latCtrl,
    required this.lonCtrl,
    required this.checkResult,
    required this.onCheck,
  });
  final List<dynamic> zones;
  final TextEditingController latCtrl, lonCtrl;
  final Map<String, dynamic>? checkResult;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: _GeoMap(zones: zones),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: _SidePanel(
            zones: zones,
            latCtrl: latCtrl,
            lonCtrl: lonCtrl,
            checkResult: checkResult,
            onCheck: onCheck,
          ),
        ),
      ],
    );
  }
}

// ── Map ───────────────────────────────────────────────────────────────────────

class _GeoMap extends StatelessWidget {
  const _GeoMap({required this.zones});
  final List<dynamic> zones;

  // Fallback Odisha zone centres when no zones exist yet
  static const _odishaPreview = [
    (name: 'Bhubaneswar', lat: 20.2961, lon: 85.8315, r: 0.18),
    (name: 'Cuttack',     lat: 20.4625, lon: 85.8830, r: 0.14),
    (name: 'Rourkela',    lat: 22.2604, lon: 84.8536, r: 0.16),
    (name: 'Sambalpur',   lat: 21.4669, lon: 83.9756, r: 0.13),
    (name: 'Puri',        lat: 19.8106, lon: 85.8315, r: 0.12),
    (name: 'Berhampur',   lat: 19.3150, lon: 84.7941, r: 0.12),
    (name: 'Balasore',    lat: 21.4927, lon: 86.9260, r: 0.12),
    (name: 'Koraput',     lat: 18.8125, lon: 82.7100, r: 0.11),
  ];

  List<CircleMarker> _buildCircles() {
    if (zones.isNotEmpty) {
      return zones.map((z) {
        final zone = z as Map<String, dynamic>;
        final lat = (zone['lat'] ?? zone['center_lat'] as num?)?.toDouble() ?? 20.2961;
        final lon = (zone['lon'] ?? zone['center_lon'] as num?)?.toDouble() ?? 85.8315;
        final radius = ((zone['radius_km'] as num?)?.toDouble() ?? 15.0) * 1000;
        return CircleMarker(
          point: LatLng(lat, lon),
          radius: radius,
          color: AppColors.primary.withValues(alpha: 0.12),
          borderColor: AppColors.primary.withValues(alpha: 0.6),
          borderStrokeWidth: 1.5,
          useRadiusInMeter: true,
        );
      }).toList();
    }
    // Show preview circles
    return _odishaPreview.map((z) {
      final radiusMeters = z.r * 111000; // rough deg→m
      return CircleMarker(
        point: LatLng(z.lat, z.lon),
        radius: radiusMeters,
        color: AppColors.accent.withValues(alpha: 0.10),
        borderColor: AppColors.accent.withValues(alpha: 0.45),
        borderStrokeWidth: 1.5,
        useRadiusInMeter: true,
      );
    }).toList();
  }

  List<Marker> _buildLabels() {
    if (zones.isNotEmpty) {
      return zones.map((z) {
        final zone = z as Map<String, dynamic>;
        final lat = (zone['lat'] ?? zone['center_lat'] as num?)?.toDouble() ?? 20.2961;
        final lon = (zone['lon'] ?? zone['center_lon'] as num?)?.toDouble() ?? 85.8315;
        final name = zone['name'] as String? ?? 'Zone';
        return Marker(
          point: LatLng(lat, lon),
          width: 90, height: 28,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.cardBg.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Text(
              name,
              style: const TextStyle(
                  color: AppColors.primary, fontSize: 9,
                  fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList();
    }
    return _odishaPreview.map((z) => Marker(
      point: LatLng(z.lat, z.lon),
      width: 90, height: 28,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.cardBg.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: Text(
          z.name,
          style: const TextStyle(
              color: AppColors.accent, fontSize: 9,
              fontWeight: FontWeight.w700),
        ),
      ),
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(20.5937, 84.2500), // Odisha centre
        initialZoom: 6.5,
        interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}?access_token=${ApiConstants.mapboxToken}',
          userAgentPackageName: 'com.qloop.app',
          tileSize: 512,
          zoomOffset: -1,
        ),
        CircleLayer(circles: _buildCircles()),
        MarkerLayer(markers: _buildLabels()),
      ],
    );
  }
}

// ── Side panel ────────────────────────────────────────────────────────────────

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.zones,
    required this.latCtrl,
    required this.lonCtrl,
    required this.checkResult,
    required this.onCheck,
  });
  final List<dynamic> zones;
  final TextEditingController latCtrl, lonCtrl;
  final Map<String, dynamic>? checkResult;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Summary ─────────────────────────────────────────────────────────
          Row(children: [
            _StatPill('${zones.length}', 'Zones', AppColors.primary),
            const SizedBox(width: 8),
            _StatPill(
              zones.where((z) => (z as Map)['is_active'] == true).length
                  .toString(),
              'Active',
              AppColors.success,
            ),
          ]),
          const SizedBox(height: 16),

          // ── Point check ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.my_location, color: AppColors.accent, size: 16),
                  SizedBox(width: 6),
                  Text('Check Point in Zone',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: latCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onCheck,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    child: const Text('Check'),
                  ),
                ),
                if (checkResult != null) ...[
                  const SizedBox(height: 10),
                  _CheckResultCard(result: checkResult!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Zone list ───────────────────────────────────────────────────────
          Text(
            zones.isEmpty ? 'No zones yet — click "Seed Odisha"' : 'All Zones',
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (zones.isEmpty)
            const _EmptyState()
          else
            ...zones.map((z) => _ZoneCard(zone: z as Map<String, dynamic>)),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill(this.value, this.label, this.color);
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({required this.zone});
  final Map<String, dynamic> zone;

  @override
  Widget build(BuildContext context) {
    final name = zone['name'] as String? ?? 'Unnamed Zone';
    final district = zone['district'] as String? ?? '';
    final state = zone['state'] as String? ?? '';
    final isActive = zone['is_active'] as bool? ?? true;
    final radius = (zone['radius_km'] as num?)?.toDouble();
    final shipCount = zone['shipment_count'] as int?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppColors.success : AppColors.textMuted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            if (district.isNotEmpty || state.isNotEmpty)
              Text(
                [district, state].where((s) => s.isNotEmpty).join(', '),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
              ),
          ]),
        ),
        if (radius != null)
          Text('${radius.toStringAsFixed(0)} km',
              style: const TextStyle(
                  color: AppColors.accent, fontSize: 11,
                  fontWeight: FontWeight.w600)),
        if (shipCount != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$shipCount pkgs',
                style: const TextStyle(
                    color: AppColors.primary, fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

class _CheckResultCard extends StatelessWidget {
  const _CheckResultCard({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final error = result['error'] as String?;
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Text(error,
            style: const TextStyle(color: AppColors.error, fontSize: 11)),
      );
    }

    final inZone = result['in_zone'] as bool? ??
        result['inside'] as bool? ??
        (result['zone'] != null);
    final zoneName = (result['zone'] as Map<String, dynamic>?)?['name']
        as String? ?? result['zone_name'] as String? ?? '';
    final color = inZone ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(
          inZone ? Icons.check_circle_outline : Icons.cancel_outlined,
          color: color, size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            inZone
                ? 'Inside${zoneName.isNotEmpty ? ': $zoneName' : ' a zone'}'
                : 'Not inside any zone',
            style: TextStyle(
                color: color, fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_off_outlined,
            size: 36, color: AppColors.textMuted),
        SizedBox(height: 8),
        Text('No geofence zones yet',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        SizedBox(height: 4),
        Text('Click "Seed Odisha" to load pre-built district zones.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 40),
        const SizedBox(height: 12),
        Text('Failed to load zones: $error',
            style: const TextStyle(color: AppColors.error, fontSize: 13),
            textAlign: TextAlign.center),
      ]),
    );
  }
}
