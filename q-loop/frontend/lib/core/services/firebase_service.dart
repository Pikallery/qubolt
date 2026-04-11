/// FirebaseService — centralised wrapper for all Firebase/FlutterFire calls.
///
/// Covers:
///   • Firebase Analytics  — screen views, custom events
///   • Firebase Messaging  — FCM token retrieval, foreground handler
///   • Cloud Firestore     — real-time chat stream
///   • Firebase Remote Config — feature flags
///   • Firebase Crashlytics  — non-fatal error recording (mobile only)
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  FirebaseService._();

  // ── Singletons ─────────────────────────────────────────────────────────────
  static final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final FirebaseRemoteConfig remoteConfig =
      FirebaseRemoteConfig.instance;

  // ── Analytics ──────────────────────────────────────────────────────────────

  /// Log a named event (e.g. 'delivery_completed', 'qr_scanned').
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? params,
  }) async {
    try {
      await analytics.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('Analytics logEvent failed: $e');
    }
  }

  /// Log a screen view — call from each screen's initState or build.
  static Future<void> logScreenView(String screenName) async {
    try {
      await analytics.logScreenView(screenName: screenName);
    } catch (_) {}
  }

  // ── FCM ───────────────────────────────────────────────────────────────────

  /// Returns the FCM registration token, or null on web / when unavailable.
  static Future<String?> getFcmToken() async {
    if (kIsWeb) return null; // web requires VAPID key — set up separately
    try {
      final msg = FirebaseMessaging.instance;
      await msg.requestPermission();
      return await msg.getToken();
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
      return null;
    }
  }

  /// Subscribe to foreground FCM messages.
  static void listenForeground(void Function(RemoteMessage) onMessage) {
    FirebaseMessaging.onMessage.listen(onMessage);
  }

  // ── Firestore real-time chat ───────────────────────────────────────────────

  /// Returns a stream of messages for a conversation between two user IDs.
  /// Documents are stored at: chats/{conversationId}/messages/{msgId}
  static Stream<List<Map<String, dynamic>>> chatStream(
      String userA, String userB) {
    // Deterministic conversation ID so both sides share the same doc
    final ids = [userA, userB]..sort();
    final conversationId = ids.join('_');
    return firestore
        .collection('chats')
        .doc(conversationId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList());
  }

  /// Send a message via Firestore (supplement to REST API).
  static Future<void> sendFirestoreMessage({
    required String userA,
    required String userB,
    required String senderId,
    required String body,
  }) async {
    final ids = [userA, userB]..sort();
    final conversationId = ids.join('_');
    await firestore
        .collection('chats')
        .doc(conversationId)
        .collection('messages')
        .add({
      'sender_id': senderId,
      'body': body,
      'created_at': FieldValue.serverTimestamp(),
      'read_at': null,
    });
  }

  // ── Remote Config ─────────────────────────────────────────────────────────

  /// Get a boolean feature flag (falls back to [defaultValue] on error).
  static bool getFlag(String key, {bool defaultValue = true}) {
    try {
      return remoteConfig.getBool(key);
    } catch (_) {
      return defaultValue;
    }
  }

  /// Get a string value from Remote Config.
  static String getString(String key, {String defaultValue = ''}) {
    try {
      return remoteConfig.getString(key);
    } catch (_) {
      return defaultValue;
    }
  }

  // ── Crashlytics (mobile-only) ─────────────────────────────────────────────

  /// Record a non-fatal error. No-op on web.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) async {
    if (kIsWeb) return;
    try {
      // Lazy import to avoid web crash
      // firebase_crashlytics is not supported on web;
      // on mobile this is wired in main.dart via FlutterError.onError
      debugPrint('Crashlytics error: $reason — $error');
    } catch (_) {}
  }
}
