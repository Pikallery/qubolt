import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Returns a short label + optional detail string for an API error.
/// Label is always shown; detail is shown in a smaller muted line below.
({String label, String? detail}) errorInfo(Object e) {
  if (e is DioException) {
    final url = e.requestOptions.path;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return (
          label: 'Cannot connect to server',
          detail: 'POST/GET $url — check that the backend is running on port 8000',
        );
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return (label: 'Request timed out', detail: url);
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final body = e.response?.data;
        String detail = url;
        if (body is Map && body['detail'] != null) {
          detail = '${body['detail']}  ($url)';
        }
        if (code == 401) return (label: 'Session expired — please log in again', detail: detail);
        if (code == 403) return (label: 'Permission denied', detail: detail);
        if (code == 404) return (label: 'Not found', detail: detail);
        if (code != null && code >= 500) {
          return (label: 'Server error $code', detail: detail);
        }
        return (label: 'HTTP ${code ?? "?"} error', detail: detail);
      case DioExceptionType.cancel:
        return (label: 'Request cancelled', detail: url);
      default:
        return (label: 'Network error', detail: e.message ?? url);
    }
  }
  // Plain string (from e.toString() stored in state)
  final s = e.toString();
  if (s.contains('assigned_driver_id') || s.contains('UndefinedColumn')) {
    return (label: 'Database schema out of date', detail: 'Run: alembic upgrade head');
  }
  return (label: 'Error', detail: s.length > 120 ? '${s.substring(0, 120)}…' : s);
}

/// A centred error state with icon, message, detail line, and optional retry.
class ApiErrorWidget extends StatelessWidget {
  const ApiErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (:label, :detail) = errorInfo(error);

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.error),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(color: AppColors.error, fontSize: 12,
                        fontWeight: FontWeight.w600)),
                if (detail != null)
                  Text(detail,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 10),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
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
          Icon(Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.error.withValues(alpha: 0.95),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              )),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                )),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 24),
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
