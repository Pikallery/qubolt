import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';

/// Fetches a route from Mapbox Directions API that follows real roads.
/// Splits waypoints into chunks of max 25 (API limit) and concatenates the result.
Future<List<LatLng>> fetchRoadRoute(List<LatLng> waypoints) async {
  if (waypoints.length < 2) return waypoints;
  final result = <LatLng>[];
  const chunkSize = 25;
  for (int start = 0; start < waypoints.length - 1; start += chunkSize - 1) {
    final end = math.min(start + chunkSize, waypoints.length);
    final chunk = waypoints.sublist(start, end);
    final coords = chunk.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?geometries=geojson&overview=full&access_token=${ApiConstants.mapboxToken}',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final routes = data['routes'] as List? ?? [];
        if (routes.isNotEmpty) {
          final geom = routes[0]['geometry'] as Map<String, dynamic>;
          final coordList = geom['coordinates'] as List;
          for (final c in coordList) {
            result.add(
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
          }
          continue;
        }
      }
    } catch (_) {}
    // Fallback: straight lines for this chunk
    result.addAll(chunk);
  }
  return result;
}

/// Shared provider so dashboard map and fleet screen show the same trucks.
final liveFleetProvider =
    StateNotifierProvider<LiveFleetNotifier, List<FleetTruck>>(
        (ref) => LiveFleetNotifier(ref));

class FleetTruck {
  final String id, driverId, name, status;
  final LatLng pos;
  final double speedKmh;
  const FleetTruck({
    required this.id,
    required this.driverId,
    required this.name,
    required this.status,
    required this.pos,
    required this.speedKmh,
  });
}

class LiveFleetNotifier extends StateNotifier<List<FleetTruck>> {
  LiveFleetNotifier(this._ref) : super(_kDemoFleet) {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }
  final Ref _ref;
  Timer? _timer;

  Future<void> _poll() async {
    try {
      final dio = _ref.read(dioProvider);
      final res = await dio.get(ApiConstants.commsFleetPositions);
      final list = List<Map<String, dynamic>>.from(res.data as List? ?? []);
      if (list.isNotEmpty) {
        state = list
            .map((p) => FleetTruck(
                  id: (p['custom_id'] as String?) ??
                      'DRV-${(p['driver_id'] as String?)?.substring(0, 8) ?? '?'}',
                  driverId: (p['driver_id'] as String?) ?? '',
                  name: (p['driver_name'] as String?) ?? 'Unknown',
                  status: (p['status'] as String?) ?? 'en_route',
                  pos: LatLng(
                    (p['lat'] as num?)?.toDouble() ?? 20.2961,
                    (p['lon'] as num?)?.toDouble() ?? 85.8315,
                  ),
                  speedKmh: (p['speed_kmh'] as num?)?.toDouble() ?? 0,
                ))
            .toList();
      }
      // Merge demo trucks that aren't from API
      if (state.length < 8) {
        final apiIds = state.map((t) => t.driverId).toSet();
        for (final d in _kDemoFleet) {
          if (!apiIds.contains(d.driverId) && d.driverId.isEmpty) {
            state = [...state, d];
          }
        }
      }
    } catch (_) {
      // keep existing state
    }
  }

  void refresh() => _poll();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// Demo fleet that always shows (simulated activity)
const _kDemoFleet = [
  FleetTruck(
      id: 'DRV-OD-TRUCK-3421',
      driverId: '',
      name: 'Ravi Kumar',
      status: 'en_route',
      pos: LatLng(20.4625, 85.8830),
      speedKmh: 45),
  FleetTruck(
      id: 'DRV-OD-VAN-7812',
      driverId: '',
      name: 'Amit Singh',
      status: 'at_hub',
      pos: LatLng(20.2961, 85.8315),
      speedKmh: 0),
  FleetTruck(
      id: 'DRV-OD-TRUCK-5567',
      driverId: '',
      name: 'Suresh Patel',
      status: 'en_route',
      pos: LatLng(21.4942, 86.9355),
      speedKmh: 62),
  FleetTruck(
      id: 'DRV-OD-VAN-2234',
      driverId: '',
      name: 'Priya Nanda',
      status: 'en_route',
      pos: LatLng(22.2270, 84.8536),
      speedKmh: 38),
  FleetTruck(
      id: 'DRV-OD-BIKE-9901',
      driverId: '',
      name: 'Deepak Roy',
      status: 'idle',
      pos: LatLng(19.8106, 85.8315),
      speedKmh: 0),
  FleetTruck(
      id: 'DRV-OD-TRUCK-1147',
      driverId: '',
      name: 'Gopal Das',
      status: 'en_route',
      pos: LatLng(21.4669, 83.9717),
      speedKmh: 55),
  FleetTruck(
      id: 'DRV-OD-VAN-4456',
      driverId: '',
      name: 'Manoj Behera',
      status: 'en_route',
      pos: LatLng(20.8380, 85.1010),
      speedKmh: 42),
  FleetTruck(
      id: 'DRV-OD-BIKE-3321',
      driverId: '',
      name: 'Sita Mohanty',
      status: 'en_route',
      pos: LatLng(20.5012, 86.4211),
      speedKmh: 35),
  FleetTruck(
      id: 'DRV-OD-TRUCK-8890',
      driverId: '',
      name: 'Rajesh Nayak',
      status: 'idle',
      pos: LatLng(18.8135, 82.7123),
      speedKmh: 0),
  FleetTruck(
      id: 'DRV-OD-VAN-5512',
      driverId: '',
      name: 'Anita Patra',
      status: 'en_route',
      pos: LatLng(19.3150, 84.7941),
      speedKmh: 48),
  FleetTruck(
      id: 'DRV-OD-BIKE-7745',
      driverId: '',
      name: 'Kiran Das',
      status: 'at_hub',
      pos: LatLng(21.8553, 84.0064),
      speedKmh: 0),
  FleetTruck(
      id: 'DRV-OD-TRUCK-2267',
      driverId: '',
      name: 'Bikash Jena',
      status: 'en_route',
      pos: LatLng(19.1710, 83.4166),
      speedKmh: 30),
  FleetTruck(
      id: 'DRV-OD-VAN-9934',
      driverId: '',
      name: 'Pratima Sahoo',
      status: 'en_route',
      pos: LatLng(21.9322, 86.7285),
      speedKmh: 40),
  FleetTruck(
      id: 'DRV-OD-BIKE-1123',
      driverId: '',
      name: 'Hemant Mishra',
      status: 'idle',
      pos: LatLng(20.4667, 84.2333),
      speedKmh: 0),
];

/// Dashboard ghost-route map with unoptimized→optimized toggle.
class GhostRouteMap extends ConsumerStatefulWidget {
  const GhostRouteMap({super.key, this.showOptimizeButton = false});
  final bool showOptimizeButton;

  @override
  ConsumerState<GhostRouteMap> createState() => _GhostRouteMapState();
}

class _GhostRouteMapState extends ConsumerState<GhostRouteMap>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final MapController _mapCtrl;
  bool _optimized = false;
  bool _optimizing = false;

  // Real-road-snapped geometry fetched from Mapbox Directions API
  List<LatLng>? _unoptimizedRoad;
  List<LatLng>? _optimizedRoad;

  // ── Unoptimized route (greedy/random order — longer, crosses over itself) ──
  static const _kUnoptimized = [
    LatLng(20.2961, 85.8315), // Bhubaneswar (start)
    LatLng(22.2270, 84.8536), // Rourkela (far NW jump)
    LatLng(19.3150, 84.7941), // Berhampur (far south)
    LatLng(21.4942, 86.9355), // Balasore (far NE)
    LatLng(20.4667, 84.2333), // Phulbani (central)
    LatLng(21.8553, 84.0064), // Jharsuguda (NW)
    LatLng(20.3167, 86.6104), // Paradip (east coast)
    LatLng(21.4669, 83.9717), // Sambalpur (west)
    LatLng(19.8106, 85.8315), // Puri (south coast)
    LatLng(21.0561, 86.5129), // Bhadrak (NE)
    LatLng(20.7071, 83.4849), // Bolangir (west)
    LatLng(20.4625, 85.8830), // Cuttack (central)
    LatLng(20.8380, 85.1010), // Angul (central)
    LatLng(20.6633, 85.6000), // Dhenkanal
    LatLng(20.5012, 86.4211), // Kendrapara (east)
    LatLng(21.3353, 83.6194), // Bargarh (west)
    LatLng(20.2961, 85.8315), // Back to hub
  ];

  // ── Optimized route (SA-optimised — geographically clustered, no crossings) ──
  static const _kOptimized = [
    LatLng(20.2961, 85.8315), // Bhubaneswar (hub)
    LatLng(20.4625, 85.8830), // Cuttack
    LatLng(20.6633, 85.6000), // Dhenkanal
    LatLng(20.8380, 85.1010), // Angul
    LatLng(21.0561, 86.5129), // Bhadrak
    LatLng(21.4942, 86.9355), // Balasore
    LatLng(20.5012, 86.4211), // Kendrapara
    LatLng(20.3167, 86.6104), // Paradip
    LatLng(19.8106, 85.8315), // Puri
    LatLng(19.3150, 84.7941), // Berhampur
    LatLng(20.4667, 84.2333), // Phulbani
    LatLng(20.7071, 83.4849), // Bolangir
    LatLng(21.3353, 83.6194), // Bargarh
    LatLng(21.4669, 83.9717), // Sambalpur
    LatLng(21.8553, 84.0064), // Jharsuguda
    LatLng(22.2270, 84.8536), // Rourkela
    LatLng(20.2961, 85.8315), // Back to hub
  ];

  // Traffic / unavailable road markers
  static const _kTrafficPoints = [
    LatLng(21.15, 86.0), // NH-49 congestion
    LatLng(20.65, 84.5), // Road work zone
    LatLng(19.55, 85.3), // Flood-prone area
  ];

  static const _kBlockedRoads = [
    [LatLng(21.1, 85.9), LatLng(21.2, 86.1)], // NH-49 segment
    [LatLng(19.5, 85.2), LatLng(19.6, 85.4)], // Coastal flood zone
  ];

  /// Waypoint stops (used for stop markers).
  List<LatLng> get _activeStops => _optimized ? _kOptimized : _kUnoptimized;

  /// Road-snapped polyline (falls back to straight waypoints while loading).
  List<LatLng> get _activeRoute {
    if (_optimized) return _optimizedRoad ?? _kOptimized;
    return _unoptimizedRoad ?? _kUnoptimized;
  }

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90),
    )..repeat();
    _loadRoads();
  }

  Future<void> _loadRoads() async {
    // Fetch both routes in parallel so the QUBO toggle is instant.
    final results = await Future.wait([
      fetchRoadRoute(_kUnoptimized),
      fetchRoadRoute(_kOptimized),
    ]);
    if (!mounted) return;
    setState(() {
      _unoptimizedRoad = results[0];
      _optimizedRoad = results[1];
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  LatLng _lerpAlongPolyline(List<LatLng> pts, double t) {
    if (pts.length < 2) return pts.first;
    double total = 0;
    final segs = <double>[];
    for (int i = 1; i < pts.length; i++) {
      final d = _dist(pts[i - 1], pts[i]);
      segs.add(d);
      total += d;
    }
    final target = t * total;
    double walked = 0;
    for (int i = 0; i < segs.length; i++) {
      if (walked + segs[i] >= target) {
        final s = segs[i] == 0 ? 0.0 : (target - walked) / segs[i];
        return LatLng(
          pts[i].latitude + s * (pts[i + 1].latitude - pts[i].latitude),
          pts[i].longitude + s * (pts[i + 1].longitude - pts[i].longitude),
        );
      }
      walked += segs[i];
    }
    return pts.last;
  }

  static double _dist(LatLng a, LatLng b) {
    final dlat = b.latitude - a.latitude;
    final dlon = b.longitude - a.longitude;
    return math.sqrt(dlat * dlat + dlon * dlon);
  }

  Future<void> _runOptimize() async {
    setState(() => _optimizing = true);
    // Simulate optimization delay
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _optimized = true;
        _optimizing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(liveFleetProvider);

    return Container(
      height: 340,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final truckPos = _lerpAlongPolyline(_activeRoute, _ctrl.value);
              final truck2Pos =
                  _lerpAlongPolyline(_activeRoute, (_ctrl.value + 0.35) % 1.0);

              return FlutterMap(
                mapController: _mapCtrl,
                options: const MapOptions(
                  initialCenter: LatLng(20.9517, 85.0985),
                  initialZoom: 6.5,
                  interactionOptions:
                      InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}?access_token=${ApiConstants.mapboxToken}',
                    userAgentPackageName: 'com.qloop.app',
                    tileSize: 512,
                    zoomOffset: -1,
                  ),

                  // Traffic / blocked roads (always shown)
                  if (!_optimized) ...[
                    PolylineLayer(
                      polylines: _kBlockedRoads
                          .map((seg) => Polyline(
                                points: seg,
                                color: Colors.red.withOpacity(0.7),
                                strokeWidth: 4,
                                pattern: const StrokePattern.dotted(),
                              ))
                          .toList(),
                    ),
                    MarkerLayer(
                      markers: _kTrafficPoints
                          .map((p) => Marker(
                                point: p,
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.red.withOpacity(0.6)),
                                  ),
                                  child: const Icon(Icons.warning_amber,
                                      color: Colors.red, size: 14),
                                ),
                              ))
                          .toList(),
                    ),
                  ],

                  // Route polyline
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _activeRoute,
                        color: _optimized
                            ? AppColors.ghostRoute
                            : Colors.orange.withOpacity(0.7),
                        strokeWidth: _optimized ? 2.5 : 2,
                        pattern: _optimized
                            ? const StrokePattern.solid()
                            : const StrokePattern.dotted(),
                      ),
                    ],
                  ),

                  // Stop markers
                  MarkerLayer(
                    markers: List.generate(
                      _activeStops.length - 2, // skip first/last (hub)
                      (i) => Marker(
                        point: _activeStops[i + 1],
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _optimized
                                ? AppColors.stopMarker
                                : Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: (_optimized
                                        ? AppColors.stopMarker
                                        : Colors.orange)
                                    .withOpacity(0.5),
                                blurRadius: 5,
                              )
                            ],
                          ),
                          child: Center(
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Live fleet markers from shared provider
                  MarkerLayer(
                    markers: fleet.map((t) {
                      final color = t.status == 'en_route'
                          ? AppColors.accent
                          : t.status == 'at_hub'
                              ? AppColors.primary
                              : AppColors.textSecondary;
                      return Marker(
                        point: t.pos,
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                  color: color.withOpacity(0.5), blurRadius: 8)
                            ],
                          ),
                          child: const Icon(Icons.local_shipping,
                              color: Colors.white, size: 13),
                        ),
                      );
                    }).toList(),
                  ),

                  // Animated route trucks
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: truckPos,
                        width: 34,
                        height: 34,
                        child: _AnimatedTruck(
                          pulse: _ctrl.value,
                          color: _optimized ? AppColors.accent : Colors.orange,
                        ),
                      ),
                      Marker(
                        point: truck2Pos,
                        width: 30,
                        height: 30,
                        child: _AnimatedTruck(
                          pulse: (_ctrl.value + 0.5) % 1.0,
                          color: _optimized
                              ? const Color(0xFF42A5F5)
                              : Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          // Legend overlay
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBg.withOpacity(0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_optimized) ...[
                    const _LegendRow(
                        color: Colors.orange, label: 'Initial Route'),
                    const SizedBox(height: 4),
                    const _LegendRow(
                        color: Colors.red, label: 'Blocked Segment'),
                  ] else ...[
                    const _LegendRow(
                        color: AppColors.ghostRouteSolid,
                        label: 'Optimized Route'),
                  ],
                  const SizedBox(height: 4),
                  const _LegendRow(
                      color: AppColors.accent, label: 'Live Vehicle'),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${fleet.length} trucks active',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 10)),
                  ]),
                ],
              ),
            ),
          ),

          // QUBO badge / optimize button
          Positioned(
            top: 12,
            right: 12,
            child: _optimized
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_graph,
                            color: AppColors.primary, size: 13),
                        SizedBox(width: 4),
                        Text('QUBO Route Active',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _optimizing ? null : _runOptimize,
                    icon: _optimizing
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.auto_graph, size: 14),
                    label: Text(
                        _optimizing ? 'Optimizing...' : 'Optimize with QUBO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
          ),

          // Attribution
          const Positioned(
            bottom: 6,
            right: 10,
            child: Text('© Mapbox © OpenStreetMap',
                style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTruck extends StatelessWidget {
  const _AnimatedTruck({required this.pulse, this.color});
  final double pulse;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    final scale = 0.88 + 0.12 * math.sin(pulse * 2 * math.pi);
    return Transform.scale(
      scale: scale,
      child: Container(
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
                color: c.withOpacity(0.6), blurRadius: 12, spreadRadius: 2),
          ],
        ),
        child: const Icon(Icons.local_shipping, color: Colors.white, size: 16),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
    ]);
  }
}
