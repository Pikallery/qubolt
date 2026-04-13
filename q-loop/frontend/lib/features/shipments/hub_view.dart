import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/widgets/api_error_widget.dart';
import '../auth/domain/auth_provider.dart';
import '../comms/chat_screen.dart';
import '../comms/comms_provider.dart';

/// Hub Operator view — web-compatible (no camera dependency).
/// Supports:
///  - Manual shipment ID entry to validate handshake (QR code data paste)
///  - View incoming / outgoing shipments for this hub
///  - Contact driver and manager via Twilio SMS/call
class HubView extends ConsumerStatefulWidget {
  const HubView({super.key});

  @override
  ConsumerState<HubView> createState() => _HubViewState();
}

class _HubViewState extends ConsumerState<HubView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    const hubId = 'HUB-751001-01'; // resolved from auth.userId in production

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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warehouse_outlined,
                  color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('Hub Operations',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ]),
            Text(hubId,
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace')),
          ],
        ),
        actions: [
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
          tabs: const [
            Tab(text: 'Scan / Validate'),
            Tab(text: 'Shipments'),
            Tab(text: 'Contact'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ScanTab(),
          _ShipmentsTab(),
          _ContactTab(),
        ],
      ),
    );
  }
}

// ── Tab 1: Scan / Validate ────────────────────────────────────────────────────

/// Live mobile_scanner with a UPI-style animated horizontal scan line
/// sweeping over the QR target square. On a successful scan we POST to
/// /auth/qr-scan, surface the result inline, and auto-reset after a few seconds.
class _ScanTab extends ConsumerStatefulWidget {
  const _ScanTab();

  @override
  ConsumerState<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends ConsumerState<_ScanTab>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  final TextEditingController _manualCtrl = TextEditingController();
  late final AnimationController _sweep;
  bool _processing = false;
  bool _torchOn = false;
  bool _manualMode = false;
  _ScanResult? _result;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sweep.dispose();
    _scanner.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _result != null) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;
    await _processPayload(raw);
  }

  Future<void> _processPayload(String raw) async {
    setState(() {
      _processing = true;
      _result = null;
    });

    try {
      // Accept either a JSON QR payload or a bare token / shipment id.
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {}

      final tokenHash = payload?['sig'] ?? raw;
      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.qrScan, data: {
        'token_hash': tokenHash,
        'scan_lat': null,
        'scan_lon': null,
      });

      final data = res.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _result = _ScanResult(
          success: data['success'] == true,
          message: data['message'] ?? 'Processed',
          shipmentId: data['shipment_id'],
          eventType: data['event_type'],
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = _ScanResult(
          success: false,
          message: 'Validation failed: ${e.toString().split(':').last.trim()}',
        );
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }

    // Auto-clear so the next scan can fire
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _result = null);
  }

  Future<void> _validateManual() async {
    final raw = _manualCtrl.text.trim();
    if (raw.isEmpty) return;
    await _processPayload(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Live camera viewport with UPI-style overlay ────────────────────
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!_manualMode)
                MobileScanner(
                  controller: _scanner,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) {
                    return _CameraErrorView(
                      error: error,
                      onSwitchToManual: () =>
                          setState(() => _manualMode = true),
                    );
                  },
                )
              else
                Container(color: Colors.black),
              if (!_manualMode)
                _UpiScanOverlay(
                  sweep: _sweep,
                  processing: _processing,
                  result: _result,
                ),
              // Top-right control row
              Positioned(
                top: 12,
                right: 12,
                child: Row(children: [
                  _CircleIconButton(
                    icon: _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                    color: _torchOn ? AppColors.warning : Colors.white,
                    onTap: _manualMode
                        ? null
                        : () {
                            _scanner.toggleTorch();
                            setState(() => _torchOn = !_torchOn);
                          },
                  ),
                  const SizedBox(width: 8),
                  _CircleIconButton(
                    icon: _manualMode
                        ? Icons.qr_code_scanner
                        : Icons.keyboard_alt_outlined,
                    color: Colors.white,
                    onTap: () => setState(() => _manualMode = !_manualMode),
                  ),
                ]),
              ),
              // Bottom hint chip
              if (!_manualMode && _result == null)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.4)),
                      ),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.qr_code_2,
                            color: AppColors.primary, size: 14),
                        SizedBox(width: 6),
                        Text('Align QR inside the frame',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Result / manual entry / quick stats panel ──────────────────────
        Expanded(
          flex: 4,
          child: Container(
            color: AppColors.scaffoldBg,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_manualMode) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            color: AppColors.primary, size: 16),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Manual mode: paste QR payload or enter shipment ID.',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _InputCard(
                      controller: _manualCtrl,
                      label: 'QR Payload or Shipment ID',
                      hint: 'Paste payload or type id…',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _processing ? null : _validateManual,
                        icon: _processing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.verified_outlined, size: 16),
                        label: Text(
                            _processing ? 'Validating…' : 'Validate Handshake'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_result != null) ...[
                    _ResultCard(result: _result!),
                    const SizedBox(height: 16),
                  ],
                  _QuickStats(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── UPI-style scan overlay ────────────────────────────────────────────────────

class _UpiScanOverlay extends StatelessWidget {
  const _UpiScanOverlay({
    required this.sweep,
    required this.processing,
    required this.result,
  });
  final AnimationController sweep;
  final bool processing;
  final _ScanResult? result;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            math.min(constraints.maxWidth, constraints.maxHeight) * 0.65;
        final boxSize = side.clamp(180.0, 320.0);

        Color frameColor = AppColors.primary;
        if (result != null) {
          frameColor = result!.success ? AppColors.success : AppColors.error;
        }

        return Stack(
          children: [
            // Dark dimmed background
            Container(color: Colors.black.withOpacity(0.55)),
            // Cut-out target area
            Center(
              child: Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.85),
                      blurRadius: 0,
                      spreadRadius: 2000,
                    ),
                  ],
                ),
              ),
            ),
            // Animated frame + sweep line
            Center(
              child: SizedBox(
                width: boxSize,
                height: boxSize,
                child: Stack(
                  children: [
                    // Corner brackets
                    CustomPaint(
                      size: Size(boxSize, boxSize),
                      painter: _BracketPainter(color: frameColor),
                    ),
                    // Sweeping scan line (UPI style)
                    if (result == null)
                      AnimatedBuilder(
                        animation: sweep,
                        builder: (_, __) {
                          final t = Curves.easeInOut.transform(sweep.value);
                          final dy = 12 + (boxSize - 24) * t;
                          return Positioned(
                            top: dy,
                            left: 14,
                            right: 14,
                            child: Container(
                              height: 2.5,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    frameColor.withOpacity(0),
                                    frameColor,
                                    frameColor.withOpacity(0),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: frameColor.withOpacity(0.6),
                                    blurRadius: 12,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    // Center processing indicator
                    if (processing)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: frameColor),
                          ),
                          child: const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: AppColors.primary),
                          ),
                        ),
                      ),
                    // Result icon overlay
                    if (result != null && !processing)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: frameColor, width: 2),
                          ),
                          child: Icon(
                            result!.success ? Icons.check_circle : Icons.cancel,
                            color: frameColor,
                            size: 44,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    // Top-left
    canvas.drawLine(const Offset(0, 0), const Offset(len, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, len), paint);
    // Top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    canvas.drawLine(
        Offset(0, size.height), Offset(0, size.height - len), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - len, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - len), paint);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter old) => old.color != color;
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({
    required this.error,
    required this.onSwitchToManual,
  });
  final MobileScannerException error;
  final VoidCallback onSwitchToManual;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: AppColors.warning, size: 44),
              const SizedBox(height: 12),
              const Text('Camera unavailable',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                error.errorDetails?.message ??
                    'Grant camera permission or switch to manual entry.',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: onSwitchToManual,
                icon: const Icon(Icons.keyboard_alt_outlined, size: 16),
                label: const Text('Use Manual Entry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today\'s Hub Summary',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
        SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _StatBox(
                  'Incoming', '24', AppColors.accent, Icons.arrow_downward)),
          SizedBox(width: 12),
          Expanded(
              child: _StatBox(
                  'Outgoing', '18', AppColors.primary, Icons.arrow_upward)),
          SizedBox(width: 12),
          Expanded(
              child: _StatBox(
                  'Pending', '6', AppColors.warning, Icons.hourglass_bottom)),
        ]),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox(this.label, this.value, this.color, this.icon);
  final String label, value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ]),
    );
  }
}

// ── Tab 2: Shipments ──────────────────────────────────────────────────────────

class _ShipmentsTab extends ConsumerStatefulWidget {
  const _ShipmentsTab();

  @override
  ConsumerState<_ShipmentsTab> createState() => _ShipmentsTabState();
}

class _ShipmentsTabState extends ConsumerState<_ShipmentsTab> {
  List<Map<String, dynamic>> _shipments = [];
  bool _loading = true;
  String? _error;
  String _filter = 'in_transit'; // default to transit — hub's primary view
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh every 20 s so newly-arrived drivers appear without manual pull
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/shipments',
          queryParameters: {'status': _filter, 'page_size': 30});
      if (!mounted) return;
      setState(() {
        _shipments = List<Map<String, dynamic>>.from(res.data['items'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['pending', 'in_transit', 'delivered'].map((s) {
                final active = _filter == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s.replaceAll('_', ' ').toUpperCase()),
                    selected: active,
                    onSelected: (_) {
                      setState(() => _filter = s);
                      _load();
                    },
                    selectedColor: AppColors.primary.withOpacity(0.2),
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(
                        color: active
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.normal),
                    backgroundColor: AppColors.cardBg,
                    side: BorderSide(
                        color: active
                            ? AppColors.primary.withOpacity(0.4)
                            : AppColors.border),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? ApiErrorWidget(error: _error!, onRetry: _load)
                  : _shipments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 48,
                                  color: AppColors.textMuted.withOpacity(0.5)),
                              const SizedBox(height: 12),
                              const Text('No shipments here',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _shipments.length,
                            itemBuilder: (_, i) => _HubShipmentCard(
                              shipment: _shipments[i],
                              onConfirmed: _load,
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

class _HubShipmentCard extends ConsumerStatefulWidget {
  const _HubShipmentCard({required this.shipment, this.onConfirmed});
  final Map<String, dynamic> shipment;
  final VoidCallback? onConfirmed;

  @override
  ConsumerState<_HubShipmentCard> createState() => _HubShipmentCardState();
}

class _HubShipmentCardState extends ConsumerState<_HubShipmentCard> {
  bool _confirming = false;
  bool _driverArrived = false;

  @override
  void initState() {
    super.initState();
    final status = widget.shipment['status'] as String? ?? '';
    if (status == 'in_transit') _checkDriverArrived();
  }

  Future<void> _checkDriverArrived() async {
    final id = widget.shipment['id'] as String? ?? '';
    if (id.isEmpty) return;
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/shipments/$id/events');
      final events = List<Map<String, dynamic>>.from(res.data as List? ?? []);
      final arrived =
          events.any((e) => e['event_type'] == 'driver_arrived');
      if (mounted) setState(() => _driverArrived = arrived);
    } catch (_) {}
  }

  Future<void> _confirmArrival() async {
    final id = widget.shipment['id'] as String? ?? '';
    if (id.isEmpty) return;
    setState(() => _confirming = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/shipments/$id', data: {'status': 'delivered'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Arrival confirmed — manager notified'),
          backgroundColor: AppColors.success,
        ));
        widget.onConfirmed?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.shipment['status'] ?? 'pending';
    final color = AppColors.statusColor(status);
    final isInTransit = status == 'in_transit';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isInTransit ? AppColors.warning.withValues(alpha: 0.5) : AppColors.border,
          width: isInTransit ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.inventory_2_outlined, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  widget.shipment['external_id'] ??
                      (widget.shipment['id']?.toString().substring(0, 8) ?? '—'),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.shipment['region'] ?? 'Unknown'} · ${widget.shipment['package_type'] ?? 'General'}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: color, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ]),
          if (isInTransit) ...[
            const SizedBox(height: 8),
            // Driver arrived badge
            if (_driverArrived)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.directions_run,
                      size: 13, color: AppColors.success),
                  SizedBox(width: 6),
                  Text('Driver has arrived at this hub — ready for handoff',
                      style: TextStyle(
                          color: AppColors.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: ElevatedButton.icon(
                onPressed: _confirming ? null : _confirmArrival,
                icon: _confirming
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.check_circle_outline, size: 15),
                label: Text(_confirming ? 'Confirming…' : 'Confirm Arrival'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Tab 3: Contact ────────────────────────────────────────────────────────────

class _ContactTab extends ConsumerWidget {
  const _ContactTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(chatUsersProvider);

    return contacts.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, __) => _HubContactList(
          contacts: const [],
          onRefresh: () => ref.invalidate(chatUsersProvider)),
      data: (list) => _HubContactList(
        contacts: list,
        onRefresh: () => ref.invalidate(chatUsersProvider),
      ),
    );
  }
}

class _HubContactList extends ConsumerWidget {
  const _HubContactList({required this.contacts, required this.onRefresh});
  final List<Map<String, dynamic>> contacts;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleColors = <String, Color>{
      'driver': AppColors.accent,
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
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: const Row(children: [
              Icon(Icons.hub_outlined, color: AppColors.primary, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Messages are stored in the database. Tap Chat to open a conversation thread.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
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
                  Text(
                    'Drivers and managers will appear here',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            )
          else ...[
            Text(
              '${contacts.length} Contact${contacts.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
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
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            recipientId: userId,
                            recipientName: name,
                            recipientRole: role,
                            recipientCustomId: customId,
                            recipientOrg: u['organization_name'] as String?,
                          ),
                        ),
                      );
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
      case 'driver':
        return Icons.local_shipping_outlined;
      case 'manager':
      case 'admin':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outlined;
    }
  }

  String _roleBadge(String role) {
    switch (role) {
      case 'driver':
        return 'DRIVER';
      case 'manager':
        return 'MANAGER';
      case 'admin':
        return 'ADMIN';
      default:
        return role.toUpperCase();
    }
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _ScanResult {
  final bool success;
  final String message;
  final String? shipmentId;
  final String? eventType;
  const _ScanResult(
      {required this.success,
      required this.message,
      this.shipmentId,
      this.eventType});
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final _ScanResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.success ? AppColors.success : AppColors.error;
    final icon = result.success ? Icons.check_circle : Icons.cancel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(result.success ? 'Handshake Complete!' : 'Validation Failed',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          Text(result.message,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          if (result.shipmentId != null) ...[
            const SizedBox(height: 8),
            Text('Shipment: ${result.shipmentId}',
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ],
          if (result.eventType != null)
            Text('Event: ${result.eventType}',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label, hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        filled: true,
        fillColor: AppColors.cardBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    );
  }
}
