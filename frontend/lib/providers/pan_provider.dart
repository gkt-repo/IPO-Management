import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
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
      pan: pan ?? this.pan,
      errorMessage: errorMessage,
      replaceRequired: replaceRequired ?? this.replaceRequired,
    );
  }
}

class PanNotifier extends Notifier<PanState> {
  final ApiClient _apiClient = ApiClient();

  @override
  PanState build() {
    return PanState.initial();
  }

  Future<void> fetchSavedPan() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _apiClient.dio.get(ApiConstants.pan);
      final hasPan = res.data['hasPan'] as bool? ?? false;
      final panData = res.data['pan'];
      state = state.copyWith(
        isLoading: false,
        hasPan: hasPan,
        pan: panData != null ? SavedPanModel.fromJson(panData) : null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to fetch saved PAN');
    }
  }

  Future<bool> savePan({
    required String pan,
    required bool consent,
    bool confirmReplace = false,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null, replaceRequired: false);
    try {
      final res = await _apiClient.dio.post(
        ApiConstants.pan,
        data: {
          'pan': pan.trim().toUpperCase(),
          'consent': consent,
          'confirmReplace': confirmReplace,
        },
      );
      final panModel = SavedPanModel.fromJson(res.data['pan']);
      state = state.copyWith(
        isLoading: false,
        hasPan: true,
        pan: panModel,
        replaceRequired: false,
      );
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        state = state.copyWith(
          isLoading: false,
          replaceRequired: true,
          errorMessage: 'A PAN is already linked to this account. Confirm replacement to proceed.',
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
      state = state.copyWith(isLoading: false, errorMessage: 'Unexpected error saving PAN');
      return false;
    }
  }

  Future<bool> deletePan() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _apiClient.dio.delete(ApiConstants.pan);
      state = state.copyWith(
        isLoading: false,
        hasPan: false,
        pan: null,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to delete PAN');
      return false;
    }
  }
}

final panProvider = NotifierProvider<PanNotifier, PanState>(PanNotifier.new);
