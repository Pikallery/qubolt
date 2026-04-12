import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _returnsProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.returns);
  return res.data as List<dynamic>;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});

  @override
  ConsumerState<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends ConsumerState<ReturnsScreen> {
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final returnsAsync = ref.watch(_returnsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface(context),
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                    isMobile: isMobile,
                    onRequestReturn: () => _showRequestDialog(context)),
                Expanded(
                  child: returnsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Error: $e',
                          style: const TextStyle(color: AppColors.error)),
                    ),
                    data: (returns) => returns.isEmpty
                        ? const _EmptyState()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _StatsRow(returns: returns, isMobile: isMobile),
                                const SizedBox(height: 24),
                                ...returns.map((r) => _ReturnCard(
                                      ret: r as Map<String, dynamic>,
                                      onAction: (action) => _handleAction(
                                          context,
                                          r['id'] as String? ?? '',
                                          action),
                                    )),
                              ],
                            ),
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

  Future<void> _showRequestDialog(BuildContext context) async {
    final shipmentIdCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String reason = 'defective';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('Request Return', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: shipmentIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Shipment ID',
                    hintText: 'Paste the original shipment UUID',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: AppColors.cardBg,
                  items: const [
                    DropdownMenuItem(
                        value: 'defective', child: Text('Defective')),
                    DropdownMenuItem(
                        value: 'wrong_item', child: Text('Wrong Item')),
                    DropdownMenuItem(
                        value: 'customer_changed_mind',
                        child: Text('Changed Mind')),
                    DropdownMenuItem(
                        value: 'damaged', child: Text('Damaged in Transit')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setDialogState(() => reason = v ?? reason),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pickup Address (optional)',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (shipmentIdCtrl.text.trim().isEmpty) return;
                try {
                  final dio = ref.read(dioProvider);
                  await dio.post(ApiConstants.returnsRequest, data: {
                    'shipment_id': shipmentIdCtrl.text.trim(),
                    'reason': reason,
                    if (addressCtrl.text.trim().isNotEmpty)
                      'pickup_address': addressCtrl.text.trim(),
                    if (notesCtrl.text.trim().isNotEmpty)
                      'notes': notesCtrl.text.trim(),
                  });
                  Navigator.pop(ctx, true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
              ),
              child: const Text('Submit Return'),
            ),
          ],
        ),
      ),
    );
    if (result == true) ref.invalidate(_returnsProvider);
  }

  Future<void> _handleAction(
      BuildContext context, String id, String action) async {
    if (id.isEmpty) return;
    try {
      final dio = ref.read(dioProvider);
      String endpoint;
      switch (action) {
        case 'assign':
          endpoint = ApiConstants.returnAssign(id);
          break;
        case 'pickup':
          endpoint = ApiConstants.returnPickup(id);
          break;
        case 'received':
          endpoint = ApiConstants.returnReceived(id);
          break;
        default:
          return;
      }
      await dio.put(endpoint);
      ref.invalidate(_returnsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Return ${action}ed successfully'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isMobile, required this.onRequestReturn});
  final bool isMobile;
  final VoidCallback onRequestReturn;

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
        if (isMobile) ...[
          IconButton(
            icon: Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        Text('Returns & Reverse Logistics',
            style: TextStyle(
                color: AppColors.surface(context) == AppColors.lightScaffoldBg
                    ? AppColors.lightTextPrimary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: onRequestReturn,
          icon: const Icon(Icons.assignment_return, size: 16),
          label: const Text('Request Return'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ]),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.returns, required this.isMobile});
  final List<dynamic> returns;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    int pending = 0, assigned = 0, inTransit = 0, completed = 0;
    for (final r in returns) {
      final s = (r as Map<String, dynamic>)['status'] as String? ?? '';
      if (s == 'return_pending') {
        pending++;
      } else if (s == 'return_assigned')
        assigned++;
      else if (s == 'return_in_transit')
        inTransit++;
      else if (s == 'return_completed') completed++;
    }
    final cards = [
      _StatCard('Total', '${returns.length}', AppColors.textPrimary),
      _StatCard('Pending', '$pending', AppColors.warning),
      _StatCard('In Transit', '$inTransit', AppColors.accent),
      _StatCard('Completed', '$completed', AppColors.success),
    ];
    return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: cards
            .map((c) => SizedBox(width: isMobile ? 140 : 180, child: c))
            .toList());
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(label,
            style:
                TextStyle(color: AppColors.labelText(context), fontSize: 12)),
      ]),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.ret, required this.onAction});
  final Map<String, dynamic> ret;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final status = ret['status'] as String? ?? 'return_pending';
    final reason =
        ret['return_reason'] as String? ?? ret['reason'] as String? ?? '—';
    final id = ret['id'] as String? ?? '';
    final extId = ret['external_id'] as String? ?? id;
    final created = ret['created_at'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.sidebar(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Row(children: [
        Icon(Icons.assignment_return, color: _statusColor(status), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(extId.length > 24 ? '${extId.substring(0, 20)}…' : extId,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 4),
            Text('Reason: ${reason.replaceAll('_', ' ')}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.labelText(context))),
            if (created.isNotEmpty)
              Text(
                  created.substring(
                      0, created.length > 16 ? 16 : created.length),
                  style: TextStyle(
                      fontSize: 11, color: AppColors.labelText(context))),
          ]),
        ),
        _ReturnStatusChip(status),
        const SizedBox(width: 12),
        if (status == 'return_pending')
          _ActionButton('Assign', AppColors.primary, () => onAction('assign')),
        if (status == 'return_assigned')
          _ActionButton('Pickup', AppColors.accent, () => onAction('pickup')),
        if (status == 'return_in_transit')
          _ActionButton(
              'Received', AppColors.success, () => onAction('received')),
      ]),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'return_pending':
        return AppColors.warning;
      case 'return_assigned':
        return AppColors.primary;
      case 'return_in_transit':
        return AppColors.accent;
      case 'return_completed':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.label, this.color, this.onTap);
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _ReturnStatusChip extends StatelessWidget {
  const _ReturnStatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final label =
        status.replaceAll('return_', '').replaceAll('_', ' ').toUpperCase();
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Color _color() {
    switch (status) {
      case 'return_pending':
        return AppColors.warning;
      case 'return_assigned':
        return AppColors.primary;
      case 'return_in_transit':
        return AppColors.accent;
      case 'return_completed':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_return_outlined,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('No returns yet',
              style: TextStyle(color: AppColors.textSub(context), fontSize: 15)),
          const SizedBox(height: 6),
          Text('Click "Request Return" to initiate a reverse logistics flow.',
              style:
                  TextStyle(color: AppColors.labelText(context), fontSize: 13),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
