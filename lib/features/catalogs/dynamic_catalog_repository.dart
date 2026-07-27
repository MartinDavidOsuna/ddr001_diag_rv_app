import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';

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
  factory BrandOption.fromJson(Map<String, dynamic> json) => BrandOption(
    localId: json['localId'] as String,
    remoteId: json['remoteId'] as String?,
    name: json['name'] as String,
    normalizedName: json['normalizedName'] as String,
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

class DynamicCatalogRepository extends ChangeNotifier {
  DynamicCatalogRepository({required this.client, required this.box});
  final ApiClient client;
  final Box<String> box;

  static String normalizeBrand(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'''[.,;:_/\\()[\]{}'"`´-]+'''), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

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
    final raw = box.get('brand:$localId') ?? box.get('diameter:$localId');
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
    final normalized = normalizeBrand(name);
    if (normalized.isEmpty) throw const FormatException('Nombre requerido.');
    final duplicate = brands(
      elementType,
    ).where((item) => item.normalizedName == normalized).firstOrNull;
    if (duplicate != null) return duplicate;
    final value = BrandOption(
      localId: const Uuid().v4(),
      name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
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

  Future<void> synchronizePending() async {
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
            'name': brand.name,
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
            name: brand.name,
            normalizedName: brand.normalizedName,
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

  Future<void> _putBrand(BrandOption value) => box.put(
    'brand:${value.localId}',
    jsonEncode({'kind': 'brand', 'value': value.toJson()}),
  );
  Future<void> _putDiameter(DiameterOption value) => box.put(
    'diameter:${value.localId}',
    jsonEncode({'kind': 'diameter', 'value': value.toJson()}),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
