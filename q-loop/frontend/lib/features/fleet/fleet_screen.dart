import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../comms/chat_screen.dart';
import '../dashboard/widgets/dark_sidebar.dart';
import '../routes/ghost_route_map.dart';

/// Manager Fleet Control — uses shared liveFleetProvider so data matches dashboard map.
class FleetScreen extends ConsumerWidget {
  const FleetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trucks = ref.watch(liveFleetProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  count: trucks.length,
                  isMobile: isMobile,
                  onRefresh: () => ref.read(liveFleetProvider.notifier).refresh(),
                ),
                Expanded(
                  child: isMobile
                      ? _MobileLayout(trucks: trucks)
                      : _DesktopLayout(trucks: trucks),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.count, required this.isMobile, required this.onRefresh});
  final int count;
  final bool isMobile;
  final VoidCallback onRefresh;

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
        if (isMobile && Navigator.of(context).canPop()) ...[
          IconButton(
            icon: Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        Text('Fleet Control Room',
            style: TextStyle(
                color: AppColors.textMain(context),
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.success.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('$count Active',
                style: TextStyle(
                    color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: onRefresh,
          icon: Icon(Icons.refresh, color: AppColors.textSub(context), size: 18),
          tooltip: 'Refresh fleet',
        ),
      ]),
    );
  }
}

// ── Desktop layout ───────────────────────────────────────────────────────────

class _DesktopLayout extends StatefulWidget {
  const _DesktopLayout({required this.trucks});
  final List<FleetTruck> trucks;

  @override
  State<_DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<_DesktopLayout> {
  FleetTruck? _selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.divider(context))),
            ),
            child: Column(
              children: [
                _FleetSummaryStrip(trucks: widget.trucks),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.trucks.length,
                    itemBuilder: (_, i) => _TruckCard(
                      truck: widget.trucks[i],
                      isSelected: _selected == widget.trucks[i],
                      onTap: () => setState(() => _selected = widget.trucks[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _FleetMap(
            trucks: widget.trucks,
            selected: _selected,
            onTap: (t) => setState(() => _selected = t),
          ),
        ),
      ],
    );
  }
}

// ── Mobile layout ────────────────────────────────────────────────────────────

class _MobileLayout extends StatefulWidget {
  const _MobileLayout({required this.trucks});
  final List<FleetTruck> trucks;

  @override
  State<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<_MobileLayout> {
  FleetTruck? _selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: _FleetMap(
            trucks: widget.trucks,
            selected: _selected,
            onTap: (t) => setState(() => _selected = t),
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: widget.trucks.length,
            itemBuilder: (_, i) => _TruckCard(
              truck: widget.trucks[i],
              isSelected: _selected == widget.trucks[i],
              onTap: () => setState(() => _selected = widget.trucks[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Fleet Map ────────────────────────────────────────────────────────────────

class _FleetMap extends StatelessWidget {
  const _FleetMap({required this.trucks, required this.selected, required this.onTap});
  final List<FleetTruck> trucks;
  final FleetTruck? selected;
  final ValueChanged<FleetTruck> onTap;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(20.9517, 85.0985),
        initialZoom: 6.8,
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
        // Geofence zone circles
        CircleLayer(
          circles: _kHubZones
              .map((hz) => CircleMarker(
                    point: hz.pos,
                    radius: 15000,
                    useRadiusInMeter: true,
                    color: AppColors.primary.withOpacity(0.06),
                    borderColor: AppColors.primary.withOpacity(0.25),
                    borderStrokeWidth: 1.5,
                  ))
              .toList(),
        ),
        // Hub labels
        MarkerLayer(
          markers: _kHubZones
              .map((hz) => Marker(
                    point: hz.pos,
                    width: 90,
                    height: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(hz.name,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 8,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                    ),
                  ))
              .toList(),
        ),
        // Truck markers
        MarkerLayer(
          markers: trucks.map((t) {
            final isActive = selected == t;
            final color = _statusColor(t.status);
            return Marker(
              point: t.pos,
              width: isActive ? 44 : 34,
              height: isActive ? 44 : 34,
              child: GestureDetector(
                onTap: () => onTap(t),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isActive ? Colors.white : Colors.black,
                        width: isActive ? 2.5 : 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: isActive ? 14 : 6,
                        spreadRadius: isActive ? 3 : 1,
                      )
                    ],
                  ),
                  child: Icon(Icons.local_shipping,
                      color: Colors.white, size: isActive ? 20 : 15),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'en_route':
        return AppColors.accent;
      case 'at_hub':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }
}

// ── Summary strip ────────────────────────────────────────────────────────────

class _FleetSummaryStrip extends StatelessWidget {
  const _FleetSummaryStrip({required this.trucks});
  final List<FleetTruck> trucks;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.sidebar(context),
      child: Row(children: [
        _FleetStat('En Route',
            '${trucks.where((t) => t.status == 'en_route').length}', AppColors.accent),
        _FleetStat('At Hub',
            '${trucks.where((t) => t.status == 'at_hub').length}', AppColors.primary),
        _FleetStat('Idle',
            '${trucks.where((t) => t.status == 'idle').length}', AppColors.textSecondary),
      ]),
    );
  }
}

class _FleetStat extends StatelessWidget {
  const _FleetStat(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value,
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
        Text(label,
            style: TextStyle(color: AppColors.labelText(context), fontSize: 10)),
      ]),
    );
  }
}

// ── Truck card ───────────────────────────────────────────────────────────────

// Deterministic cargo + destination + ETA from truck id hashCode
final _kCargos = [
  'Electronics (120kg)',
  'FMCG (85kg)',
  'Pharmaceuticals (40kg)',
  'Auto Parts (200kg)',
  'Textiles (150kg)',
];

final _kDestinations = [
  'Bhubaneswar HQ',
  'Cuttack Central',
  'Rourkela North',
  'Sambalpur Depot',
  'Berhampur South',
  'Balasore East',
  'Baripada Hub',
  'Angul Hub',
  'Puri Coastal',
  'Koraput Tribal',
];

class _TruckCard extends StatefulWidget {
  const _TruckCard({
    required this.truck,
    required this.isSelected,
    required this.onTap,
  });
  final FleetTruck truck;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_TruckCard> createState() => _TruckCardState();
}

class _TruckCardState extends State<_TruckCard> {
  bool _hovered = false;

  String get _vehicleType {
    final id = widget.truck.id.toUpperCase();
    if (id.contains('TRUCK')) return 'TRUCK';
    if (id.contains('VAN')) return 'VAN';
    if (id.contains('BIKE')) return 'BIKE';
    return 'VEHICLE';
  }

  String get _cargo {
    final idx = widget.truck.id.hashCode.abs() % _kCargos.length;
    return _kCargos[idx];
  }

  String get _destination {
    final idx = (widget.truck.id.hashCode.abs() ~/ 7) % _kDestinations.length;
    return _kDestinations[idx];
  }

  int get _etaMin {
    final speed = widget.truck.speedKmh;
    if (speed <= 0) return 0;
    final base = 20 + (widget.truck.id.hashCode.abs() % 160);
    return base;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'en_route':
        return AppColors.accent;
      case 'at_hub':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusC = _statusColor(widget.truck.status);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? AppColors.primary.withOpacity(0.08)
                    : AppColors.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: widget.isSelected
                        ? AppColors.primary.withOpacity(0.4)
                        : AppColors.border),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusC.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.local_shipping, color: statusC, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.truck.id,
                          style: TextStyle(
                              color: AppColors.textMain(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                      const SizedBox(height: 2),
                      Text(widget.truck.name,
                          style:
                              TextStyle(color: AppColors.textSub(context), fontSize: 11)),
                      Text('${widget.truck.speedKmh.toStringAsFixed(0)} km/h',
                          style: TextStyle(
                              color: AppColors.labelText(context), fontSize: 10)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusC.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                          widget.truck.status.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                              color: statusC,
                              fontSize: 8,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 6),
                    if (widget.truck.driverId.isNotEmpty)
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              recipientId: widget.truck.driverId,
                              recipientName: widget.truck.name,
                              recipientRole: 'driver',
                              recipientCustomId: widget.truck.id,
                            ),
                          ));
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.chat_bubble_outline,
                              color: AppColors.primary, size: 16),
                        ),
                      ),
                  ],
                ),
              ]),
            ),
          ),
          // Hover detail panel — positioned to the right of the card
          if (_hovered)
            Positioned(
              top: 0,
              left: 296, // card width is ~296, show just outside
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.sidebar(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(4, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_vehicleType,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _statusColor(widget.truck.status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.truck.status.replaceAll('_', ' '),
                          style: TextStyle(
                              color: _statusColor(widget.truck.status),
                              fontSize: 9,
                              fontWeight: FontWeight.w600),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(widget.truck.name,
                          style: TextStyle(
                              color: AppColors.textMain(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text(widget.truck.id,
                          style: TextStyle(
                              color: AppColors.labelText(context),
                              fontSize: 10,
                              fontFamily: 'monospace')),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: 8),
                      _DetailRow(Icons.speed,
                          '${widget.truck.speedKmh.toStringAsFixed(0)} km/h'),
                      _DetailRow(Icons.location_on_outlined,
                          '${widget.truck.pos.latitude.toStringAsFixed(4)}, ${widget.truck.pos.longitude.toStringAsFixed(4)}'),
                      _DetailRow(Icons.inventory_2_outlined, _cargo),
                      _DetailRow(Icons.flag_outlined, _destination),
                      if (widget.truck.speedKmh > 0)
                        _DetailRow(Icons.access_time_outlined,
                            'ETA: $_etaMin min'),
                      const SizedBox(height: 10),
                      // Message Driver button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                recipientId: widget.truck.driverId,
                                recipientName: widget.truck.name,
                                recipientRole: 'driver',
                                recipientCustomId: widget.truck.id,
                              ),
                            ));
                          },
                          icon: const Icon(Icons.chat_bubble_outline, size: 14),
                          label: const Text('Message Driver',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Icon(icon, size: 12, color: AppColors.labelText(context)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style:
                  TextStyle(color: AppColors.textSub(context), fontSize: 11)),
        ),
      ]),
    );
  }
}

// ── Hub zones ────────────────────────────────────────────────────────────────

class _HubZone {
  final String name;
  final LatLng pos;
  const _HubZone(this.name, this.pos);
}

const _kHubZones = [
  _HubZone('Bhubaneswar HQ', LatLng(20.2961, 85.8315)),
  _HubZone('Cuttack Central', LatLng(20.4625, 85.8830)),
  _HubZone('Rourkela North', LatLng(22.2270, 84.8536)),
  _HubZone('Sambalpur Depot', LatLng(21.4669, 83.9717)),
  _HubZone('Berhampur South', LatLng(19.3150, 84.7941)),
  _HubZone('Balasore East', LatLng(21.4942, 86.9355)),
  _HubZone('Baripada Hub', LatLng(21.9322, 86.7285)),
  _HubZone('Jharsuguda', LatLng(21.8553, 84.0064)),
  _HubZone('Angul Hub', LatLng(20.8380, 85.1010)),
  _HubZone('Kendrapara', LatLng(20.5012, 86.4211)),
  _HubZone('Koraput Tribal', LatLng(18.8135, 82.7123)),
  _HubZone('Puri Coastal', LatLng(19.8106, 85.8315)),
  _HubZone('Rayagada Hub', LatLng(19.1710, 83.4166)),
  _HubZone('Sundargarh', LatLng(22.1168, 84.0308)),
  _HubZone('Phulbani Hub', LatLng(20.4667, 84.2333)),
  _HubZone('Bhawanipatna', LatLng(19.8563, 83.1614)),
];
