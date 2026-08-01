import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import 'brand_name_normalizer.dart';

enum CatalogSyncStatus { local, pending, synced, error }

enum BrandElementType {
  valve('VALVE', 'Válvula'),
  solenoid('SOLENOID', 'Solenoide'),
  filter('FILTER', 'Filtro'),
  pilot('PILOT', 'Piloto'),
  pressureGauge('PRESSURE_GAUGE', 'Manómetro'),
  flowMeter('FLOW_METER', 'Medidor de flujo'),
  regulatingValve('REGULATING_VALVE', 'Válvula reguladora'),
  communicationDevice('COMMUNICATION_DEVICE', 'Equipo de comunicación'),
  powerDevice('POWER_DEVICE', 'Equipo de alimentación'),
  other('OTHER', 'Otro');

  const BrandElementType(this.wireName, this.label);
  final String wireName, label;

  static BrandElementType? parse(Object? value) {
    final raw = '$value'.trim().toUpperCase();
    for (final type in values) {
      if (type.wireName == raw) return type;
    }
    return switch (raw.toLowerCase()) {
      'valve' => valve,
      'filter' => filter,
      'flow_meter' => flowMeter,
      'regulating_valve' => regulatingValve,
      'communication_equipment' => solenoid,
      _ => null,
    };
  }
}

@immutable
class BrandOption {
  const BrandOption({
    required this.localId,
    required this.name,
    required this.normalizedName,
    required this.elementType,
    required this.status,
    this.remoteId,
    this.active = true,
    this.userCreated = false,
  });
  final String localId, name, normalizedName;
  final BrandElementType? elementType;
  final String? remoteId;
  final CatalogSyncStatus status;
  final bool active, userCreated;

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'remoteId': remoteId,
    'name': name,
    'normalizedName': normalizedName,
    'elementType': elementType?.wireName,
    'status': status.name,
    'active': active,
    'userCreated': userCreated,
  };
  factory BrandOption.fromJson(Map<String, dynamic> json) {
    final normalizedName = normalizeBrandName(
      '${json['name'] ?? json['normalizedName'] ?? ''}',
    );
    return BrandOption(
      localId: json['localId'] as String,
      remoteId: json['remoteId'] as String?,
      name: normalizedName,
      normalizedName: normalizedName,
      elementType: BrandElementType.parse(
        json['elementType'] ?? json['category'],
      ),
      status: CatalogSyncStatus.values.byName(
        json['status'] as String? ?? 'synced',
      ),
      active: json['active'] as bool? ?? true,
      userCreated: json['userCreated'] as bool? ?? false,
    );
  }
}

@immutable
class DiameterOption {
  const DiameterOption({
    required this.localId,
    required this.value,
    required this.unit,
    required this.status,
    this.remoteId,
    this.active = true,
    this.userCreated = false,
  });
  final String localId, unit;
  final String? remoteId;
  final double value;
  final CatalogSyncStatus status;
  final bool active, userCreated;
  String get display => value == value.roundToDouble()
      ? '${value.toInt()}"'
      : '${value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}"';
  Map<String, dynamic> toJson() => {
    'localId': localId,
    'remoteId': remoteId,
    'value': value,
    'unit': unit,
    'status': status.name,
    'active': active,
    'userCreated': userCreated,
  };
  factory DiameterOption.fromJson(Map<String, dynamic> json) => DiameterOption(
    localId: json['localId'] as String,
    remoteId: json['remoteId'] as String?,
    value: (json['value'] as num).toDouble(),
    unit: json['unit'] as String? ?? 'in',
    status: CatalogSyncStatus.values.byName(
      json['status'] as String? ?? 'synced',
    ),
    active: json['active'] as bool? ?? true,
    userCreated: json['userCreated'] as bool? ?? false,
  );
}

@immutable
class PressureRangeOption {
  const PressureRangeOption({
    required this.localId,
    required this.minimum,
    required this.maximum,
    required this.unit,
    required this.status,
    this.remoteId,
    this.ownerUserId,
    this.active = true,
  });
  final String localId, unit;
  final String? remoteId, ownerUserId;
  final double minimum, maximum;
  final CatalogSyncStatus status;
  final bool active;
  String get display =>
      '${formatPressureNumber(minimum)}–${formatPressureNumber(maximum)} $unit';
  String get normalizedKey =>
      '${minimum.toStringAsFixed(4)}|${maximum.toStringAsFixed(4)}|$unit';
  Map<String, dynamic> toJson() => {
    'localId': localId,
    'remoteId': remoteId,
    'minimum': minimum,
    'maximum': maximum,
    'unit': unit,
    'displayName': display,
    'status': status.name,
    'ownerUserId': ownerUserId,
    'active': active,
  };
  factory PressureRangeOption.fromJson(Map<String, dynamic> j) =>
      PressureRangeOption(
        localId: '${j['localId'] ?? j['clientId'] ?? j['id']}',
        remoteId: j['remoteId']?.toString() ?? j['id']?.toString(),
        minimum: (j['minimum'] as num).toDouble(),
        maximum: (j['maximum'] as num).toDouble(),
        unit: '${j['unit']}'.trim().toLowerCase(),
        status: CatalogSyncStatus.values.byName(
          j['status'] as String? ?? 'synced',
        ),
        ownerUserId: j['ownerUserId'] as String?,
        active: j['active'] as bool? ?? j['isActive'] as bool? ?? true,
      );
}

String formatPressureNumber(double value) => value
    .toStringAsFixed(4)
    .replaceFirst(RegExp(r'0+$'), '')
    .replaceFirst(RegExp(r'\.$'), '')
    .replaceAll('.', ',');

class DynamicCatalogRepository extends ChangeNotifier {
  DynamicCatalogRepository({required this.client, required this.box});
  final ApiClient client;
  final Box<String> box;
  String? activeOwnerId;
  void setOwner(String? value) => activeOwnerId = value;
  List<PressureRangeOption> get pressureRanges =>
      box.values
          .where((raw) => raw.contains('"kind":"pressureRange"'))
          .map(
            (raw) => PressureRangeOption.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw)['value'] as Map),
            ),
          )
          .where(
            (item) =>
                item.active &&
                (item.status == CatalogSyncStatus.synced ||
                    item.ownerUserId == activeOwnerId),
          )
          .toList()
        ..sort((a, b) {
          final u = a.unit.compareTo(b.unit);
          if (u != 0) return u;
          final m = a.minimum.compareTo(b.minimum);
          return m != 0 ? m : a.maximum.compareTo(b.maximum);
        });

  List<BrandOption> brands(BrandElementType elementType) =>
      box.values
          .where((raw) => raw.contains('"kind":"brand"'))
          .map((raw) => BrandOption.fromJson(jsonDecode(raw)['value']))
          .where((item) => item.active && item.elementType == elementType)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  List<DiameterOption> get diameters {
    final values =
        box.values
            .where((raw) => raw.contains('"kind":"diameter"'))
            .map((raw) => DiameterOption.fromJson(jsonDecode(raw)['value']))
            .where((item) => item.active)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    return values;
  }

  String? remoteIdFor(String localId) {
    final raw =
        box.get('brand:$localId') ??
        box.get('diameter:$localId') ??
        box.get('pressureRange:$localId');
    if (raw == null) return null;
    final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final value = Map<String, dynamic>.from(decoded['value'] as Map);
    return value['remoteId'] as String?;
  }

  Future<void> seed() async {
    if (diameters.isNotEmpty) return;
    await _putDiameter(
      const DiameterOption(
        localId: '30000000-0000-4000-8000-000000000003',
        remoteId: '30000000-0000-4000-8000-000000000003',
        value: 3,
        unit: 'in',
        status: CatalogSyncStatus.synced,
      ),
    );
    await _putDiameter(
      const DiameterOption(
        localId: '40000000-0000-4000-8000-000000000004',
        remoteId: '40000000-0000-4000-8000-000000000004',
        value: 4,
        unit: 'in',
        status: CatalogSyncStatus.synced,
      ),
    );
  }

  Future<BrandOption> createBrand(
    String name,
    BrandElementType elementType,
  ) async {
    final normalized = normalizeBrandName(name);
    final duplicate = brands(
      elementType,
    ).where((item) => item.normalizedName == normalized).firstOrNull;
    if (duplicate != null) return duplicate;
    final value = BrandOption(
      localId: const Uuid().v4(),
      name: normalized,
      normalizedName: normalized,
      elementType: elementType,
      status: CatalogSyncStatus.pending,
      userCreated: true,
    );
    await _putBrand(value);
    notifyListeners();
    return value;
  }

  Future<DiameterOption> createDiameter(double value) async {
    if (!value.isFinite || value <= 0 || value > 120) {
      throw const FormatException(
        'El diámetro debe ser mayor a 0 y hasta 120".',
      );
    }
    final normalized = double.parse(value.toStringAsFixed(3));
    final duplicate = diameters
        .where((item) => item.value == normalized && item.unit == 'in')
        .firstOrNull;
    if (duplicate != null) return duplicate;
    final item = DiameterOption(
      localId: const Uuid().v4(),
      value: normalized,
      unit: 'in',
      status: CatalogSyncStatus.pending,
      userCreated: true,
    );
    await _putDiameter(item);
    notifyListeners();
    return item;
  }

  Future<PressureRangeOption> createPressureRange(
    double minimum,
    double maximum,
    String unit, {
    required String ownerUserId,
  }) async {
    final normalizedUnit = unit.trim().toLowerCase();
    if (!minimum.isFinite ||
        !maximum.isFinite ||
        minimum < 0 ||
        maximum <= minimum) {
      throw const FormatException(
        'El valor máximo debe ser mayor que el mínimo.',
      );
    }
    if (!const {'psi', 'bar'}.contains(normalizedUnit)) {
      throw const FormatException('Selecciona una unidad.');
    }
    final min = double.parse(minimum.toStringAsFixed(4)),
        max = double.parse(maximum.toStringAsFixed(4));
    final key =
        '${min.toStringAsFixed(4)}|${max.toStringAsFixed(4)}|$normalizedUnit';
    final duplicate = pressureRanges
        .where((x) => x.normalizedKey == key)
        .firstOrNull;
    if (duplicate != null) return duplicate;
    final item = PressureRangeOption(
      localId: const Uuid().v4(),
      minimum: min,
      maximum: max,
      unit: normalizedUnit,
      status: CatalogSyncStatus.pending,
      ownerUserId: ownerUserId,
    );
    await _putPressureRange(item);
    notifyListeners();
    return item;
  }

  Future<void> synchronizePending() async {
    for (final item in pressureRanges.where(
      (x) =>
          x.status != CatalogSyncStatus.synced &&
          x.ownerUserId == activeOwnerId,
    )) {
      try {
        final response = await client.dio.post<Map<String, dynamic>>(
          '/catalogs/pressure-ranges',
          data: {
            'clientId': item.localId,
            'minimum': item.minimum,
            'maximum': item.maximum,
            'unit': item.unit,
          },
          options: Options(
            headers: {'Idempotency-Key': 'pressure-range-${item.localId}'},
          ),
        );
        final data = Map<String, dynamic>.from(
          response.data?['item'] as Map? ?? const {},
        );
        await _putPressureRange(
          PressureRangeOption(
            localId: item.localId,
            remoteId: '${response.data?['canonicalId'] ?? data['id']}',
            minimum: (data['minimum'] as num?)?.toDouble() ?? item.minimum,
            maximum: (data['maximum'] as num?)?.toDouble() ?? item.maximum,
            unit: '${data['unit'] ?? item.unit}',
            status: CatalogSyncStatus.synced,
            active: data['isActive'] as bool? ?? true,
          ),
        );
      } on Object {
        await _putPressureRange(
          PressureRangeOption(
            localId: item.localId,
            remoteId: item.remoteId,
            minimum: item.minimum,
            maximum: item.maximum,
            unit: item.unit,
            status: CatalogSyncStatus.error,
            ownerUserId: item.ownerUserId,
          ),
        );
      }
    }
    await _refreshPressureRanges();
    final allBrands = box.values
        .where((raw) => raw.contains('"kind":"brand"'))
        .map((raw) => BrandOption.fromJson(jsonDecode(raw)['value']));
    for (final brand in allBrands.where(
      (item) => item.status != CatalogSyncStatus.synced,
    )) {
      try {
        final response = await client.dio.post<Map<String, dynamic>>(
          '/catalogs/brands',
          data: {
            'clientUuid': brand.localId,
            'name': normalizeBrandName(brand.name),
            'elementType': brand.elementType?.wireName,
          },
          options: Options(
            headers: {'Idempotency-Key': 'brand-${brand.localId}'},
          ),
        );
        await _putBrand(
          BrandOption(
            localId: brand.localId,
            remoteId: '${response.data?['brand_id'] ?? response.data?['id']}',
            name: normalizeBrandName('${response.data?['name'] ?? brand.name}'),
            normalizedName: normalizeBrandName(
              '${response.data?['normalized_name'] ?? response.data?['normalizedName'] ?? brand.name}',
            ),
            elementType: brand.elementType,
            status: CatalogSyncStatus.synced,
            userCreated: true,
          ),
        );
      } on Object {
        await _putBrand(
          BrandOption(
            localId: brand.localId,
            remoteId: brand.remoteId,
            name: brand.name,
            normalizedName: brand.normalizedName,
            elementType: brand.elementType,
            status: CatalogSyncStatus.error,
            userCreated: brand.userCreated,
          ),
        );
      }
    }
    await _refreshAllBrands();
    for (final diameter in diameters.where(
      (item) => item.status != CatalogSyncStatus.synced,
    )) {
      try {
        final response = await client.dio.post<Map<String, dynamic>>(
          '/catalogs/diameters',
          data: {
            'clientId': diameter.localId,
            'nominalValue': diameter.value,
            'unit': diameter.unit,
          },
          options: Options(
            headers: {'Idempotency-Key': 'diameter-${diameter.localId}'},
          ),
        );
        await _putDiameter(
          DiameterOption(
            localId: diameter.localId,
            remoteId:
                '${response.data?['diameter_id'] ?? response.data?['id']}',
            value: diameter.value,
            unit: diameter.unit,
            status: CatalogSyncStatus.synced,
            userCreated: true,
          ),
        );
      } on Object {
        await _putDiameter(
          DiameterOption(
            localId: diameter.localId,
            remoteId: diameter.remoteId,
            value: diameter.value,
            unit: diameter.unit,
            status: CatalogSyncStatus.error,
            userCreated: diameter.userCreated,
          ),
        );
      }
    }
    notifyListeners();
  }

  Future<void> _refreshPressureRanges() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/catalogs/pressure-ranges',
      );
      for (final raw
          in (response.data?['items'] as List? ?? const []).whereType<Map>()) {
        final j = Map<String, dynamic>.from(raw), id = '${j['id']}';
        final existing = pressureRanges
            .where((x) => x.remoteId == id)
            .firstOrNull;
        await _putPressureRange(
          PressureRangeOption(
            localId: existing?.localId ?? '${j['clientId'] ?? id}',
            remoteId: id,
            minimum: (j['minimum'] as num).toDouble(),
            maximum: (j['maximum'] as num).toDouble(),
            unit: '${j['unit']}',
            status: CatalogSyncStatus.synced,
            active: j['isActive'] as bool? ?? true,
          ),
        );
      }
    } on Object {
      /* preserve local catalog */
    }
  }

  Future<void> _refreshAllBrands() async {
    for (final elementType in BrandElementType.values) {
      try {
        final response = await client.dio.get<Map<String, dynamic>>(
          '/catalogs/brands',
          queryParameters: {'elementType': elementType.wireName},
        );
        final items = response.data?['items'];
        if (items is! List) continue;
        for (final raw in items.whereType<Map>()) {
          final json = Map<String, dynamic>.from(raw);
          final remoteId = '${json['id'] ?? json['brand_id']}';
          final existing = brands(
            elementType,
          ).where((item) => item.remoteId == remoteId).firstOrNull;
          final normalized = normalizeBrandName('${json['name']}');
          await _putBrand(
            BrandOption(
              localId: existing?.localId ?? '${json['clientId'] ?? remoteId}',
              remoteId: remoteId,
              name: normalized,
              normalizedName: normalized,
              elementType: elementType,
              status: CatalogSyncStatus.synced,
              active: json['active'] as bool? ?? true,
              userCreated: json['source'] == 'user_created',
            ),
          );
        }
      } on Object {
        // A failed catalog download must not discard or downgrade local brands.
      }
    }
  }

  Future<void> _putBrand(BrandOption value) => box.put(
    'brand:${value.localId}',
    jsonEncode({'kind': 'brand', 'value': value.toJson()}),
  );
  Future<void> _putDiameter(DiameterOption value) => box.put(
    'diameter:${value.localId}',
    jsonEncode({'kind': 'diameter', 'value': value.toJson()}),
  );
  Future<void> _putPressureRange(PressureRangeOption value) => box.put(
    'pressureRange:${value.localId}',
    jsonEncode({'kind': 'pressureRange', 'value': value.toJson()}),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
