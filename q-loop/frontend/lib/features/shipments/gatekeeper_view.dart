import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/widgets/notification_bell.dart';

/// Gatekeeper mobile view — scans driver QR codes to confirm pickup / delivery.
/// Implements the 3-way digital handshake:
///   Step 2: Gatekeeper scans QR code
///   Step 3: Backend validates + emits ShipmentEvent
class GatekeeperView extends ConsumerStatefulWidget {
  const GatekeeperView({super.key});

  @override
  ConsumerState<GatekeeperView> createState() => _GatekeeperViewState();
}

class _GatekeeperViewState extends ConsumerState<GatekeeperView> {
  final MobileScannerController _scanner = MobileScannerController();
  bool _processing = false;
  _ScanResult? _lastResult;
  bool _torchOn = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() {
      _processing = true;
    });

    try {
      final payload = _parseQRPayload(barcode!.rawValue!);
      if (payload == null) {
        setState(() {
          _lastResult = const _ScanResult(
            success: false,
            message: 'Invalid QR format. Not a Qubolt handshake code.',
          );
          _processing = false;
        });
        return;
      }

      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.qrScan, data: {
        'token_hash': payload['sig'],
        'scan_lat': null,
        'scan_lon': null,
      });

      final data = res.data as Map<String, dynamic>;
      setState(() {
        _lastResult = _ScanResult(
          success: data['success'] == true,
          message: data['message'] ?? '',
          shipmentId: data['shipment_id'],
          eventType: data['event_type'],
        );
        _processing = false;
      });
    } catch (e) {
      setState(() {
        _lastResult = _ScanResult(
          success: false,
          message: 'Scan failed: ${e.toString()}',
        );
        _processing = false;
      });
    }

    // Auto-reset after 3 seconds
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() {
        _lastResult = null;
      });
    }
  }

  Map<String, dynamic>? _parseQRPayload(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.sidebarBg,
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 20),
          SizedBox(width: 8),
          Text('Hub Scanner',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16)),
        ]),
        actions: [
          const NotificationBell(),
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
              color: _torchOn ? AppColors.warning : AppColors.textSecondary,
            ),
            onPressed: () {
              _scanner.toggleTorch();
              setState(() {
                _torchOn = !_torchOn;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Scanner viewport ──────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scanner,
                  onDetect: _onDetect,
                ),
                // Scan overlay
                _ScanOverlay(processing: _processing),
              ],
            ),
          ),

          // ── Result panel ──────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Container(
              color: AppColors.sidebarBg,
              child: _lastResult == null
                  ? _IdlePanel()
                  : _ResultPanel(result: _lastResult!),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan overlay ──────────────────────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.processing});
  final bool processing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dark vignette
        Container(color: Colors.black.withOpacity(0.35)),
        // Corner brackets
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: CustomPaint(painter: _BracketPainter()),
          ),
        ),
        if (processing)
          const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
      ],
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    // Top-left
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, len), paint);
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
  bool shouldRepaint(_) => false;
}

// ── Result panel ─────────────────────────────────────────────────────────────

class _ScanResult {
  final bool success;
  final String message;
  final String? shipmentId;
  final String? eventType;
  const _ScanResult({
    required this.success,
    required this.message,
    this.shipmentId,
    this.eventType,
  });
}

class _IdlePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2,
              size: 48, color: AppColors.primary.withOpacity(0.4)),
          const SizedBox(height: 12),
          const Text('Point camera at driver\'s QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          const Text('3-way handshake · HMAC-SHA256 · Single use',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});
  final _ScanResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.success ? AppColors.success : AppColors.error;
    final icon = result.success ? Icons.check_circle : Icons.cancel;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(
            result.success ? 'Handshake Complete' : 'Scan Failed',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(result.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          if (result.shipmentId != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                _ResultRow(
                    'Shipment', '${result.shipmentId!.substring(0, 8)}...'),
                if (result.eventType != null)
                  _ResultRow('Event', result.eventType!),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
