import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  runApp(const ProviderScope(child: QLoopApp()));
}

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Remote Config — fetch flags in background, never block startup
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
    rc.fetchAndActivate().ignore(); // fire-and-forget

    // Analytics
    FirebaseAnalytics.instance
        .setAnalyticsCollectionEnabled(true)
        .ignore(); // fire-and-forget
  } catch (e) {
    // Firebase is optional — app runs fine without it
    debugPrint('[Firebase] init skipped: $e');
  }
}
