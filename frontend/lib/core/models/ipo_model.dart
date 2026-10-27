enum AllotmentStatusEnum {
  allotted,
  notAllotted,
  pending,
  lookupFailed,
  notSupported,
}

AllotmentStatusEnum parseAllotmentStatus(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'ALLOTTED':
      return AllotmentStatusEnum.allotted;
    case 'NOT_ALLOTTED':
      return AllotmentStatusEnum.notAllotted;
    case 'LOOKUP_FAILED':
      return AllotmentStatusEnum.lookupFailed;
    case 'NOT_SUPPORTED':
      return AllotmentStatusEnum.notSupported;
    case 'PENDING':
    default:
      return AllotmentStatusEnum.pending;
  }
}

String allotmentStatusLabel(AllotmentStatusEnum status) {
  switch (status) {
    case AllotmentStatusEnum.allotted:
      return 'Allotted';
    case AllotmentStatusEnum.notAllotted:
      return 'Not Allotted';
    case AllotmentStatusEnum.pending:
      return 'Pending';
    case AllotmentStatusEnum.lookupFailed:
      return 'Lookup Failed';
    case AllotmentStatusEnum.notSupported:
      return 'Not Supported';
  }
}

class IpoItemModel {
  final String id;
  final String? externalId;
  final String name;
  final String slug;
  final String issueType; // MAINBOARD or SME
  final DateTime? openDate;
  final DateTime? closeDate;
  final String? priceBand;
  final int? lotSize;
  final DateTime? allotmentDate;
  final DateTime? listingDate;
  final String registrar;
  final String officialVerificationUrl;
  final AllotmentStatusEnum status;
  final int? allottedQuantity;
  final DateTime? lastCheckedAt;
  final String? diagnosticMessage;

  IpoItemModel({
    required this.id,
    this.externalId,
    required this.name,
    required this.slug,
    required this.issueType,
    this.openDate,
    this.closeDate,
    this.priceBand,
    this.lotSize,
    this.allotmentDate,
    this.listingDate,
    required this.registrar,
    required this.officialVerificationUrl,
    required this.status,
    this.allottedQuantity,
    this.lastCheckedAt,
    this.diagnosticMessage,
  });

  factory IpoItemModel.fromJson(Map<String, dynamic> json) {
    return IpoItemModel(
      id: json['id'] as String,
      externalId: json['externalId'] as String?,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      issueType: json['issueType'] as String? ?? 'MAINBOARD',
      openDate: json['openDate'] != null ? DateTime.tryParse(json['openDate']) : null,
      closeDate: json['closeDate'] != null ? DateTime.tryParse(json['closeDate']) : null,
      priceBand: json['priceBand'] as String?,
      lotSize: json['lotSize'] as int?,
      allotmentDate: json['allotmentDate'] != null ? DateTime.tryParse(json['allotmentDate']) : null,
      listingDate: json['listingDate'] != null ? DateTime.tryParse(json['listingDate']) : null,
      registrar: json['registrar'] as String? ?? 'UNKNOWN',
      officialVerificationUrl: json['officialVerificationUrl'] as String? ?? '',
      status: parseAllotmentStatus(json['status'] as String?),
      allottedQuantity: json['allottedQuantity'] as int?,
      lastCheckedAt: json['lastCheckedAt'] != null ? DateTime.tryParse(json['lastCheckedAt']) : null,
      diagnosticMessage: json['diagnosticMessage'] as String?,
    );
  }
}

class AllotmentHistoryItemModel {
  final String id;
  final AllotmentStatusEnum status;
  final int? allottedQuantity;
  final String source;
  final String? errorCode;
  final String? diagnosticMessage;
  final DateTime timestamp;

  AllotmentHistoryItemModel({
    required this.id,
    required this.status,
    this.allottedQuantity,
    required this.source,
    this.errorCode,
    this.diagnosticMessage,
    required this.timestamp,
  });

  factory AllotmentHistoryItemModel.fromJson(Map<String, dynamic> json) {
    return AllotmentHistoryItemModel(
      id: json['id'] as String,
      status: parseAllotmentStatus(json['status'] as String?),
      allottedQuantity: json['allottedQuantity'] as int?,
      source: json['source'] as String? ?? 'PEEK',
      errorCode: json['errorCode'] as String?,
      diagnosticMessage: json['diagnosticMessage'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
