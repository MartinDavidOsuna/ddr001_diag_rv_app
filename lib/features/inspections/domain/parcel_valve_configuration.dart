enum ParcelValveConfigurationType {
  one3('ONE_3', '1 de 3"', 1, 3),
  two3('TWO_3', '2 de 3"', 2, 3),
  three3('THREE_3', '3 de 3"', 3, 3),
  three4('THREE_4', '3 de 4"', 3, 4),
  other('OTHER', 'Otro', null, null);

  const ParcelValveConfigurationType(
    this.wireName,
    this.label,
    this.fixedCount,
    this.fixedDiameter,
  );
  final String wireName, label;
  final int? fixedCount, fixedDiameter;

  static ParcelValveConfigurationType parse(Object? value) {
    final raw = '$value';
    return values.firstWhere(
      (item) => item.wireName == raw || item.name == raw,
      orElse: () => other,
    );
  }
}

class ParcelValve {
  const ParcelValve({
    required this.index,
    this.valveBrand,
    this.diameter,
    this.hasSolenoid = false,
    this.solenoidBrand,
    this.hasPilot = false,
    this.pilotBrand,
    this.hasPressureGauge = false,
    this.pressureGaugeBrand,
  });
  final int index;
  final Map<String, dynamic>? valveBrand, diameter;
  final bool hasSolenoid, hasPilot, hasPressureGauge;
  final Map<String, dynamic>? solenoidBrand, pilotBrand, pressureGaugeBrand;

  ParcelValve copyWith({
    Map<String, dynamic>? valveBrand,
    Map<String, dynamic>? diameter,
    bool? hasSolenoid,
    Map<String, dynamic>? solenoidBrand,
    bool? hasPilot,
    Map<String, dynamic>? pilotBrand,
    bool? hasPressureGauge,
    Map<String, dynamic>? pressureGaugeBrand,
  }) => ParcelValve(
    index: index,
    valveBrand: valveBrand ?? this.valveBrand,
    diameter: diameter ?? this.diameter,
    hasSolenoid: hasSolenoid ?? this.hasSolenoid,
    solenoidBrand: (hasSolenoid ?? this.hasSolenoid)
        ? (solenoidBrand ?? this.solenoidBrand)
        : null,
    hasPilot: hasPilot ?? this.hasPilot,
    pilotBrand: (hasPilot ?? this.hasPilot)
        ? (pilotBrand ?? this.pilotBrand)
        : null,
    hasPressureGauge: hasPressureGauge ?? this.hasPressureGauge,
    pressureGaugeBrand: (hasPressureGauge ?? this.hasPressureGauge)
        ? (pressureGaugeBrand ?? this.pressureGaugeBrand)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'valveBrand': valveBrand,
    'diameter': diameter,
    'hasSolenoid': hasSolenoid,
    'solenoidBrand': solenoidBrand,
    'hasPilot': hasPilot,
    'pilotBrand': pilotBrand,
    'hasPressureGauge': hasPressureGauge,
    'pressureGaugeBrand': pressureGaugeBrand,
  };
  factory ParcelValve.fromJson(Map<String, dynamic> json) => ParcelValve(
    index: (json['index'] as num).toInt(),
    valveBrand: _map(json['valveBrand']),
    diameter: _map(json['diameter']),
    hasSolenoid: json['hasSolenoid'] as bool? ?? false,
    solenoidBrand: _map(json['solenoidBrand']),
    hasPilot: json['hasPilot'] as bool? ?? false,
    pilotBrand: _map(json['pilotBrand']),
    hasPressureGauge: json['hasPressureGauge'] as bool? ?? false,
    pressureGaugeBrand: _map(json['pressureGaugeBrand']),
  );
}

class ParcelValveConfiguration {
  const ParcelValveConfiguration({
    required this.type,
    required this.valveCount,
    required this.valves,
    this.customDescription,
    this.retiredValves = const [],
  });
  final ParcelValveConfigurationType type;
  final String? customDescription;
  final int valveCount;
  final List<ParcelValve> valves, retiredValves;

  ParcelValveConfiguration copyWith({
    ParcelValveConfigurationType? type,
    String? customDescription,
    int? valveCount,
    List<ParcelValve>? valves,
    List<ParcelValve>? retiredValves,
  }) => ParcelValveConfiguration(
    type: type ?? this.type,
    customDescription: customDescription ?? this.customDescription,
    valveCount: valveCount ?? this.valveCount,
    valves: valves ?? this.valves,
    retiredValves: retiredValves ?? this.retiredValves,
  );

  Map<String, dynamic> toJson() => {
    'type': type.wireName,
    'customDescription': customDescription,
    'valveCount': valveCount,
    'valves': valves.map((item) => item.toJson()).toList(),
    'retiredValves': retiredValves.map((item) => item.toJson()).toList(),
  };
  factory ParcelValveConfiguration.fromJson(
    Map<String, dynamic> json,
  ) => ParcelValveConfiguration(
    type: ParcelValveConfigurationType.parse(json['type']),
    customDescription: json['customDescription'] as String?,
    valveCount: (json['valveCount'] as num).toInt(),
    valves: (json['valves'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ParcelValve.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    retiredValves: (json['retiredValves'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ParcelValve.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
  );
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
