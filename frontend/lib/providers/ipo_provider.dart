import 'dart:convert';
import 'account_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api/api_client.dart';
import '../core/constants/api_constants.dart';
import '../core/models/ipo_model.dart';
import '../core/models/dashboard_summary_model.dart';

class IpoListState {
  final bool isLoading;
  final List<IpoItemModel> ipos;
  final DashboardSummaryModel? summary;
  final String? errorMessage;
  final String selectedIssueType; // 'MAINBOARD' or 'SME'
  final String
  selectedStatusFilter; // 'ALL', 'ALLOTTED', 'NOT_ALLOTTED', 'PENDING'
  final String searchQuery;
  final IpoLifecycle selectedLifecycle;

  IpoListState({
    required this.isLoading,
    required this.ipos,
    this.summary,
    this.errorMessage,
    this.selectedIssueType = 'MAINBOARD',
    this.selectedStatusFilter = 'ALL',
    this.searchQuery = '',
    this.selectedLifecycle = IpoLifecycle.open,
  });

  factory IpoListState.initial() =>
      IpoListState(isLoading: false, ipos: [], selectedIssueType: 'MAINBOARD');

  List<IpoItemModel> get filteredIpos => filteredIposAt(DateTime.now());

  List<IpoItemModel> filteredIposAt(DateTime now) {
    final result = ipos.where((ipo) {
      if (ipo.issueType != selectedIssueType) return false;
      if (ipo.lifecycleAt(now) != selectedLifecycle) return false;
      return _matchesSearchAndStatus(ipo);
    }).toList();
    result.sort((a, b) {
      final dateA = selectedLifecycle == IpoLifecycle.upcoming
          ? a.opensAt
          : a.closesAt ?? a.listingDate;
      final dateB = selectedLifecycle == IpoLifecycle.upcoming
          ? b.opensAt
          : b.closesAt ?? b.listingDate;
      if (dateA == null && dateB != null) return 1;
      if (dateA != null && dateB == null) return -1;
      final cmp = dateA == null || dateB == null ? 0 : dateA.compareTo(dateB);
      return (selectedLifecycle == IpoLifecycle.closed ? -cmp : cmp) != 0
          ? (selectedLifecycle == IpoLifecycle.closed ? -cmp : cmp)
          : a.name.compareTo(b.name);
    });
    return result;
  }

  bool _matchesSearchAndStatus(IpoItemModel ipo) {
    if (selectedStatusFilter != 'ALL' &&
        ipo.status != parseAllotmentStatus(selectedStatusFilter)) {
      return false;
    }
    final q = searchQuery.trim().toLowerCase();
    return q.isEmpty ||
        ipo.name.toLowerCase().contains(q) ||
        ipo.registrar.toLowerCase().contains(q);
  }

  int lifecycleCount(IpoLifecycle lifecycle) => ipos
      .where(
        (ipo) =>
            ipo.issueType == selectedIssueType &&
            ipo.lifecycle == lifecycle &&
            _matchesSearchAndStatus(ipo),
      )
      .length;

  List<IpoItemModel> get unscheduledIpos =>
      ipos
          .where(
            (ipo) =>
                ipo.issueType == selectedIssueType &&
                ipo.lifecycle == IpoLifecycle.unknown &&
                _matchesSearchAndStatus(ipo),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// List of all allotted IPOs regardless of current filter, latest first
  List<IpoItemModel> get allottedIpos {
    final list = ipos
        .where((ipo) => ipo.status == AllotmentStatusEnum.allotted)
        .toList();
    list.sort((a, b) {
      final dateA =
          a.listingDate ??
          a.allotmentDate ??
          a.closeDate ??
          a.openDate ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dateB =
          b.listingDate ??
          b.allotmentDate ??
          b.closeDate ??
          b.openDate ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });
    return list;
  }

  /// Total profit across all allotted IPOs based on shares allotted
  double get totalAllottedProfit {
    double total = 0;
    for (final ipo in allottedIpos) {
      if (ipo.totalProfit != null) {
        total += ipo.totalProfit!;
      }
    }
    return total;
  }

  /// Total investment across all allotted IPOs
  double get totalAllottedInvested {
    double total = 0;
    for (final ipo in allottedIpos) {
      if (ipo.totalInvested != null) {
        total += ipo.totalInvested!;
      }
    }
    return total;
  }

  /// Total current market value across all allotted IPOs
  double get totalAllottedValue {
    double total = 0;
    for (final ipo in allottedIpos) {
      if (ipo.totalCurrentValue != null) {
        total += ipo.totalCurrentValue!;
      }
    }
    return total;
  }

  /// Total shares allotted across all allotted IPOs
  int get totalAllottedShares {
    int total = 0;
    for (final ipo in allottedIpos) {
      if (ipo.allottedQuantity != null) {
        total += ipo.allottedQuantity!;
      }
    }
    return total;
  }

  /// Overall profit percentage across all allotted IPOs
  double? get totalAllottedReturnPercentage {
    final invested = totalAllottedInvested;
    if (invested <= 0) return null;
    return (totalAllottedProfit / invested) * 100.0;
  }

  IpoListState copyWith({
    bool? isLoading,
    List<IpoItemModel>? ipos,
    DashboardSummaryModel? summary,
    String? errorMessage,
    String? selectedIssueType,
    String? selectedStatusFilter,
    String? searchQuery,
    IpoLifecycle? selectedLifecycle,
  }) {
    return IpoListState(
      isLoading: isLoading ?? this.isLoading,
      ipos: ipos ?? this.ipos,
      summary: summary ?? this.summary,
      errorMessage: errorMessage,
      selectedIssueType: selectedIssueType ?? this.selectedIssueType,
      selectedStatusFilter: selectedStatusFilter ?? this.selectedStatusFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedLifecycle: selectedLifecycle ?? this.selectedLifecycle,
    );
  }
}

class IpoListNotifier extends Notifier<IpoListState> {
  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  IpoListState build() {
    ref.watch(accountSessionProvider);
    return IpoListState.initial();
  }

  bool _isCurrent(AccountSession session) =>
      ref.mounted && identical(ref.read(accountSessionProvider), session);

  Future<void> fetchIposAndSummary({bool silent = false}) async {
    final session = ref.read(accountSessionProvider);
    final userId = session.userId;
    if (userId == null) return;
    // Fast local database cache: load instantly if in-memory list is empty
    if (state.ipos.isEmpty) {
      try {
        final cachedIposRaw = await _storage.read(
          key: 'cached_ipos_list:$userId',
        );
        final cachedSummaryRaw = await _storage.read(
          key: 'cached_dashboard_summary:$userId',
        );
        if (!_isCurrent(session)) return;
        if (cachedIposRaw != null && cachedIposRaw.isNotEmpty) {
          final ipoJson = jsonDecode(cachedIposRaw) as List;
          final cachedList = ipoJson
              .map((i) => IpoItemModel.fromJson(i))
              .toList();
          DashboardSummaryModel? cachedSummary;
          if (cachedSummaryRaw != null && cachedSummaryRaw.isNotEmpty) {
            cachedSummary = DashboardSummaryModel.fromJson(
              jsonDecode(cachedSummaryRaw),
            );
          }
          state = state.copyWith(
            isLoading: false,
            ipos: cachedList,
            summary: cachedSummary,
          );
        }
      } catch (_) {
        // Fallback silently to network fetch
      }
    }

    if (!_isCurrent(session)) return;
    if (!silent && state.ipos.isEmpty) {
      state = state.copyWith(isLoading: true, errorMessage: null);
    }

    try {
      // Schedule freshness must not depend on a successful portfolio request.
      final ipoRes = await _apiClient.dio.get(ApiConstants.ipoList);
      if (!_isCurrent(session)) return;
      final list = (ipoRes.data as List)
          .map((i) => IpoItemModel.fromJson(i))
          .toList();
      state = state.copyWith(isLoading: false, ipos: list);
      await _storage
          .write(
            key: 'cached_ipos_list:$userId',
            value: jsonEncode(ipoRes.data),
          )
          .catchError((_) {});
      try {
        if (!_isCurrent(session)) return;
        final summaryRes = await _apiClient.dio.get(ApiConstants.dashboard);
        if (!_isCurrent(session)) return;
        state = state.copyWith(
          summary: DashboardSummaryModel.fromJson(summaryRes.data),
        );
        await _storage
            .write(
              key: 'cached_dashboard_summary:$userId',
              value: jsonEncode(summaryRes.data),
            )
            .catchError((_) {});
      } catch (_) {
        // The current catalogue remains usable if portfolio totals are unavailable.
      }
    } catch (e) {
      if (!_isCurrent(session)) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.ipos.isEmpty
            ? 'Failed to load IPO data'
            : 'Could not refresh schedules. Showing saved data; dates may be outdated.',
      );
    }
  }

  Future<void> toggleApplied(String ipoId) async {
    final session = ref.read(accountSessionProvider);
    if (session.userId == null) return;
    final updatedIpos = state.ipos.map((ipo) {
      if (ipo.id == ipoId) {
        if (ipo.status == AllotmentStatusEnum.allotted) return ipo;
        final newApplied = !ipo.hasApplied;
        return ipo.copyWith(
          hasApplied: newApplied,
          status: newApplied
              ? AllotmentStatusEnum.pending
              : AllotmentStatusEnum.notApplied,
        );
      }
      return ipo;
    }).toList();

    state = state.copyWith(ipos: updatedIpos);

    try {
      final res = await _apiClient.dio.post(
        '${ApiConstants.ipoList}/$ipoId/toggle-applied',
      );
      if (!_isCurrent(session)) return;
      final data = res.data;
      if (data['hasApplied'] != null) {
        final bool confirmedApplied = data['hasApplied'];
        final updated = state.ipos.map((ipo) {
          if (ipo.id == ipoId) {
            return ipo.copyWith(
              hasApplied: confirmedApplied,
              status: parseAllotmentStatus(data['status']),
            );
          }
          return ipo;
        }).toList();
        state = state.copyWith(ipos: updated);
      }

      // Update dashboard summary counts
      final summaryRes = await _apiClient.dio.get(ApiConstants.dashboard);
      if (!_isCurrent(session)) return;
      state = state.copyWith(
        summary: DashboardSummaryModel.fromJson(summaryRes.data),
      );
    } catch (_) {
      if (!_isCurrent(session)) return;
      fetchIposAndSummary(silent: true);
    }
  }

  void setIssueTypeFilter(String issueType) {
    if (issueType != 'MAINBOARD' && issueType != 'SME') return;
    state = state.copyWith(selectedIssueType: issueType);
  }

  void setLifecycleFilter(IpoLifecycle lifecycle) {
    state = state.copyWith(
      selectedLifecycle: lifecycle,
      selectedStatusFilter: 'ALL',
    );
  }

  void setStatusFilter(String status) {
    state = state.copyWith(
      selectedStatusFilter: status,
      selectedLifecycle: status == 'ALL'
          ? state.selectedLifecycle
          : IpoLifecycle.closed,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final ipoListProvider = NotifierProvider<IpoListNotifier, IpoListState>(
  IpoListNotifier.new,
);
