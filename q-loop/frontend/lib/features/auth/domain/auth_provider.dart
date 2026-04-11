import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

const _accessKey = 'access_token';
const _refreshKey = 'refresh_token';

/// Decode role + userId from a JWT access token.
Map<String, String?> _decodeJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return {};
    String payload = parts[1];
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = utf8.decode(base64Url.decode(payload));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    return {
      'role': map['role'] as String?,
      'userId': map['sub'] as String?,
    };
  } catch (_) {
    return {};
  }
}

/// Check if a JWT token is expired (with 30s buffer).
bool _isTokenExpired(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    String payload = parts[1];
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = utf8.decode(base64Url.decode(payload));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    final exp = map['exp'] as int?;
    if (exp == null) return true;
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 30)));
  } catch (_) {
    return true;
  }
}

class AuthState {
  final bool isAuthenticated;
  final String? role;
  final String? userId;
  const AuthState({this.isAuthenticated = false, this.role, this.userId});
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._storage, this._ref) : super(const AuthState());

  final FlutterSecureStorage _storage;
  final Ref _ref;

  Future<void> login({required String email, required String password}) async {
    final dio = _ref.read(dioProvider);
    try {
      final res = await dio.post(
        ApiConstants.login,
        data: {'email': email, 'password': password},
        options: Options(headers: {'X-Tenant-ID': ApiConstants.tenantId}),
      );
      final accessToken = res.data['access_token'] as String;
      await _storage.write(key: _accessKey, value: accessToken);
      await _storage.write(
          key: _refreshKey, value: res.data['refresh_token'] as String?);
      final claims = _decodeJwt(accessToken);
      state = AuthState(
        isAuthenticated: true,
        role: claims['role'],
        userId: claims['userId'],
      );
    } on DioException catch (e) {
      final detail = e.response?.data;
      String msg = 'Login failed. Please check your connection.';
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        msg = 'Invalid email or password.';
      } else if (status == 404) {
        msg = 'Service unavailable. Please try again later.';
      } else if (detail is Map && detail['detail'] != null) {
        msg = detail['detail'].toString();
      }
      throw Exception(msg);
    } catch (e) {
      throw Exception('Login failed. Please try again.');
    }
  }

  /// Send OTP to [phone] (E.164 format). Returns response map.
  /// In dev mode: {"mock": true, "code": "123456"}.
  Future<Map<String, dynamic>> sendOtp({required String phone}) async {
    final dio = _ref.read(dioProvider);
    final res = await dio.post(
      ApiConstants.sendOtp,
      data: {'phone': phone},
      options: Options(headers: {'X-Tenant-ID': ApiConstants.tenantId}),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> signup({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
    required String otpCode,
    String? licenseNumber,
    String? vehicleType,
    String? assignedHubId,
    String? hubName,
    String? organizationName,
  }) async {
    final dio = _ref.read(dioProvider);
    final res = await dio.post(
      ApiConstants.signup,
      data: {
        'email': email,
        'password': password,
        'full_name': fullName,
        'phone': phone,
        'role': role,
        'otp_code': otpCode,
        if (licenseNumber != null) 'license_number': licenseNumber,
        if (vehicleType != null) 'vehicle_type': vehicleType,
        if (assignedHubId != null) 'assigned_hub_id': assignedHubId,
        if (hubName != null) 'hub_name': hubName,
        if (organizationName != null) 'organization_name': organizationName,
      },
      options: Options(headers: {'X-Tenant-ID': ApiConstants.tenantId}),
    );
    final accessToken = res.data['access_token'] as String;
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(
        key: _refreshKey, value: res.data['refresh_token'] as String?);
    final claims = _decodeJwt(accessToken);
    state = AuthState(
      isAuthenticated: true,
      role: claims['role'],
      userId: claims['userId'],
    );
  }

  Future<void> logout() async {
    try {
      final dio = _ref.read(dioProvider);
      await dio.post(ApiConstants.logout);
    } catch (_) {}
    await _storage.deleteAll();
    state = const AuthState(isAuthenticated: false);
  }

  Future<bool> checkAuthenticated() async {
    final token = await _storage.read(key: _accessKey);
    if (token == null) {
      state = const AuthState(isAuthenticated: false);
      return false;
    }
    // Check if JWT is expired
    final claims = _decodeJwt(token);
    if (claims['role'] == null) {
      // Token is malformed — clear and force re-login
      await _storage.deleteAll();
      state = const AuthState(isAuthenticated: false);
      return false;
    }
    // Check expiry from JWT payload
    if (_isTokenExpired(token)) {
      // Try refresh before declaring unauthenticated
      final refreshToken = await _storage.read(key: _refreshKey);
      if (refreshToken != null) {
        try {
          final dio = _ref.read(dioProvider);
          final res = await dio.post(
            ApiConstants.refresh,
            data: {'refresh_token': refreshToken},
          );
          final newAccess = res.data['access_token'] as String;
          await _storage.write(key: _accessKey, value: newAccess);
          await _storage.write(
              key: _refreshKey, value: res.data['refresh_token'] as String?);
          final newClaims = _decodeJwt(newAccess);
          state = AuthState(
            isAuthenticated: true,
            role: newClaims['role'],
            userId: newClaims['userId'],
          );
          return true;
        } catch (_) {
          await _storage.deleteAll();
          state = const AuthState(isAuthenticated: false);
          return false;
        }
      }
      await _storage.deleteAll();
      state = const AuthState(isAuthenticated: false);
      return false;
    }
    state = AuthState(
      isAuthenticated: true,
      role: claims['role'],
      userId: claims['userId'],
    );
    return true;
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(secureStorageProvider), ref);
});
