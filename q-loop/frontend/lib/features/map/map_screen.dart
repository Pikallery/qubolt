library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../dashboard/widgets/dark_sidebar.dart';
import '../routes/ghost_route_map.dart';

// Traffic severity segments across Odisha highway network
const _kTrafficHeavy = [
  [LatLng(20.45, 85.83), LatLng(20.55, 85.89)],  // NH-16 Cuttack bypass
  [LatLng(21.45, 86.88), LatLng(21.52, 86.95)],  // Balasore entry
  [LatLng(22.18, 84.80), LatLng(22.25, 84.90)],  // Rourkela industrial
];
const _kTrafficModerate = [
  [LatLng(20.28, 85.80), LatLng(20.35, 85.88)],
  [LatLng(21.40, 83.90), LatLng(21.50, 84.00)],
  [LatLng(19.82, 85.75), LatLng(19.90, 85.85)],
];
const _kClosedRoads = [
  [LatLng(20.65, 84.45), LatLng(20.72, 84.52)],  // Flood closure
  [LatLng(19.52, 85.22), LatLng(19.60, 85.32)],  // Road work
];

const _kTollData = [
  (lat: 20.42, lon: 85.84, name: 'Cuttack Toll'),
  (lat: 22.20, lon: 84.82, name: 'Rourkela Toll'),
  (lat: 21.47, lon: 86.91, name: 'Balasore Toll'),
  (lat: 19.85, lon: 85.82, name: 'Puri Toll'),
];

const _kHubData = [
  (lat: 20.2961, lon: 85.8315, name: 'Bhubaneswar HQ'),
  (lat: 20.4625, lon: 85.8830, name: 'Cuttack Central'),
  (lat: 22.2270, lon: 84.8536, name: 'Rourkela North'),
  (lat: 21.4942, lon: 86.9355, name: 'Balasore East'),
  (lat: 19.8106, lon: 85.8315, name: 'Puri Coastal'),
  (lat: 21.4669, lon: 83.9717, name: 'Sambalpur Depot'),
];

final _showTrafficProvider   = StateProvider<bool>((ref) => true);
final _showTollsProvider     = StateProvider<bool>((ref) => true);
final _showClosuresProvider  = StateProvider<bool>((ref) => true);
final _showFleetProvider     = StateProvider<bool>((ref) => true);
final _mapStyleProvider      = StateProvider<String>((ref) => 'dark-v11');

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapCtrl;
  late final AnimationController _pulse;
  late final AnimationController _trafficFlow;
  String? _hoveredToll;
  bool _optimized = false;
  bool _optimizing = false;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _trafficFlow = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() { _pulse.dispose(); _trafficFlow.dispose(); super.dispose(); }

  Future<void> _optimize() async {
    setState(() => _optimizing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() { _optimized = true; _optimizing = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final showTraffic  = ref.watch(_showTrafficProvider);
    final showTolls    = ref.watch(_showTollsProvider);
    final showClosures = ref.watch(_showClosuresProvider);
    final showFleet    = ref.watch(_showFleetProvider);
    final mapStyle     = ref.watch(_mapStyleProvider);
    final fleet        = ref.watch(liveFleetProvider);

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: Row(children: [
        if (!isMobile) const DarkSidebar(),
        Expanded(
          child: Stack(children: [
            // ── Full-screen map ──────────────────────────────────────────────
            AnimatedBuilder(
              animation: Listenable.merge([_pulse, _trafficFlow]),
              builder: (ctx, _) => FlutterMap(
                mapController: _mapCtrl,
                options: const MapOptions(
                  initialCenter: LatLng(20.5937, 84.2500),
                  initialZoom: 7.2,
                  interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.mapbox.com/styles/v1/mapbox/$mapStyle/tiles/{z}/{x}/{y}?access_token=${ApiConstants.mapboxToken}',
                    userAgentPackageName: 'com.qloop.app',
                    tileSize: 512,
                    zoomOffset: -1,
                  ),

                  // ── Road closures ────────────────────────────────────────
                  if (showClosures)
                    PolylineLayer(
                      polylines: _kClosedRoads.map((seg) => Polyline(
                        points: seg,
                        color: Colors.red.withOpacity(0.85),
                        strokeWidth: 5,
                        pattern: const StrokePattern.dotted(),
                      )).toList(),
                    ),

                  // ── Heavy traffic ────────────────────────────────────────
                  if (showTraffic)
                    PolylineLayer(
                      polylines: [
                        ..._kTrafficHeavy.map((seg) => Polyline(
                          points: seg,
                          color: Colors.red.withOpacity(0.6 + _trafficFlow.value * 0.2),
                          strokeWidth: 6,
                        )),
                        ..._kTrafficModerate.map((seg) => Polyline(
                          points: seg,
                          color: Colors.orange.withOpacity(0.55 + _trafficFlow.value * 0.15),
                          strokeWidth: 5,
                        )),
                      ],
                    ),

                  // ── Optimized / unoptimized ghost route ──────────────────
                  PolylineLayer(
                    polylines: [
                      if (_optimized)
                        Polyline(
                          points: _kOptimizedRoute,
                          color: AppColors.quantumAccent.withOpacity(0.15),
                          strokeWidth: 12,
                        ),
                      Polyline(
                        points: _optimized ? _kOptimizedRoute : _kUnoptimizedRoute,
                        color: _optimized
                            ? AppColors.quantumAccent.withOpacity(0.85)
                            : Colors.orange.withOpacity(0.6),
                        strokeWidth: _optimized ? 3.5 : 2.5,
                        pattern: _optimized
                            ? const StrokePattern.solid()
                            : const StrokePattern.dotted(),
                      ),
                    ],
                  ),

                  // ── Toll markers ─────────────────────────────────────────
                  if (showTolls)
                    MarkerLayer(
                      markers: _kTollData.map((t) => Marker(
                        point: LatLng(t.lat, t.lon),
                        width: _hoveredToll == t.name ? 80 : 32,
                        height: 32,
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hoveredToll = t.name),
                          onExit:  (_) => setState(() => _hoveredToll = null),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(
                              horizontal: _hoveredToll == t.name ? 8 : 0,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [BoxShadow(
                                color: const Color(0xFFF59E0B).withOpacity(0.4),
                                blurRadius: 8,
                              )],
                            ),
                            child: _hoveredToll == t.name
                                ? Text(t.name, style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w700))
                                : const Icon(Icons.toll, color: Colors.black, size: 16),
                          ),
                        ),
                      )).toList(),
                    ),

                  // ── Road closure markers ─────────────────────────────────
                  if (showClosures)
                    MarkerLayer(
                      markers: _kClosedRoads.map((seg) {
                        final mid = LatLng((seg[0].latitude + seg[1].latitude) / 2, (seg[0].longitude + seg[1].longitude) / 2);
                        return Marker(
                          point: mid,
                          width: 28, height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.85),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 8)],
                            ),
                            child: const Icon(Icons.block, color: Colors.white, size: 14),
                          ),
                        );
                      }).toList(),
                    ),

                  // ── Hub markers with breathing glow ─────────────────────
                  MarkerLayer(
                    markers: _kHubData.map((h) => Marker(
                      point: LatLng(h.lat, h.lon),
                      width: 44, height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.quantumAccent.withOpacity(0.15 + _pulse.value * 0.25),
                              blurRadius: 16 + _pulse.value * 8,
                              spreadRadius: 2 + _pulse.value * 4,
                            ),
                          ],
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.quantumAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.warehouse_outlined, color: Colors.black, size: 14),
                        ),
                      ),
                    )).toList(),
                  ),

                  // ── Fleet trucks ─────────────────────────────────────────
                  if (showFleet)
                    MarkerLayer(
                      markers: fleet.map((t) {
                        final color = t.status == 'en_route'
                            ? AppColors.accent
                            : t.status == 'at_hub'
                                ? AppColors.quantumAccent
                                : AppColors.textSecondary;
                        return Marker(
                          point: t.pos,
                          width: 30, height: 30,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)],
                            ),
                            child: const Icon(Icons.local_shipping, color: Colors.white, size: 14),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),

            // ── Top bar ──────────────────────────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.obsidian.withOpacity(0.9),
                  border: const Border(bottom: BorderSide(color: Color(0xFF1A2030))),
                ),
                child: Row(children: [
                  if (isMobile) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: AppColors.textSecondary, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.quantumAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.quantumAccent.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.map_outlined, color: AppColors.quantumAccent, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text('Live Intelligence Map',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                  const Spacer(),
                  // Style toggle
                  _StyleToggle(
                    current: ref.watch(_mapStyleProvider),
                    onChanged: (s) => ref.read(_mapStyleProvider.notifier).state = s,
                  ),
                  const SizedBox(width: 8),
                  // Optimize button
                  _optimized
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.quantumAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.quantumAccent.withOpacity(0.4)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_outline, color: AppColors.quantumAccent, size: 14),
                            SizedBox(width: 5),
                            Text('QUBO Active', style: TextStyle(color: AppColors.quantumAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        )
                      : ElevatedButton.icon(
                          onPressed: _optimizing ? null : _optimize,
                          icon: _optimizing
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.auto_graph, size: 14),
                          label: Text(_optimizing ? 'Optimizing…' : 'Run QUBO'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.quantumAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                ]),
              ),
            ),

            // ── Layer toggles panel ───────────────────────────────────────────
            Positioned(
              top: 68, right: 12,
              child: _LayerPanel(
                showTraffic:  showTraffic,
                showTolls:    showTolls,
                showClosures: showClosures,
                showFleet:    showFleet,
                onTraffic:    (v) => ref.read(_showTrafficProvider.notifier).state = v,
                onTolls:      (v) => ref.read(_showTollsProvider.notifier).state = v,
                onClosures:   (v) => ref.read(_showClosuresProvider.notifier).state = v,
                onFleet:      (v) => ref.read(_showFleetProvider.notifier).state = v,
              ),
            ),

            // ── Legend ──────────────────────────────────────────────────────
            Positioned(
              bottom: 20, left: 12,
              child: _MapLegend(optimized: _optimized),
            ),

            // ── Stats strip ─────────────────────────────────────────────────
            Positioned(
              bottom: 20, right: 12,
              child: _MapStats(fleet: fleet, optimized: _optimized),
            ),

            // Attribution
            const Positioned(
              bottom: 5, left: 0, right: 0,
              child: Center(child: Text('© Mapbox · © OpenStreetMap contributors',
                style: TextStyle(color: Color(0xFF484F58), fontSize: 9))),
            ),
          ]),
        ),
      ]),
    );
  }
}

// Unoptimized and optimized routes
const _kUnoptimizedRoute = [
  LatLng(20.2961, 85.8315), LatLng(22.2270, 84.8536), LatLng(19.3150, 84.7941),
  LatLng(21.4942, 86.9355), LatLng(20.4667, 84.2333), LatLng(21.8553, 84.0064),
  LatLng(20.3167, 86.6104), LatLng(21.4669, 83.9717), LatLng(19.8106, 85.8315),
  LatLng(21.0561, 86.5129), LatLng(20.7071, 83.4849), LatLng(20.4625, 85.8830),
  LatLng(20.8380, 85.1010), LatLng(20.6633, 85.6000), LatLng(20.5012, 86.4211),
  LatLng(21.3353, 83.6194), LatLng(20.2961, 85.8315),
];
const _kOptimizedRoute = [
  LatLng(20.2961, 85.8315), LatLng(20.4625, 85.8830), LatLng(20.6633, 85.6000),
  LatLng(20.8380, 85.1010), LatLng(21.0561, 86.5129), LatLng(21.4942, 86.9355),
  LatLng(20.5012, 86.4211), LatLng(20.3167, 86.6104), LatLng(19.8106, 85.8315),
  LatLng(19.3150, 84.7941), LatLng(20.4667, 84.2333), LatLng(20.7071, 83.4849),
  LatLng(21.3353, 83.6194), LatLng(21.4669, 83.9717), LatLng(21.8553, 84.0064),
  LatLng(22.2270, 84.8536), LatLng(20.2961, 85.8315),
];

class _StyleToggle extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _StyleToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const styles = [('dark-v11', Icons.nightlight_outlined), ('streets-v12', Icons.wb_sunny_outlined)];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: styles.map((s) => GestureDetector(
        onTap: () => onChanged(s.$1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: current == s.$1 ? AppColors.quantumAccent.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(s.$2, size: 15, color: current == s.$1 ? AppColors.quantumAccent : AppColors.textSecondary),
        ),
      )).toList()),
    );
  }
}

class _LayerPanel extends StatelessWidget {
  final bool showTraffic, showTolls, showClosures, showFleet;
  final ValueChanged<bool> onTraffic, onTolls, onClosures, onFleet;
  const _LayerPanel({required this.showTraffic, required this.showTolls, required this.showClosures, required this.showFleet, required this.onTraffic, required this.onTolls, required this.onClosures, required this.onFleet});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.obsidian.withOpacity(0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E2A3A)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text('LAYERS', style: TextStyle(color: Color(0xFF484F58), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        _LayerRow(icon: Icons.traffic, label: 'Traffic', color: Colors.red, value: showTraffic, onChanged: onTraffic),
        _LayerRow(icon: Icons.toll, label: 'Tolls', color: const Color(0xFFF59E0B), value: showTolls, onChanged: onTolls),
        _LayerRow(icon: Icons.block, label: 'Closures', color: Colors.red, value: showClosures, onChanged: onClosures),
        _LayerRow(icon: Icons.local_shipping, label: 'Fleet', color: AppColors.accent, value: showFleet, onChanged: onFleet),
      ]),
    );
  }
}

class _LayerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _LayerRow({required this.icon, required this.label, required this.color, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, color: value ? color : const Color(0xFF484F58), size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(color: value ? Colors.white70 : const Color(0xFF484F58), fontSize: 11))),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 28, height: 16,
            decoration: BoxDecoration(
              color: value ? AppColors.quantumAccent.withOpacity(0.8) : const Color(0xFF30363D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Align(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 12, height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MapLegend extends StatelessWidget {
  final bool optimized;
  const _MapLegend({required this.optimized});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.obsidian.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _LegItem(color: optimized ? AppColors.quantumAccent : Colors.orange, label: optimized ? 'QUBO Route' : 'Initial Route'),
        const _LegItem(color: Colors.red, label: 'Heavy Traffic', dashed: true),
        const _LegItem(color: Colors.orange, label: 'Moderate Traffic'),
        const _LegItem(color: Color(0xFFF59E0B), label: 'Toll Point', icon: Icons.toll),
        const _LegItem(color: Colors.red, label: 'Road Closed', icon: Icons.block),
      ]),
    );
  }
}

class _LegItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  final IconData? icon;
  const _LegItem({required this.color, required this.label, this.dashed = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        icon != null
            ? Icon(icon, color: color, size: 12)
            : Container(width: 18, height: 3, decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ]),
    );
  }
}

class _MapStats extends StatelessWidget {
  final List<FleetTruck> fleet;
  final bool optimized;
  const _MapStats({required this.fleet, required this.optimized});

  @override
  Widget build(BuildContext context) {
    final active = fleet.where((t) => t.status == 'en_route').length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.obsidian.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.quantumAccent.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _StatItem('${fleet.length}', 'Total', AppColors.quantumAccent),
        const SizedBox(width: 14),
        _StatItem('$active', 'En Route', AppColors.accent),
        const SizedBox(width: 14),
        _StatItem(optimized ? '−23%' : '—', 'Distance', AppColors.success),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatItem(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
    ]);
  }
}

// ignore: unused_element
double _unused = math.pi; // keep math import used
