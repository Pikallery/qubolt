import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _partnersProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.partners);
  return res.data as List<dynamic>;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final partnersAsync = ref.watch(_partnersProvider);

    return Scaffold(
      backgroundColor: AppColors.surface(context),
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                    isMobile: isMobile, onAdd: () => _showAddDialog(context)),
                Expanded(
                  child: partnersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Error: $e',
                          style: const TextStyle(color: AppColors.error)),
                    ),
                    data: (partners) => partners.isEmpty
                        ? const _EmptyState()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: partners
                                  .map((p) => _PartnerCard(
                                      partner: p as Map<String, dynamic>,
                                      onTap: () => _showDetail(context, p)))
                                  .toList(),
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

  Future<void> _showAddDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final endpointCtrl = TextEditingController();
    final regionsCtrl = TextEditingController();
    final modes = <String>{};
    final vehicles = <String>{};

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('Add Delivery Partner',
              style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Partner Name *',
                      border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Contact Phone', border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endpointCtrl,
                  decoration: const InputDecoration(
                      labelText: 'API Endpoint (optional)',
                      border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Supported Modes',
                        style: TextStyle(fontSize: 12))),
                Wrap(
                    spacing: 8,
                    children: ['standard', 'express', 'same_day', 'overnight']
                        .map(
                          (m) => FilterChip(
                            label: Text(m.replaceAll('_', ' '),
                                style: const TextStyle(fontSize: 11)),
                            selected: modes.contains(m),
                            onSelected: (v) => setDialogState(
                                () => v ? modes.add(m) : modes.remove(m)),
                            selectedColor: AppColors.primary.withOpacity(0.2),
                          ),
                        )
                        .toList()),
                const SizedBox(height: 12),
                const Align(
                    alignment: Alignment.centerLeft,
                    child:
                        Text('Vehicle Types', style: TextStyle(fontSize: 12))),
                Wrap(
                    spacing: 8,
                    children: ['bike', 'van', 'truck', 'three_wheeler']
                        .map(
                          (v) => FilterChip(
                            label: Text(v.replaceAll('_', ' '),
                                style: const TextStyle(fontSize: 11)),
                            selected: vehicles.contains(v),
                            onSelected: (sel) => setDialogState(() =>
                                sel ? vehicles.add(v) : vehicles.remove(v)),
                            selectedColor: AppColors.accent.withOpacity(0.2),
                          ),
                        )
                        .toList()),
                const SizedBox(height: 12),
                TextField(
                  controller: regionsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Active Regions (comma-separated)',
                    hintText: 'e.g. Bhubaneswar, Cuttack, Rourkela',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  final dio = ref.read(dioProvider);
                  await dio.post(ApiConstants.partners, data: {
                    'name': nameCtrl.text.trim(),
                    if (phoneCtrl.text.trim().isNotEmpty)
                      'contact_phone': phoneCtrl.text.trim(),
                    if (endpointCtrl.text.trim().isNotEmpty)
                      'api_endpoint': endpointCtrl.text.trim(),
                    'supported_modes': modes.toList(),
                    'supported_vehicle_types': vehicles.toList(),
                    'active_regions': regionsCtrl.text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList(),
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
                  foregroundColor: Colors.black),
              child: const Text('Create Partner'),
            ),
          ],
        ),
      ),
    );
    if (result == true) ref.invalidate(_partnersProvider);
  }

  void _showDetail(BuildContext context, Map<String, dynamic> partner) {
    final name = partner['name'] as String? ?? '—';
    final phone = partner['contact_phone'] as String? ?? '—';
    final modes = (partner['supported_modes'] as List?)?.cast<String>() ?? [];
    final vehicles =
        (partner['supported_vehicle_types'] as List?)?.cast<String>() ?? [];
    final regions = (partner['active_regions'] as List?)?.cast<String>() ?? [];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: Text(name, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Phone: $phone', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                if (modes.isNotEmpty) ...[
                  const Text('Modes',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                      spacing: 6,
                      children: modes
                          .map((m) => Chip(
                                label: Text(m.replaceAll('_', ' '),
                                    style: const TextStyle(fontSize: 11)),
                                backgroundColor:
                                    AppColors.primary.withOpacity(0.12),
                              ))
                          .toList()),
                  const SizedBox(height: 12),
                ],
                if (vehicles.isNotEmpty) ...[
                  const Text('Vehicles',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                      spacing: 6,
                      children: vehicles
                          .map((v) => Chip(
                                label: Text(v.replaceAll('_', ' '),
                                    style: const TextStyle(fontSize: 11)),
                                backgroundColor:
                                    AppColors.accent.withOpacity(0.12),
                              ))
                          .toList()),
                  const SizedBox(height: 12),
                ],
                if (regions.isNotEmpty) ...[
                  const Text('Regions',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                      spacing: 6,
                      children: regions
                          .map((r) => Chip(
                                label: Text(r,
                                    style: const TextStyle(fontSize: 11)),
                                backgroundColor:
                                    AppColors.success.withOpacity(0.12),
                              ))
                          .toList()),
                ],
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isMobile, required this.onAdd});
  final bool isMobile;
  final VoidCallback onAdd;

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
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        Text('Delivery Partners',
            style: TextStyle(
                color: AppColors.surface(context) == AppColors.lightScaffoldBg
                    ? AppColors.lightTextPrimary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Partner'),
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

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.partner, required this.onTap});
  final Map<String, dynamic> partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = partner['name'] as String? ?? '—';
    final phone = partner['contact_phone'] as String? ?? '';
    final modes = (partner['supported_modes'] as List?)?.cast<String>() ?? [];
    final vehicles =
        (partner['supported_vehicle_types'] as List?)?.cast<String>() ?? [];
    final regions = (partner['active_regions'] as List?)?.cast<String>() ?? [];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.sidebar(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider(context)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.handshake_outlined,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  if (phone.isNotEmpty)
                    Text(phone,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.labelText(context))),
                ])),
          ]),
          if (modes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
                spacing: 4,
                runSpacing: 4,
                children: modes
                    .map((m) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(m.replaceAll('_', ' '),
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList()),
          ],
          if (vehicles.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
                spacing: 4,
                runSpacing: 4,
                children: vehicles
                    .map((v) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(v.replaceAll('_', ' '),
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList()),
          ],
          if (regions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(regions.join(', '),
                style: TextStyle(
                    fontSize: 11, color: AppColors.labelText(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    );
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
          const Icon(Icons.handshake_outlined,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('No delivery partners',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 6),
          Text('Click "Add Partner" to register your first delivery partner.',
              style:
                  TextStyle(color: AppColors.labelText(context), fontSize: 13),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
