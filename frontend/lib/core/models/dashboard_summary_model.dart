class DashboardSummaryModel {
  final bool hasPan;
  final String? maskedPan;
  final int allottedCount;
  final int notAllottedCount;
  final int pendingCount;
  final int lookupFailedCount;
  final int notSupportedCount;
  final int totalCount;
  final DateTime? lastScanAt;
  final ActiveJobModel? activeJob;

  DashboardSummaryModel({
    required this.hasPan,
    this.maskedPan,
    required this.allottedCount,
    required this.notAllottedCount,
    required this.pendingCount,
    required this.lookupFailedCount,
    required this.notSupportedCount,
    required this.totalCount,
    this.lastScanAt,
    this.activeJob,
  });

  factory DashboardSummaryModel.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] as Map<String, dynamic>? ?? {};
    return DashboardSummaryModel(
      hasPan: json['hasPan'] as bool? ?? false,
      maskedPan: json['maskedPan'] as String?,
      allottedCount: (counts['allotted'] as num?)?.toInt() ?? 0,
      notAllottedCount: (counts['notAllotted'] as num?)?.toInt() ?? 0,
      pendingCount: (counts['pending'] as num?)?.toInt() ?? 0,
      lookupFailedCount: (counts['lookupFailed'] as num?)?.toInt() ?? 0,
      notSupportedCount: (counts['notSupported'] as num?)?.toInt() ?? 0,
      totalCount: (counts['total'] as num?)?.toInt() ?? 0,
      lastScanAt: json['lastScanAt'] != null ? DateTime.tryParse(json['lastScanAt']) : null,
      activeJob: json['activeJob'] != null
          ? ActiveJobModel.fromJson(json['activeJob'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ActiveJobModel {
  final String id;
  final String status;
  final int totalIpos;
  final int processedIpos;
  final DateTime? startedAt;

  ActiveJobModel({
    required this.id,
    required this.status,
    required this.totalIpos,
    required this.processedIpos,
    this.startedAt,
  });

  factory ActiveJobModel.fromJson(Map<String, dynamic> json) {
    return ActiveJobModel(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'IN_PROGRESS',
      totalIpos: (json['totalIpos'] as num?)?.toInt() ?? 0,
      processedIpos: (json['processedIpos'] as num?)?.toInt() ?? 0,
      startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt']) : null,
    );
  }
}
