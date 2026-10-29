import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'account_session_provider.dart';
import '../core/api/api_client.dart';
import '../core/constants/api_constants.dart';
import '../core/models/pan_model.dart';

class PanState {
  final bool isLoading;
  final bool hasPan;
  final SavedPanModel? pan;
  final String? errorMessage;
  final bool replaceRequired;

  PanState({
    required this.isLoading,
    required this.hasPan,
    this.pan,
    this.errorMessage,
    this.replaceRequired = false,
  });

  factory PanState.initial() => PanState(isLoading: false, hasPan: false);

  PanState copyWith({
    bool? isLoading,
    bool? hasPan,
    SavedPanModel? pan,
    String? errorMessage,
    bool? replaceRequired,
  }) {
    return PanState(
      isLoading: isLoading ?? this.isLoading,
      hasPan: hasPan ?? this.hasPan,
      pan: hasPan == false ? null : pan ?? this.pan,
      errorMessage: errorMessage,
      replaceRequired: replaceRequired ?? this.replaceRequired,
    );
  }
}

class PanNotifier extends Notifier<PanState> {
  final ApiClient _apiClient = ApiClient();

  @override
  PanState build() {
    ref.watch(accountSessionProvider);
    return PanState.initial();
  }

  bool _isCurrent(AccountSession session) =>
      ref.mounted && identical(ref.read(accountSessionProvider), session);

  Future<void> fetchSavedPan() async {
    final session = ref.read(accountSessionProvider);
    if (session.userId == null) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _apiClient.dio.get(ApiConstants.pan);
      if (!_isCurrent(session)) return;
      final hasPan = res.data['hasPan'] as bool? ?? false;
      final panData = res.data['pan'];
      state = state.copyWith(
        isLoading: false,
        hasPan: hasPan,
        pan: panData != null ? SavedPanModel.fromJson(panData) : null,
      );
    } catch (e) {
      if (!_isCurrent(session)) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to fetch saved PAN',
      );
    }
  }

  Future<bool> savePan({
    required String pan,
    required bool consent,
    bool confirmReplace = false,
  }) async {
    final session = ref.read(accountSessionProvider);
    if (session.userId == null) return false;
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      replaceRequired: false,
    );
    try {
      final res = await _apiClient.dio.post(
        ApiConstants.pan,
        data: {
          'pan': pan.trim().toUpperCase(),
          'consent': consent,
          'confirmReplace': confirmReplace,
        },
      );
      if (!_isCurrent(session)) return false;
      final panModel = SavedPanModel.fromJson(res.data['pan']);
      state = state.copyWith(
        isLoading: false,
        hasPan: true,
        pan: panModel,
        replaceRequired: false,
      );
      return true;
    } on DioException catch (e) {
      if (!_isCurrent(session)) return false;
      if (e.response?.statusCode == 409) {
        state = state.copyWith(
          isLoading: false,
          replaceRequired: true,
          errorMessage:
              'A PAN is already linked to this account. Confirm replacement to proceed.',
        );
        return false;
      }
      final msg = e.response?.data?['message'] ?? 'Failed to save PAN';
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg is List ? msg.join(', ') : msg.toString(),
      );
      return false;
    } catch (e) {
      if (!_isCurrent(session)) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unexpected error saving PAN',
      );
      return false;
    }
  }

  Future<bool> deletePan() async {
    final session = ref.read(accountSessionProvider);
    if (session.userId == null) return false;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _apiClient.dio.delete(ApiConstants.pan);
      if (!_isCurrent(session)) return false;
      state = state.copyWith(isLoading: false, hasPan: false, pan: null);
      return true;
    } catch (e) {
      if (!_isCurrent(session)) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to delete PAN',
      );
      return false;
    }
  }
}

final panProvider = NotifierProvider<PanNotifier, PanState>(PanNotifier.new);
