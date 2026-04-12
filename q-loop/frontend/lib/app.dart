import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/constants/app_colors.dart';
import 'core/providers/theme_provider.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/auth/domain/auth_provider.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/signup_screen.dart';
import 'features/comms/chat_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/fleet/fleet_screen.dart';
import 'features/ingestion/ingestion_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/routes/routes_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shipments/driver_view.dart';
import 'features/shipments/hub_view.dart';
import 'features/shipments/shipments_screen.dart';
import 'features/users/users_screen.dart';
import 'features/drivers/driver_analytics_screen.dart';
import 'features/geofence/geofence_screen.dart';
import 'features/map/map_screen.dart';
import 'features/returns/returns_screen.dart';
import 'features/partners/partners_screen.dart';

const _publicRoutes = {'/login', '/signup'};

GoRouter createRouter(Ref ref) => GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final auth = ref.read(authNotifierProvider);
        final isPublic = _publicRoutes.contains(state.matchedLocation);
        if (!auth.isAuthenticated && !isPublic) return '/login';
        if (auth.isAuthenticated && isPublic) {
          return _routeForRole(auth.role);
        }
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
        GoRoute(
            path: '/dashboard', builder: (_, __) => const DashboardScreen()),
        GoRoute(
            path: '/shipments', builder: (_, __) => const ShipmentsScreen()),
        GoRoute(path: '/routes', builder: (_, __) => const RoutesScreen()),
        GoRoute(
            path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: '/fleet', builder: (_, __) => const FleetScreen()),
        GoRoute(path: '/insights', builder: (_, __) => const InsightsScreen()),
        GoRoute(
            path: '/ingestion', builder: (_, __) => const IngestionScreen()),
        GoRoute(path: '/users', builder: (_, __) => const UsersScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/driver', builder: (_, __) => const DriverView()),
        GoRoute(path: '/hub', builder: (_, __) => const HubView()),
        GoRoute(path: '/gatekeeper', builder: (_, __) => const HubView()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
        GoRoute(
            path: '/driver-analytics',
            builder: (_, __) => const DriverAnalyticsScreen()),
        GoRoute(path: '/returns', builder: (_, __) => const ReturnsScreen()),
        GoRoute(path: '/partners', builder: (_, __) => const PartnersScreen()),
        GoRoute(path: '/geofence', builder: (_, __) => const GeofenceScreen()),
        GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
      ],
    );

String _routeForRole(String? role) {
  switch (role) {
    case 'driver':
      return '/driver';
    case 'gatekeeper':
      return '/hub';
    default:
      return '/dashboard';
  }
}

final routerProvider = Provider<GoRouter>((ref) => createRouter(ref));

class QLoopApp extends ConsumerWidget {
  const QLoopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Qubolt',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      routerConfig: router,
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.scaffoldBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.cardBg,
        error: AppColors.error,
        onPrimary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.textPrimary),
        bodySmall: TextStyle(color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      dividerColor: AppColors.border,
      cardColor: AppColors.cardBg,
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightScaffoldBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.lightCardBg,
        error: AppColors.error,
        onPrimary: Colors.black,
        onSurface: AppColors.lightTextPrimary,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.lightTextPrimary),
        bodySmall: TextStyle(color: AppColors.lightTextSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSidebarBg,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        shadowColor: Color(0x0D000000),
        titleTextStyle: TextStyle(
          color: AppColors.lightTextPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      dividerColor: AppColors.lightBorder,
      cardColor: AppColors.lightCardBg,
    );
  }
}
