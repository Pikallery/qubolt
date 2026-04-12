import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../dashboard/widgets/dark_sidebar.dart';

final _usersProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get('/users');
    return res.data['items'] as List? ?? [];
  } catch (_) {
    return _kDemoUsers;
  }
});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final users = ref.watch(_usersProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                    onRefresh: () => ref.invalidate(_usersProvider),
                    isMobile: isMobile),
                Expanded(
                  child: users.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                    error: (e, _) => _UserList(
                        users: _kDemoUsers, onRefresh: () => ref.invalidate(_usersProvider)),
                    data: (list) => _UserList(
                        users: list.isEmpty ? _kDemoUsers : list,
                        onRefresh: () => ref.invalidate(_usersProvider)),
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
        Icon(Icons.people_outline, color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        Text('User Management',
            style: TextStyle(
                color: AppColors.textMain(context),
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const Spacer(),
        IconButton(
          onPressed: onRefresh,
          icon: Icon(Icons.refresh,
              color: AppColors.textSub(context), size: 18),
        ),
      ]),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({required this.users, required this.onRefresh});
  final List<dynamic> users;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Role summary strip
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            _RolePill(
                'Drivers',
                users.where((u) => _role(u) == 'driver').length,
                AppColors.accent),
            const SizedBox(width: 8),
            _RolePill(
                'Hub Ops',
                users.where((u) => _role(u) == 'gatekeeper').length,
                AppColors.primary),
            const SizedBox(width: 8),
            _RolePill(
                'Managers',
                users.where((u) => _role(u) == 'manager').length,
                AppColors.warning),
            const SizedBox(width: 8),
            _RolePill('Admins', users.where((u) => _role(u) == 'admin').length,
                AppColors.error),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: users.length,
            itemBuilder: (_, i) =>
                _UserCard(user: users[i], onRefresh: onRefresh),
          ),
        ),
      ],
    );
  }

  String _role(dynamic u) => (u is Map ? u['role'] : null) ?? '';
}

class _RolePill extends StatelessWidget {
  const _RolePill(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text('$count $label',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user, required this.onRefresh});
  final dynamic user;
  final VoidCallback onRefresh;

  String get _id {
    final m = user is Map ? user as Map : <String, dynamic>{};
    final role = (m['role'] as String?) ?? 'viewer';
    final email = (m['email'] as String?) ?? '';
    final hash = email.hashCode.abs() % 9000 + 1000;
    switch (role) {
      case 'driver':
        return 'DRV-OD-TRUCK-$hash';
      case 'gatekeeper':
        return 'HUB-751001-${(hash % 90 + 10).toString().padLeft(2, '0')}';
      case 'manager':
        return 'MGR-QUBOLT-L2-$hash';
      case 'admin':
        return 'MGR-QUBOLT-L5-$hash';
      default:
        return 'USR-$hash';
    }
  }

  Color get _roleColor {
    final role = (user is Map ? (user as Map)['role'] : null) ?? '';
    switch (role) {
      case 'driver':
        return AppColors.accent;
      case 'gatekeeper':
        return AppColors.primary;
      case 'manager':
        return AppColors.warning;
      case 'admin':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _editPhone(BuildContext context, WidgetRef ref) async {
    final m = user is Map ? user as Map : <String, dynamic>{};
    final userId = m['id'] as String? ?? '';
    final existing = m['phone'] as String? ?? '';

    final ctrl = TextEditingController(text: existing);

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.phone_outlined, color: AppColors.primary, size: 18),
          SizedBox(width: 8),
          Text('Set Phone Number',
              style: TextStyle(color: AppColors.textMain(context), fontSize: 15)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the mobile number in international format.\nExample: +919876543210',
              style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '+91XXXXXXXXXX',
                hintStyle:
                    TextStyle(color: AppColors.labelText(context), fontSize: 13),
                filled: true,
                fillColor: AppColors.scaffoldBg,
                prefixIcon: Icon(Icons.phone, color: AppColors.primary, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.divider(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.divider(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || userId.isEmpty) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.patch(
        ApiConstants.userById(userId),
        data: {'phone': result.isEmpty ? null : result},
      );
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.isEmpty
              ? 'Phone number removed'
              : 'Phone set to $result — calls will now connect via Twilio'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update phone: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = user is Map ? user as Map : <String, dynamic>{};
    final email = (m['email'] as String?) ?? '—';
    final role = (m['role'] as String?) ?? 'viewer';
    final name = (m['full_name'] as String?) ?? email.split('@').first;
    final phone = (m['phone'] as String?);
    final color = _roleColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      color: AppColors.textMain(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              Text(email,
                  style: TextStyle(
                      color: AppColors.textSub(context), fontSize: 11)),
              const SizedBox(height: 2),
              // Phone row
              Row(children: [
                Icon(
                  phone != null ? Icons.phone : Icons.phone_disabled_outlined,
                  size: 11,
                  color: phone != null ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  phone ?? 'No phone — calls simulated',
                  style: TextStyle(
                    color: phone != null
                        ? AppColors.textSecondary
                        : AppColors.textMuted,
                    fontSize: 11,
                    fontStyle:
                        phone == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Text(_id,
                  style: TextStyle(
                      color: AppColors.labelText(context),
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
        // Role badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(role == 'gatekeeper' ? 'HUB OPS' : role.toUpperCase(),
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        // Phone edit button
        Tooltip(
          message: phone != null ? 'Edit phone number' : 'Add phone number to enable calls',
          child: IconButton(
            onPressed: () => _editPhone(context, ref),
            icon: Icon(
              phone != null ? Icons.edit_outlined : Icons.add_call,
              size: 16,
              color: phone != null ? AppColors.textSecondary : AppColors.primary,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ),
      ]),
    );
  }
}

const _kDemoUsers = [
  {'email': 'admin@qubolt.io', 'role': 'admin', 'full_name': 'Qubolt Admin'},
  {
    'email': 'ravi.driver@test.com',
    'role': 'driver',
    'full_name': 'Ravi Kumar',
  },
  {'email': 'samal@gmail.com', 'role': 'driver', 'full_name': 'Sai Samal'},
  {
    'email': 'samal12@gmail.com',
    'role': 'gatekeeper',
    'full_name': 'Hub Operator'
  },
  {'email': 'saisamal@gmail.com', 'role': 'driver', 'full_name': 'Deepak Roy'},
];
