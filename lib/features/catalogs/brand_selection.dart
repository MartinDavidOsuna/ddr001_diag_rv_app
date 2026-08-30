enum BrandReadability { readable, illegible }

class BrandSelection {
  const BrandSelection({
    required this.mode,
    this.brandId,
    required this.displayName,
    this.illegibleReason,
    this.evidencePhotoId,
    this.localEvidencePath,
  });
  final BrandReadability mode;
  final String? brandId, illegibleReason, evidencePhotoId, localEvidencePath;
  final String displayName;
  bool get isComplete => mode == BrandReadability.readable
      ? brandId != null
      : (illegibleReason?.trim().length ?? 0) >= 10;
  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'brandId': brandId,
    'displayName': displayName,
    'reason': illegibleReason,
    'evidencePhotoId': evidencePhotoId,
    'localEvidencePath': localEvidencePath,
  };
  factory BrandSelection.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'] == 'illegible'
        ? BrandReadability.illegible
        : BrandReadability.readable;
    return BrandSelection(
      mode: mode,
      brandId: json['brandId']?.toString() ?? json['catalogId']?.toString(),
      displayName:
          '${json['displayName'] ?? json['displayValue'] ?? (mode == BrandReadability.illegible ? 'Ilegible' : 'No capturado')}',
      illegibleReason: json['reason']?.toString(),
      evidencePhotoId: json['evidencePhotoId']?.toString(),
      localEvidencePath: json['localEvidencePath']?.toString(),
    );
  }
}

Map<String, dynamic> illegibleBrandMap(
  String reason, {
  String? evidencePhotoId,
  String? localEvidencePath,
}) => {
  'mode': 'illegible',
  'brandId': null,
  'catalogId': null,
  'localCatalogId': null,
  'displayName': 'Ilegible',
  'displayValue': 'Ilegible',
  'reason': reason.trim(),
  'evidencePhotoId': evidencePhotoId,
  'localEvidencePath': localEvidencePath,
};
