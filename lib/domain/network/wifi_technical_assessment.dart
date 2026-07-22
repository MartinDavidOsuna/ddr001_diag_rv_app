enum TechnicalAssessmentAnswer { yes, no, notVerified, notApplicable }

class WifiTechnicalAssessment {
  const WifiTechnicalAssessment({
    this.wifiNearbyAnswer,
    this.wifiConnectionPossibleAnswer,
    this.wifiSignalAdequateAnswer,
    this.wifiInternetAvailableAnswer,
    this.comments = '',
    this.assessedBy,
    this.assessedAt,
    this.schemaVersion = 1,
  });

  final TechnicalAssessmentAnswer? wifiNearbyAnswer;
  final TechnicalAssessmentAnswer? wifiConnectionPossibleAnswer;
  final TechnicalAssessmentAnswer? wifiSignalAdequateAnswer;
  final TechnicalAssessmentAnswer? wifiInternetAvailableAnswer;
  final String comments;
  final String? assessedBy;
  final DateTime? assessedAt;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
    'wifiNearbyAnswer': wifiNearbyAnswer?.name,
    'wifiConnectionPossibleAnswer': wifiConnectionPossibleAnswer?.name,
    'wifiSignalAdequateAnswer': wifiSignalAdequateAnswer?.name,
    'wifiInternetAvailableAnswer': wifiInternetAvailableAnswer?.name,
    'comments': comments.trim(),
    'assessedBy': assessedBy,
    'assessedAt': assessedAt?.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };

  factory WifiTechnicalAssessment.fromJson(
    Map<String, dynamic> json,
  ) => WifiTechnicalAssessment(
    wifiNearbyAnswer: _answer(json['wifiNearbyAnswer']),
    wifiConnectionPossibleAnswer: _answer(json['wifiConnectionPossibleAnswer']),
    wifiSignalAdequateAnswer: _answer(json['wifiSignalAdequateAnswer']),
    wifiInternetAvailableAnswer: _answer(json['wifiInternetAvailableAnswer']),
    comments: json['comments'] as String? ?? '',
    assessedBy: json['assessedBy'] as String?,
    assessedAt: DateTime.tryParse(json['assessedAt'] as String? ?? '')?.toUtc(),
    schemaVersion: json['schemaVersion'] as int? ?? 1,
  );
}

TechnicalAssessmentAnswer? _answer(Object? raw) => TechnicalAssessmentAnswer
    .values
    .where((value) => value.name == raw)
    .firstOrNull;
