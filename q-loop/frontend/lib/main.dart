import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Remote Config — fetch feature flags in background
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc.setDefaults(const {
      'enable_ai_insights': true,
      'enable_geofence': true,
      'enable_returns': true,
      'app_banner': '',
    });
    rc.fetchAndActivate().ignore();

    // Analytics
    FirebaseAnalytics.instance
        .setAnalyticsCollectionEnabled(true)
        .ignore();

    // Crashlytics — mobile only (not supported on web)
    if (!kIsWeb) {
      // FlutterError.onError wired in firebase_service.dart
    }
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  runApp(
    const ProviderScope(
      child: QLoopApp(),
    ),
  );
}
