import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/theme_provider.dart';
import '../auth/domain/auth_provider.dart';
import '../dashboard/widgets/dark_sidebar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final auth = ref.watch(authNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      body: Row(
        children: [
          if (!isMobile) const DarkSidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(isMobile: isMobile),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Profile card
                        _ProfileCard(auth: auth),
                        const SizedBox(height: 20),

                        // Appearance
                        _SectionCard(
                          title: 'Appearance',
                          icon: Icons.palette_outlined,
                          children: [
                            _ToggleTile(
                              label: 'Dark Mode',
                              subtitle: 'Switch between light and dark themes',
                              value: isDark,
                              onChanged: (v) {
                                ref.read(themeModeProvider.notifier).state =
                                    v ? ThemeMode.dark : ThemeMode.light;
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Notifications
                        _SectionCard(
                          title: 'Notifications',
                          icon: Icons.notifications_outlined,
                          children: [
                            _ToggleTile(
                              label: 'Push Notifications',
                              subtitle: 'Receive alerts for shipment updates',
                              value: true,
                              onChanged: (_) {},
                            ),
                            _ToggleTile(
                              label: 'SMS Alerts',
                              subtitle: 'Twilio SMS for critical events',
                              value: true,
                              onChanged: (_) {},
                            ),
                            _ToggleTile(
                              label: 'Email Digest',
                              subtitle: 'Daily summary emails',
                              value: false,
                              onChanged: (_) {},
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Backend connection
                        const _SectionCard(
                          title: 'Backend Connection',
                          icon: Icons.cloud_outlined,
                          children: [
                            _InfoTile(
                              label: 'API Endpoint',
                              value: 'http://localhost:8000/api/v1',
                            ),
                            _InfoTile(
                              label: 'Tenant ID',
                              value: 'a25c91cf-681c-…',
                              mono: true,
                            ),
                            _InfoTile(
                              label: 'Database',
                              value: 'PostgreSQL · qloop_db',
                            ),
                            _InfoTile(
                              label: 'Records',
                              value: '601,700 shipments',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // About
                        const _SectionCard(
                          title: 'About Qubolt',
                          icon: Icons.info_outline,
                          children: [
                            _InfoTile(label: 'Version', value: '0.1.0'),
                            _InfoTile(
                                label: 'Optimizer',
                                value: 'QUBO / Simulated Annealing v2.1'),
                            _InfoTile(
                                label: 'Coverage',
                                value: 'Odisha (16 districts)'),
                            _InfoTile(
                                label: 'Stack',
                                value: 'Flutter · FastAPI · PostgreSQL'),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Sign out
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await ref
                                  .read(authNotifierProvider.notifier)
                                  .logout();
                              if (context.mounted) {
                                context.go('/login');
                              }
                            },
                            icon: const Icon(Icons.logout,
                                size: 18, color: AppColors.error),
                            label: const Text('Sign Out',
                                style: TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: AppColors.error.withOpacity(0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
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
  const _TopBar({this.isMobile = false});
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
        Icon(Icons.settings_outlined, color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        Text('Settings',
            style: TextStyle(
                color: AppColors.textMain(context),
                fontWeight: FontWeight.w600,
                fontSize: 18)),
      ]),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.auth});
  final AuthState auth;

  String get _customId {
    final hash = (auth.userId ?? 'default').hashCode.abs() % 9000 + 1000;
    switch (auth.role) {
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

  @override
  Widget build(BuildContext context) {
    final role = auth.role ?? 'viewer';
    final roleColors = <String, Color>{
      'driver': AppColors.accent,
      'gatekeeper': AppColors.primary,
      'manager': AppColors.warning,
      'admin': AppColors.error,
    };
    final color = roleColors[role] ?? AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.12),
            AppColors.cardBg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: color.withOpacity(0.2),
          child: Icon(
            role == 'driver'
                ? Icons.local_shipping_outlined
                : role == 'gatekeeper'
                    ? Icons.warehouse_outlined
                    : Icons.admin_panel_settings_outlined,
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role == 'gatekeeper'
                    ? 'Hub Operator'
                    : role[0].toUpperCase() + role.substring(1),
                style: TextStyle(
                    color: AppColors.textMain(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
              const SizedBox(height: 3),
              Text(_customId,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600)),
              Text(auth.userId ?? 'Not logged in',
                  style: TextStyle(
                      color: AppColors.labelText(context),
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            role == 'gatekeeper' ? 'HUB OPS' : role.toUpperCase(),
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider(context)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(icon, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: AppColors.textMain(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ]),
          ),
          Divider(color: AppColors.divider(context), height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _ToggleTile extends StatefulWidget {
  const _ToggleTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String label, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_ToggleTile> createState() => _ToggleTileState();
}

class _ToggleTileState extends State<_ToggleTile> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label,
                  style: TextStyle(
                      color: AppColors.textMain(context), fontSize: 13)),
              Text(widget.subtitle,
                  style: TextStyle(
                      color: AppColors.labelText(context), fontSize: 11)),
            ],
          ),
        ),
        Switch(
          value: _value,
          onChanged: (v) {
            setState(() => _value = v);
            widget.onChanged(v);
          },
          activeThumbColor: AppColors.primary,
        ),
      ]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.label, required this.value, this.mono = false});
  final String label, value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text(label,
            style:
                TextStyle(color: AppColors.textSub(context), fontSize: 13)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: AppColors.textMain(context),
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
