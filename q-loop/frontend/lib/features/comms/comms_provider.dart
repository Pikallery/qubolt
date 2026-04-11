/// Riverpod providers for DB-backed in-app messaging and fleet positions.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';

// ── Contactable users ─────────────────────────────────────────────────────────

/// Returns the list of users the current user can contact (RBAC-filtered).
final chatUsersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get(ApiConstants.commsUsersForChat);
    return List<Map<String, dynamic>>.from(res.data as List? ?? []);
  } catch (_) {
    return [];
  }
});

// ── Conversation thread ───────────────────────────────────────────────────────

/// Messages between current user and [otherUserId], ordered oldest-first.
/// Marks received messages as read on fetch.
final conversationProvider = FutureProvider.family<
    List<Map<String, dynamic>>, String>((ref, otherUserId) async {
  final dio = ref.read(dioProvider);
  try {
    final res =
        await dio.get(ApiConstants.commsConversation(otherUserId));
    return List<Map<String, dynamic>>.from(res.data as List? ?? []);
  } catch (_) {
    return [];
  }
});

// ── Fleet positions ───────────────────────────────────────────────────────────

/// Live driver GPS positions visible to managers/admins/operators.
final fleetPositionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get(ApiConstants.commsFleetPositions);
    return List<Map<String, dynamic>>.from(res.data as List? ?? []);
  } catch (_) {
    return [];
  }
});
