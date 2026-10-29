import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'account_session_provider.dart';
import '../core/api/api_client.dart';
import '../core/constants/api_constants.dart';
import '../core/models/user_model.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final UserModel? user;
  final String? errorMessage;

  AuthState({
    required this.isLoading,
    required this.isAuthenticated,
    this.user,
    this.errorMessage,
  });

  factory AuthState.initial() =>
      AuthState(isLoading: true, isAuthenticated: false);

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    UserModel? user,
    String? errorMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  final ApiClient _apiClient = ApiClient();
  int _operation = 0;

  bool _isCurrent(int operation) => ref.mounted && operation == _operation;

  @override
  AuthState build() {
    Future.microtask(() => checkAuth());
    return AuthState.initial();
  }

  Future<void> checkAuth() async {
    final operation = ++_operation;
    final token = await _apiClient.getToken();
    if (!_isCurrent(operation)) return;
    if (token == null || token.isEmpty) {
      await logout();
      return;
    }

    try {
      final res = await _apiClient.dio.get(ApiConstants.me);
      if (!_isCurrent(operation)) return;
      final user = UserModel.fromJson(res.data);
      ref.read(accountSessionProvider.notifier).changeUser(user.id);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: user,
      );
    } catch (e) {
      if (!_isCurrent(operation)) return;
      await logout();
    }
  }

  Future<bool> login(String email, String password) async {
    final operation = ++_operation;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _apiClient.dio.post(
        ApiConstants.login,
        data: {'email': email, 'password': password},
      );
      if (!_isCurrent(operation)) return false;
      final token = res.data['accessToken'] as String;
      await _apiClient.saveToken(token);
      if (!_isCurrent(operation)) return false;
      final user = UserModel.fromJson(res.data['user']);
      ref.read(accountSessionProvider.notifier).changeUser(user.id);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: user,
      );
      return true;
    } on DioException catch (e) {
      if (!_isCurrent(operation)) return false;
      final msg =
          e.response?.data?['message'] ??
          'Login failed. Please check your credentials.';
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg is List ? msg.join(', ') : msg.toString(),
      );
      return false;
    } catch (e) {
      if (!_isCurrent(operation)) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unexpected connection error',
      );
      return false;
    }
  }

  Future<bool> register(
    String email,
    String password,
    String? fullName, {
    String? passwordHint,
  }) async {
    final operation = ++_operation;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _apiClient.dio.post(
        ApiConstants.register,
        data: {
          'email': email,
          'password': password,
          if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
          if (passwordHint != null && passwordHint.isNotEmpty)
            'passwordHint': passwordHint,
        },
      );
      if (!_isCurrent(operation)) return false;
      final token = res.data['accessToken'] as String;
      await _apiClient.saveToken(token);
      if (!_isCurrent(operation)) return false;
      final user = UserModel.fromJson(res.data['user']);
      ref.read(accountSessionProvider.notifier).changeUser(user.id);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: user,
      );
      return true;
    } on DioException catch (e) {
      if (!_isCurrent(operation)) return false;
      final msg = e.response?.data?['message'] ?? 'Registration failed.';
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg is List ? msg.join(', ') : msg.toString(),
      );
      return false;
    } catch (e) {
      if (!_isCurrent(operation)) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unexpected connection error',
      );
      return false;
    }
  }

  Future<({bool success, String? hint, String message})> getPasswordHint(
    String email,
  ) async {
    try {
      final res = await _apiClient.dio.post(
        ApiConstants.forgotPasswordHint,
        data: {'email': email.trim().toLowerCase()},
      );
      final hint = res.data['hint'] as String?;
      final message = res.data['message'] as String? ?? '';
      return (success: hint != null, hint: hint, message: message);
    } on DioException catch (e) {
      final msg =
          e.response?.data?['message'] ?? 'Unable to retrieve password hint.';
      return (
        success: false,
        hint: null,
        message: msg is List ? msg.join(', ') : msg.toString(),
      );
    } catch (e) {
      return (
        success: false,
        hint: null,
        message: 'Connection error. Please try again.',
      );
    }
  }

  Future<void> logout() async {
    _operation++;
    final userId = ref.read(accountSessionProvider).userId;
    ref.read(accountSessionProvider.notifier).changeUser(null);
    state = AuthState(isLoading: false, isAuthenticated: false);
    await _apiClient.clearToken();
    const storage = FlutterSecureStorage();
    await Future.wait([
      storage.delete(key: 'cached_ipos_list'),
      storage.delete(key: 'cached_dashboard_summary'),
      if (userId != null) storage.delete(key: 'cached_ipos_list:$userId'),
      if (userId != null)
        storage.delete(key: 'cached_dashboard_summary:$userId'),
    ]);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
