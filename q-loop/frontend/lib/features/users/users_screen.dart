import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      backgroundColor: AppColors.scaffoldBg,
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
                    error: (e, _) => const _UserList(users: _kDemoUsers),
                    data: (list) =>
                        _UserList(users: list.isEmpty ? _kDemoUsers : list),
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
        const Icon(Icons.people_outline, color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        const Text('User Management',
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

class _UserList extends StatelessWidget {
  const _UserList({required this.users});
  final List<dynamic> users;

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
            itemBuilder: (_, i) => _UserCard(user: users[i]),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text('$count $label',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});
  final dynamic user;

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
        return 'MGR-QLOOP-L2-$hash';
      case 'admin':
        return 'MGR-QLOOP-L5-$hash';
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

  @override
  Widget build(BuildContext context) {
    final m = user is Map ? user as Map : <String, dynamic>{};
    final email = (m['email'] as String?) ?? '—';
    final role = (m['role'] as String?) ?? 'viewer';
    final name = (m['full_name'] as String?) ?? email.split('@').first;
    final color = _roleColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withOpacity(0.15),
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
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              Text(email,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 3),
              Text(_id,
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontFamily: 'monospace')),
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
          child: Text(role == 'gatekeeper' ? 'HUB OPS' : role.toUpperCase(),
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w700)),
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
    'full_name': 'Ravi Kumar'
  },
  {'email': 'samal@gmail.com', 'role': 'driver', 'full_name': 'Sai Samal'},
  {
    'email': 'samal12@gmail.com',
    'role': 'gatekeeper',
    'full_name': 'Hub Operator'
  },
  {'email': 'saisamal@gmail.com', 'role': 'driver', 'full_name': 'Deepak Roy'},
];
