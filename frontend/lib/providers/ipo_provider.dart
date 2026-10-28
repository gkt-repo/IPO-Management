import 'dart:convert';
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
  final String selectedIssueType; // 'MAINBOARD', 'SME', 'ALL'
  final String selectedStatusFilter; // 'ALL', 'ALLOTTED', 'NOT_ALLOTTED', 'PENDING'
  final String searchQuery;

  IpoListState({
    required this.isLoading,
    required this.ipos,
    this.summary,
    this.errorMessage,
    this.selectedIssueType = 'MAINBOARD',
    this.selectedStatusFilter = 'ALL',
    this.searchQuery = '',
  });

  factory IpoListState.initial() => IpoListState(
        isLoading: false,
        ipos: [],
        selectedIssueType: 'MAINBOARD',
      );

  List<IpoItemModel> get filteredIpos {
    final result = ipos.where((ipo) {
      if (selectedIssueType != 'ALL' && ipo.issueType != selectedIssueType) {
        return false;
      }
      if (selectedStatusFilter != 'ALL') {
        if (selectedStatusFilter == 'ALLOTTED' && ipo.status != AllotmentStatusEnum.allotted) return false;
        if (selectedStatusFilter == 'NOT_ALLOTTED' && ipo.status != AllotmentStatusEnum.notAllotted) return false;
        if (selectedStatusFilter == 'PENDING' && ipo.status != AllotmentStatusEnum.pending) return false;
        if (selectedStatusFilter == 'LOOKUP_FAILED' && ipo.status != AllotmentStatusEnum.lookupFailed) return false;
      }
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        if (!ipo.name.toLowerCase().contains(q) && !ipo.registrar.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    // Sort latest IPOs at the top (listingDate -> allotmentDate -> closeDate -> openDate)
    result.sort((a, b) {
      final dateA = a.listingDate ?? a.allotmentDate ?? a.closeDate ?? a.openDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = b.listingDate ?? b.allotmentDate ?? b.closeDate ?? b.openDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });

    return result;
  }

  /// List of all allotted IPOs regardless of current filter, latest first
  List<IpoItemModel> get allottedIpos {
    final list = ipos.where((ipo) => ipo.status == AllotmentStatusEnum.allotted).toList();
    list.sort((a, b) {
      final dateA = a.listingDate ?? a.allotmentDate ?? a.closeDate ?? a.openDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = b.listingDate ?? b.allotmentDate ?? b.closeDate ?? b.openDate ?? DateTime.fromMillisecondsSinceEpoch(0);
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
  }) {
    return IpoListState(
      isLoading: isLoading ?? this.isLoading,
      ipos: ipos ?? this.ipos,
      summary: summary ?? this.summary,
      errorMessage: errorMessage,
      selectedIssueType: selectedIssueType ?? this.selectedIssueType,
      selectedStatusFilter: selectedStatusFilter ?? this.selectedStatusFilter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class IpoListNotifier extends Notifier<IpoListState> {
  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  IpoListState build() {
    return IpoListState.initial();
  }

  Future<void> fetchIposAndSummary({bool silent = false}) async {
    // Fast local database cache: load instantly if in-memory list is empty
    if (state.ipos.isEmpty) {
      try {
        final cachedIposRaw = await _storage.read(key: 'cached_ipos_list');
        final cachedSummaryRaw = await _storage.read(key: 'cached_dashboard_summary');
        if (cachedIposRaw != null && cachedIposRaw.isNotEmpty) {
          final ipoJson = jsonDecode(cachedIposRaw) as List;
          final cachedList = ipoJson.map((i) => IpoItemModel.fromJson(i)).toList();
          DashboardSummaryModel? cachedSummary;
          if (cachedSummaryRaw != null && cachedSummaryRaw.isNotEmpty) {
            cachedSummary = DashboardSummaryModel.fromJson(jsonDecode(cachedSummaryRaw));
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

    if (!silent && state.ipos.isEmpty) {
      state = state.copyWith(isLoading: true, errorMessage: null);
    }

    try {
      final summaryRes = await _apiClient.dio.get(ApiConstants.dashboard);
      final summary = DashboardSummaryModel.fromJson(summaryRes.data);

      final ipoRes = await _apiClient.dio.get(ApiConstants.ipoList);
      final list = (ipoRes.data as List).map((i) => IpoItemModel.fromJson(i)).toList();

      state = state.copyWith(
        isLoading: false,
        ipos: list,
        summary: summary,
      );

      // Persist to local database cache for instant 0ms startup
      _storage.write(key: 'cached_dashboard_summary', value: jsonEncode(summaryRes.data)).catchError((_) {});
      _storage.write(key: 'cached_ipos_list', value: jsonEncode(ipoRes.data)).catchError((_) {});
    } catch (e) {
      // Only set error message if no local cache is available
      if (state.ipos.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load IPO data',
        );
      }
    }
  }

  Future<void> toggleApplied(String ipoId) async {
    final updatedIpos = state.ipos.map((ipo) {
      if (ipo.id == ipoId) {
        if (ipo.status == AllotmentStatusEnum.allotted) return ipo;
        final newApplied = !ipo.hasApplied;
        return ipo.copyWith(
          hasApplied: newApplied,
          status: newApplied ? AllotmentStatusEnum.pending : AllotmentStatusEnum.notApplied,
        );
      }
      return ipo;
    }).toList();

    state = state.copyWith(ipos: updatedIpos);

    try {
      final res = await _apiClient.dio.post('${ApiConstants.ipoList}/$ipoId/toggle-applied');
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
      state = state.copyWith(summary: DashboardSummaryModel.fromJson(summaryRes.data));
    } catch (_) {
      fetchIposAndSummary(silent: true);
    }
  }

  void setIssueTypeFilter(String issueType) {
    state = state.copyWith(selectedIssueType: issueType);
  }

  void setStatusFilter(String status) {
    state = state.copyWith(selectedStatusFilter: status);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final ipoListProvider = NotifierProvider<IpoListNotifier, IpoListState>(IpoListNotifier.new);
