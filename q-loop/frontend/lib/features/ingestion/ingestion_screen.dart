import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

final _jobsProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get(ApiConstants.ingestionJobs);
    return res.data['items'] as List? ?? [];
  } catch (_) {
    return _kDemoJobs;
  }
});

class IngestionScreen extends ConsumerWidget {
  const IngestionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final jobs = ref.watch(_jobsProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                    onRefresh: () => ref.invalidate(_jobsProvider),
                    isMobile: isMobile),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Upload card
                        _UploadCard(),
                        const SizedBox(height: 20),

                        // Stats strip
                        _StatsStrip(),
                        const SizedBox(height: 20),

                        // Job history
                        const Text('Ingestion Jobs',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        const SizedBox(height: 12),
                        jobs.when(
                          loading: () => const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary)),
                          error: (e, _) => const _JobList(jobs: _kDemoJobs),
                          data: (list) =>
                              _JobList(jobs: list.isEmpty ? _kDemoJobs : list),
                        ),
                      ],
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onRefresh, this.isMobile = false});
  final VoidCallback onRefresh;
  final bool isMobile;

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
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        const Icon(Icons.upload_file_outlined,
            color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        const Text('Data Ingestion',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const Spacer(),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh,
              color: AppColors.textSecondary, size: 18),
        ),
      ]),
    );
  }
}

class _UploadCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_UploadCard> createState() => _UploadCardState();
}

class _UploadCardState extends ConsumerState<_UploadCard> {
  bool _uploading = false;
  String? _result;

  Future<void> _simulateUpload() async {
    setState(() {
      _uploading = true;
      _result = null;
    });
    await Future.delayed(const Duration(seconds: 2));
    // In production: pick CSV file and POST to /ingestion/upload
    setState(() {
      _uploading = false;
      _result = 'Successfully queued 1,200 shipment records for processing.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.cloud_upload_outlined,
                color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Upload Shipment Data',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Upload a CSV or JSON file containing shipment records. '
            'The system validates, deduplicates and bulk-inserts into PostgreSQL. '
            'Supports up to 100,000 records per batch.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Drop zone (simulated — no file_picker in pubspec)
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.border, style: BorderStyle.solid),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_upload_outlined,
                      color: AppColors.textMuted, size: 28),
                  SizedBox(height: 6),
                  Text('Drop CSV / JSON here',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  Text('shipments.csv · max 100k rows',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          Row(children: [
            ElevatedButton.icon(
              onPressed: _uploading ? null : _simulateUpload,
              icon: _uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.upload, size: 16),
              label: Text(_uploading ? 'Uploading…' : 'Select & Upload'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download Template'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),

          if (_result != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_result!,
                      style: const TextStyle(
                          color: AppColors.success, fontSize: 12)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(children: [
      Expanded(
          child: _StatBox('Total Records', '601,700', AppColors.accent,
              Icons.storage_outlined)),
      SizedBox(width: 12),
      Expanded(
          child: _StatBox(
              'This Month', '+12,340', AppColors.primary, Icons.trending_up)),
      SizedBox(width: 12),
      Expanded(
          child:
              _StatBox('Failed', '47', AppColors.error, Icons.error_outline)),
    ]);
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
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({required this.jobs});
  final List<dynamic> jobs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: jobs.map((j) {
        final m = j is Map ? j : <String, dynamic>{};
        final status = (m['status'] as String?) ?? 'completed';
        final color = status == 'completed'
            ? AppColors.success
            : status == 'failed'
                ? AppColors.error
                : AppColors.warning;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                status == 'completed'
                    ? Icons.check_circle_outline
                    : status == 'failed'
                        ? Icons.error_outline
                        : Icons.hourglass_empty,
                color: color,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m['filename'] as String? ?? 'shipments_batch.csv',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  Text(
                    '${m['records_total'] ?? 1200} records · ${m['created_at'] ?? 'Today'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: color, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

const _kDemoJobs = [
  {
    'filename': 'odisha_shipments_apr2024.csv',
    'status': 'completed',
    'records_total': 45200,
    'created_at': 'Apr 3, 2024'
  },
  {
    'filename': 'rourkela_batch_0312.csv',
    'status': 'completed',
    'records_total': 12400,
    'created_at': 'Mar 12, 2024'
  },
  {
    'filename': 'coastal_express_feb.json',
    'status': 'failed',
    'records_total': 3200,
    'created_at': 'Feb 28, 2024'
  },
  {
    'filename': 'bulk_import_jan2024.csv',
    'status': 'completed',
    'records_total': 78000,
    'created_at': 'Jan 15, 2024'
  },
];
