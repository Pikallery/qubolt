import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Converts a raw exception (usually DioException) into a short human-readable
/// message — never exposes internal stack traces or library internals.
String friendlyError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Could not reach the server.\nMake sure the backend is running.';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Request timed out. Please try again.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401) return 'Session expired. Please log in again.';
        if (code == 403) return 'You don\'t have permission to view this.';
        if (code == 404) return 'Resource not found.';
        if (code != null && code >= 500) return 'Server error ($code). Try again later.';
        return 'Server returned an error (${code ?? '?'}).';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        return 'Network error. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

/// A centred error state with an icon, friendly message, and optional retry.
class ApiErrorWidget extends StatelessWidget {
  const ApiErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;

  /// When true renders a smaller inline version (no large icon).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final msg = friendlyError(error);
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(msg,
                style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.error.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.error.withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.5,
              )),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
