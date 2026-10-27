class SavedPanModel {
  final String id;
  final String panMasked;
  final bool consentGiven;
  final DateTime? consentTimestamp;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SavedPanModel({
    required this.id,
    required this.panMasked,
    required this.consentGiven,
    this.consentTimestamp,
    this.createdAt,
    this.updatedAt,
  });

  factory SavedPanModel.fromJson(Map<String, dynamic> json) {
    return SavedPanModel(
      id: json['id'] as String,
      panMasked: json['panMasked'] as String? ?? '**********',
      consentGiven: json['consentGiven'] as bool? ?? true,
      consentTimestamp: json['consentTimestamp'] != null
          ? DateTime.tryParse(json['consentTimestamp'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
