import 'dart:convert';

import 'package:ddr001diag/app/theme/app_theme.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/hydrants/data/hydrant_api_models.dart';
import 'package:ddr001diag/features/hydrants/new_survey_page.dart';
import 'package:ddr001diag/features/map/map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy hydrant remains readable with safe global defaults', () {
    final cached = CachedHydrant.fromJson({
      'hydrantId': 'h1',
      'accountNumber': '001-A',
      'updatedAt': '2026-08-01T00:00:00Z',
    });
    expect(cached.rvStatus, 'available');
    expect(cached.availableForRv, isTrue);
    expect(cached.hasConflict, isFalse);
    expect(cached.currentRound, 1);
  });

  test('new projection survives cache serialization', () {
    final cached = CachedHydrant.fromApi({
      'hydrantId': 'h2',
      'accountNumber': '000-42',
      'rvStatus': 'conflict',
      'officialInspectionId': 'official',
      'lastStatusChangedAt': '2026-08-01T12:00:00Z',
      'reviewedByName': 'Técnico Uno',
      'reviewedByCrew': 'Brigada A',
      'hasConflict': true,
      'conflictCount': 2,
      'availableForRv': false,
      'currentRound': 1,
      'requiredPhotosVerified': true,
      'isActive': true,
    }, DateTime.utc(2026, 8, 1));
    final restored = CachedHydrant.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(cached.toJson())) as Map),
    );
    expect(restored.rvStatus, 'conflict');
    expect(restored.officialInspectionId, 'official');
    expect(restored.conflictCount, 2);
    expect(restored.lastStatusChangedAt, DateTime.utc(2026, 8, 1, 12));
  });

  test('normal selection hides reviewed but exact account can find it', () {
    final reviewed = hydrant(rvStatus: 'completed', availableForRv: false);
    expect(
      hydrantVisibleForNewRv(
        reviewed,
        normalizedQuery: '',
        hasLocalWork: false,
      ),
      isFalse,
    );
    expect(
      hydrantVisibleForNewRv(
        reviewed,
        normalizedQuery: '000-42',
        hasLocalWork: false,
      ),
      isTrue,
    );
  });

  test('local completed projection also requires an exact account search', () {
    final staleCatalog = hydrant(
      rvStatus: 'available',
      availableForRv: true,
      localStatus: InspectionStatus.completed,
    );
    expect(
      hydrantVisibleForNewRv(
        staleCatalog,
        normalizedQuery: '11',
        hasLocalWork: false,
      ),
      isFalse,
    );
    expect(
      hydrantVisibleForNewRv(
        staleCatalog,
        normalizedQuery: '000-42',
        hasLocalWork: false,
      ),
      isTrue,
    );
    expect(hydrantAvailableForNewRv(staleCatalog), isFalse);
  });

  test('map colors combine canonical and local state', () {
    expect(hydrantMarkerColor(hydrant()), AppColors.brightBlue);
    expect(
      hydrantMarkerColor(
        hydrant(
          rvStatus: 'completed',
          availableForRv: false,
          photosVerified: true,
        ),
      ),
      AppColors.green,
    );
    expect(
      hydrantMarkerColor(hydrant(rvStatus: 'conflict', availableForRv: false)),
      AppColors.red,
    );
    expect(
      hydrantMarkerColor(hydrant(isActive: false, availableForRv: false)),
      Colors.grey,
    );
    expect(
      hydrantMarkerColor(hydrant(localStatus: InspectionStatus.inProgress)),
      Colors.amber.shade700,
    );
    expect(
      hydrantMarkerColor(
        hydrant(
          rvStatus: 'conflict',
          availableForRv: false,
          localStatus: InspectionStatus.inProgress,
        ),
      ),
      AppColors.red,
    );
    expect(
      hydrantMarkerColor(
        hydrant(
          isActive: false,
          availableForRv: false,
          localStatus: InspectionStatus.inProgress,
        ),
      ),
      Colors.grey,
    );
  });
}

Hydrant hydrant({
  String rvStatus = 'available',
  bool availableForRv = true,
  bool photosVerified = false,
  bool isActive = true,
  InspectionStatus localStatus = InspectionStatus.pending,
}) => Hydrant(
  id: 'h',
  code: '000-42',
  locality: 'L',
  parcel: 'P',
  priority: PriorityLevel.medium,
  access: AccessType.both,
  syncStatus: SyncStatus.synced,
  f02a: InspectionSummary(
    type: InspectionType.f02A,
    status: localStatus,
    progress: 0,
  ),
  f02b: const InspectionSummary(
    type: InspectionType.f02B,
    status: InspectionStatus.notRequired,
    progress: 0,
  ),
  latitude: 1,
  longitude: 1,
  rvStatus: rvStatus,
  availableForRv: availableForRv,
  requiredPhotosVerified: photosVerified,
  isActive: isActive,
);
