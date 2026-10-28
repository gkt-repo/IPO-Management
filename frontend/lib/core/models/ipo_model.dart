enum IpoLifecycle { open, closed, upcoming, unknown }

extension IpoLifecycleLabel on IpoLifecycle {
  String get label => switch (this) {
    IpoLifecycle.open => 'Open',
    IpoLifecycle.closed => 'Closed',
    IpoLifecycle.upcoming => 'Upcoming',
    IpoLifecycle.unknown => 'Dates unavailable',
  };
}

DateTime? parseScheduleDate(String? value) {
  if (value == null) return null;
  // A date without a zone is a calendar date, never the device's midnight.
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return DateTime.tryParse('${value}T00:00:00Z');
  }
  return DateTime.tryParse(value);
}

// UTC-midnight values represent Indian calendar dates in the legacy API.
DateTime? biddingTime(DateTime? date, int hour) {
  if (date == null) return null;
  final utc = !date.isUtc && date.hour == 0 && date.minute == 0 && date.second == 0 && date.millisecond == 0
      ? DateTime.utc(date.year, date.month, date.day)
      : date.toUtc();
  if (utc.hour != 0 ||
      utc.minute != 0 ||
      utc.second != 0 ||
      utc.millisecond != 0) {
    return utc;
  }
  return utc.add(Duration(minutes: hour * 60 - 330));
}

DateTime inIndia(DateTime time) =>
    time.toUtc().add(const Duration(minutes: 330));

enum AllotmentStatusEnum {
  allotted,
  notAllotted,
  pending,
  lookupFailed,
  notSupported,
  notApplied,
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
    case 'NOT_APPLIED':
      return AllotmentStatusEnum.notApplied;
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
    case AllotmentStatusEnum.notApplied:
      return 'Not Applied';
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
  final double? issuePrice;
  final double? listingPrice;
  final double? currentPrice;
  final int? lotSize;
  final DateTime? allotmentDate;
  final DateTime? listingDate;
  final String registrar;
  final String officialVerificationUrl;
  final AllotmentStatusEnum status;
  final int? allottedQuantity;
  final DateTime? lastCheckedAt;
  final String? diagnosticMessage;
  final bool hasApplied;
  final bool?
  isUpcomingExplicit; // Legacy cached flag; never used for classification.
  final DateTime? biddingOpensAt;
  final DateTime? biddingClosesAt;

  IpoItemModel({
    required this.id,
    this.externalId,
    required this.name,
    required this.slug,
    required this.issueType,
    this.openDate,
    this.closeDate,
    this.priceBand,
    this.issuePrice,
    this.listingPrice,
    this.currentPrice,
    this.lotSize,
    this.allotmentDate,
    this.listingDate,
    required this.registrar,
    required this.officialVerificationUrl,
    required this.status,
    this.allottedQuantity,
    this.lastCheckedAt,
    this.diagnosticMessage,
    this.hasApplied = false,
    this.isUpcomingExplicit,
    this.biddingOpensAt,
    this.biddingClosesAt,
  });

  DateTime? get opensAt => biddingOpensAt ?? biddingTime(openDate, 10);
  DateTime? get closesAt =>
      biddingClosesAt ?? biddingTime(closeDate, issueType == 'SME' ? 16 : 17);

  IpoLifecycle lifecycleAt(DateTime now) {
    final opens = opensAt;
    final closes = closesAt;
    if (opens != null && closes != null && !closes.isAfter(opens)) {
      return IpoLifecycle.unknown;
    }
    if (closes != null && !now.isBefore(closes)) return IpoLifecycle.closed;
    if (listingPrice != null ||
        (listingDate != null && !now.isBefore(listingDate!))) {
      return IpoLifecycle.closed;
    }
    if (opens != null && now.isBefore(opens)) return IpoLifecycle.upcoming;
    if (opens != null &&
        closes != null &&
        !now.isBefore(opens) &&
        now.isBefore(closes)) {
      return IpoLifecycle.open;
    }
    return IpoLifecycle.unknown;
  }

  IpoLifecycle get lifecycle => lifecycleAt(DateTime.now());
  bool get isUpcoming => lifecycle == IpoLifecycle.upcoming;

  static double? _extractUpperPrice(String? priceBand) {
    if (priceBand == null || priceBand.isEmpty) return null;
    final clean = priceBand.replaceAll(',', '');
    final matches = RegExp(r'(\d+(?:\.\d+)?)').allMatches(clean);
    if (matches.isEmpty) return null;
    double maxVal = 0;
    for (final m in matches) {
      final val = double.tryParse(m.group(1) ?? '');
      if (val != null && val > maxVal) {
        maxVal = val;
      }
    }
    return maxVal > 0 ? maxVal : null;
  }

  /// Only use supplied prices; company-name guesses can invent a listing.
  double? get effectiveIssuePrice =>
      issuePrice ?? _extractUpperPrice(priceBand);
  double? get effectiveListingPrice => listingPrice;

  /// Profit/gain per share (Listing Price - Issue Price)
  double? get gainPerShare {
    final l = effectiveListingPrice;
    final i = effectiveIssuePrice;
    if (l == null || i == null) return null;
    return l - i;
  }

  /// Percentage profit or gain
  double? get gainPercentage {
    final g = gainPerShare;
    final i = effectiveIssuePrice;
    if (g == null || i == null || i <= 0) return null;
    return (g / i) * 100.0;
  }

  /// Total profit on this IPO based on allotted shares:
  /// (Listing Price - Issue Price) * allottedQuantity
  double? get totalProfit {
    final g = gainPerShare;
    final q = allottedQuantity;
    if (g == null || q == null || q <= 0) return null;
    return g * q;
  }

  /// Total investment for allotted shares: Issue Price * allottedQuantity
  double? get totalInvested {
    final i = effectiveIssuePrice;
    final q = allottedQuantity;
    if (i == null || q == null || q <= 0) return null;
    return i * q;
  }

  /// Total current market value on listing: Listing Price * allottedQuantity
  double? get totalCurrentValue {
    final l = effectiveListingPrice;
    final q = allottedQuantity;
    if (l == null || q == null || q <= 0) return null;
    return l * q;
  }

  factory IpoItemModel.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final slug = json['slug'] as String? ?? '';
    final priceBand = json['priceBand'] as String?;
    final lotSize = json['lotSize'] as int?;

    final status = parseAllotmentStatus(json['status'] as String?);
    final isAllotted = status == AllotmentStatusEnum.allotted;
    final hasApplied = isAllotted || (json['hasApplied'] as bool? ?? false);

    return IpoItemModel(
      id: json['id'] as String,
      externalId: json['externalId'] as String?,
      name: name,
      slug: slug,
      issueType: json['issueType'] as String? ?? 'MAINBOARD',
      openDate: json['openDate'] != null
          ? parseScheduleDate(json['openDate'] as String?)
          : null,
      closeDate: json['closeDate'] != null
          ? parseScheduleDate(json['closeDate'] as String?)
          : null,
      priceBand: priceBand,
      issuePrice: json['issuePrice'] != null
          ? (json['issuePrice'] as num).toDouble()
          : _extractUpperPrice(priceBand),
      listingPrice: json['listingPrice'] != null
          ? (json['listingPrice'] as num).toDouble()
          : null,
      currentPrice: json['currentPrice'] != null
          ? (json['currentPrice'] as num).toDouble()
          : null,
      lotSize: lotSize,
      allotmentDate: json['allotmentDate'] != null
          ? parseScheduleDate(json['allotmentDate'] as String?)
          : null,
      listingDate: json['listingDate'] != null
          ? parseScheduleDate(json['listingDate'] as String?)
          : null,
      registrar: json['registrar'] as String? ?? 'UNKNOWN',
      officialVerificationUrl: json['officialVerificationUrl'] as String? ?? '',
      status: status,
      allottedQuantity: json['allottedQuantity'] as int?,
      lastCheckedAt: json['lastCheckedAt'] != null
          ? DateTime.tryParse(json['lastCheckedAt'])
          : null,
      diagnosticMessage: json['diagnosticMessage'] as String?,
      hasApplied: hasApplied,
      isUpcomingExplicit: json['isUpcoming'] as bool?,
      biddingOpensAt: DateTime.tryParse(
        json['biddingOpensAt'] as String? ?? '',
      ),
      biddingClosesAt: DateTime.tryParse(
        json['biddingClosesAt'] as String? ?? '',
      ),
    );
  }

  IpoItemModel copyWith({
    String? id,
    String? externalId,
    String? name,
    String? slug,
    String? issueType,
    DateTime? openDate,
    DateTime? closeDate,
    String? priceBand,
    double? issuePrice,
    double? listingPrice,
    double? currentPrice,
    int? lotSize,
    DateTime? allotmentDate,
    DateTime? listingDate,
    String? registrar,
    String? officialVerificationUrl,
    AllotmentStatusEnum? status,
    int? allottedQuantity,
    DateTime? lastCheckedAt,
    String? diagnosticMessage,
    bool? hasApplied,
    bool? isUpcomingExplicit,
  }) {
    return IpoItemModel(
      id: id ?? this.id,
      externalId: externalId ?? this.externalId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      issueType: issueType ?? this.issueType,
      openDate: openDate ?? this.openDate,
      closeDate: closeDate ?? this.closeDate,
      priceBand: priceBand ?? this.priceBand,
      issuePrice: issuePrice ?? this.issuePrice,
      listingPrice: listingPrice ?? this.listingPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      lotSize: lotSize ?? this.lotSize,
      allotmentDate: allotmentDate ?? this.allotmentDate,
      listingDate: listingDate ?? this.listingDate,
      registrar: registrar ?? this.registrar,
      officialVerificationUrl:
          officialVerificationUrl ?? this.officialVerificationUrl,
      status: status ?? this.status,
      allottedQuantity: allottedQuantity ?? this.allottedQuantity,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      diagnosticMessage: diagnosticMessage ?? this.diagnosticMessage,
      hasApplied: hasApplied ?? this.hasApplied,
      isUpcomingExplicit: isUpcomingExplicit ?? this.isUpcomingExplicit,
      biddingOpensAt: openDate == null ? biddingOpensAt : null,
      biddingClosesAt: closeDate == null && issueType == null
          ? biddingClosesAt
          : null,
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
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
