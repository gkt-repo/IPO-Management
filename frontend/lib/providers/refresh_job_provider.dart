import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/constants/api_constants.dart';
import 'ipo_provider.dart';
import 'account_session_provider.dart';

class RefreshJobState {
  final bool isRefreshing;
  final String? activeJobId;
  final int totalIpos;
  final int processedIpos;
  final String? statusMessage;
  final DateTime? lastTriggerTime;

  RefreshJobState({
    this.isRefreshing = false,
    this.activeJobId,
    this.totalIpos = 0,
    this.processedIpos = 0,
    this.statusMessage,
    this.lastTriggerTime,
  });

  RefreshJobState copyWith({
    bool? isRefreshing,
    String? activeJobId,
    int? totalIpos,
    int? processedIpos,
    String? statusMessage,
    DateTime? lastTriggerTime,
  }) {
    return RefreshJobState(
      isRefreshing: isRefreshing ?? this.isRefreshing,
      activeJobId: isRefreshing == false
          ? null
          : activeJobId ?? this.activeJobId,
      totalIpos: totalIpos ?? this.totalIpos,
      processedIpos: processedIpos ?? this.processedIpos,
      statusMessage: statusMessage ?? this.statusMessage,
      lastTriggerTime: lastTriggerTime ?? this.lastTriggerTime,
    );
  }
}

class RefreshJobNotifier extends Notifier<RefreshJobState> {
  final ApiClient _apiClient = ApiClient();
  Timer? _pollingTimer;

  @override
  RefreshJobState build() {
    ref.watch(accountSessionProvider);
    _pollingTimer?.cancel();
    ref.onDispose(() {
      _pollingTimer?.cancel();
    });
    return RefreshJobState();
  }

  /// App-Open automatic refresh: checks client-side debounce to avoid duplicate fires on rebuilds,
  /// calls backend non-blocking, and streams status updates.
  Future<void> triggerAppOpenRefresh() async {
    // Prevent rapid multiple triggers on widget rebuild
    if (state.isRefreshing) return;
    if (state.lastTriggerTime != null) {
      final diff = DateTime.now().difference(state.lastTriggerTime!);
      if (diff.inSeconds < 15) return; // 15-second client-side debounce
    }

    await startRefresh(force: false);
  }

  /// Manual refresh button trigger.
  Future<void> triggerManualRefresh() async {
    if (state.isRefreshing) return;
    await startRefresh(force: true);
  }

  bool _isCurrent(AccountSession session) =>
      ref.mounted && identical(ref.read(accountSessionProvider), session);

  Future<void> startRefresh({required bool force}) async {
    final session = ref.read(accountSessionProvider);
    if (session.userId == null) return;
    state = state.copyWith(
      isRefreshing: true,
      lastTriggerTime: DateTime.now(),
      statusMessage: 'Checking allotment status in background...',
      processedIpos: 0,
    );

    try {
      final res = await _apiClient.dio.post(
        '${ApiConstants.refresh}?force=${force ? "true" : "false"}',
      );

      if (!_isCurrent(session)) return;
      final jobId = res.data['jobId'] as String?;
      final status = res.data['status'] as String?;
      final message = res.data['message'] as String? ?? 'Refresh initiated';
      final total = (res.data['totalIpos'] as num?)?.toInt() ?? 0;

      if (status == 'COMPLETED') {
        state = state.copyWith(isRefreshing: false, statusMessage: message);
        ref.read(ipoListProvider.notifier).fetchIposAndSummary(silent: true);
        return;
      }

      if (jobId != null) {
        state = state.copyWith(
          activeJobId: jobId,
          totalIpos: total,
          statusMessage: 'Scanning registrars for allotment results...',
        );
        _startPolling(jobId);
      } else {
        state = state.copyWith(isRefreshing: false, statusMessage: message);
      }
    } catch (e) {
      if (!_isCurrent(session)) return;
      state = state.copyWith(
        isRefreshing: false,
        statusMessage: 'Refresh bypassed: checking cached results',
      );
    }
  }

  void _startPolling(String jobId) {
    final session = ref.read(accountSessionProvider);
    bool polling = false;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isCurrent(session)) {
        timer.cancel();
        return;
      }
      if (polling) return;
      polling = true;
      try {
        final res = await _apiClient.dio.get('${ApiConstants.refresh}/$jobId');
        if (!_isCurrent(session)) {
          timer.cancel();
          return;
        }
        final status = res.data['status'] as String?;
        final processed = (res.data['processedIpos'] as num?)?.toInt() ?? 0;
        final total =
            (res.data['totalIpos'] as num?)?.toInt() ?? state.totalIpos;

        state = state.copyWith(
          processedIpos: processed,
          totalIpos: total,
          statusMessage: 'Checked $processed of $total IPOs...',
        );

        if (status == 'COMPLETED' || status == 'FAILED') {
          timer.cancel();
          state = state.copyWith(
            isRefreshing: false,
            activeJobId: null,
            statusMessage: status == 'COMPLETED'
                ? 'Allotment scan up to date'
                : 'Scan completed with notices',
          );
          ref.read(ipoListProvider.notifier).fetchIposAndSummary(silent: true);
        }
      } catch (e) {
        timer.cancel();
        if (!_isCurrent(session)) return;
        state = state.copyWith(isRefreshing: false, activeJobId: null);
      } finally {
        polling = false;
      }
    });
  }
}

final refreshJobProvider =
    NotifierProvider<RefreshJobNotifier, RefreshJobState>(
      RefreshJobNotifier.new,
    );
