import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/theme_provider.dart';

class DarkSidebar extends ConsumerWidget {
  const DarkSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.sidebarBg : AppColors.lightSidebarBg;
    final dividerColor = isDark ? AppColors.border : AppColors.lightBorder;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Logo ────────────────────────────────────────────────────────────
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor))),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.loop, color: Colors.black, size: 18),
              ),
              const SizedBox(width: 10),
              Text('Qubolt', style: TextStyle(
                color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.8,
              )),
            ]),
          ),

          const SizedBox(height: 12),

          // ── Nav items ───────────────────────────────────────────────────────
          _Section(label: 'OPERATIONS', isDark: isDark),
          _NavItem(icon: Icons.dashboard_outlined,
            label: 'Dashboard', route: '/dashboard', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.inventory_2_outlined,
            label: 'Shipments', route: '/shipments', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.route_outlined,
            label: 'Routes', route: '/routes', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.local_shipping_outlined,
            label: 'Fleet', route: '/fleet', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.assignment_return_outlined,
            label: 'Returns', route: '/returns', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.location_on_outlined,
            label: 'Geofence', route: '/geofence', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.map_outlined,
            label: 'Live Map', route: '/map', currentPath: path, isDark: isDark),

          const SizedBox(height: 8),
          _Section(label: 'INTELLIGENCE', isDark: isDark),
          _NavItem(icon: Icons.bar_chart_outlined,
            label: 'Analytics', route: '/analytics', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.auto_graph_outlined,
            label: 'AI Insights', route: '/insights', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.speed_outlined,
            label: 'Driver Stats', route: '/driver-analytics', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.upload_file_outlined,
            label: 'Data Ingestion', route: '/ingestion', currentPath: path, isDark: isDark),

          const SizedBox(height: 8),
          _Section(label: 'ADMIN', isDark: isDark),
          _NavItem(icon: Icons.people_outline,
            label: 'Users', route: '/users', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.handshake_outlined,
            label: 'Partners', route: '/partners', currentPath: path, isDark: isDark),
          _NavItem(icon: Icons.settings_outlined,
            label: 'Settings', route: '/settings', currentPath: path, isDark: isDark),

          const Spacer(),

          // ── Theme toggle ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _ThemeToggle(isDark: isDark),
          ),

          // ── Version ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text('v0.1.0 · Qubolt',
              style: TextStyle(
                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                fontSize: 11,
              )),
          ),
        ],
      ),
    );
  }
}

// ── Theme toggle chip ─────────────────────────────────────────────────────────

class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        ref.read(themeModeProvider.notifier).state =
            isDark ? ThemeMode.light : ThemeMode.dark;
      },
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceAlt : AppColors.lightSurfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.border : AppColors.lightBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 15,
              color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              isDark ? 'Light mode' : 'Dark mode',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.isDark});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(label, style: TextStyle(
        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      )),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon, required this.label,
    required this.route, required this.currentPath,
    required this.isDark,
  });
  final IconData icon;
  final String label;
  final String route;
  final String currentPath;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final active = currentPath == route || currentPath.startsWith('$route/');
    final inactiveText = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: active ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon,
          color: active ? AppColors.primary : inactiveText,
          size: 18),
        title: Text(label, style: TextStyle(
          color: active ? AppColors.primary : inactiveText,
          fontSize: 13,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        )),
        onTap: () => context.go(route),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
