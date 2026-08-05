import 'dart:io';
import 'package:ddr001diag/features/visual_reports/domain/visual_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses complete report into typed presentation models', () {
    final report = VisualReport.fromJson({
      'visualReportId': 'r',
      'accountNumber': '001-A',
      'versionNumber': 3,
      'rvRoundNumber': 1,
      'status': 'validated',
      'isValidated': true,
      'lastStatusChangedAt': '2026-07-31T18:35:00Z',
      'reviewer': {
        'userId': 'u',
        'displayName': 'Técnico Uno',
        'crewName': 'Brigada A',
      },
      'sections': [
        {
          'code': 'general',
          'title': 'General',
          'order': 1,
          'items': [
            {'label': 'Visible', 'displayValue': 'Sí'},
          ],
        },
      ],
      'photos': {
        'required': [
          {
            'photoId': 'p',
            'title': 'Frente',
            'thumbnailUrl': '/thumb',
            'viewerUrl': '/content',
            'integrityVerified': true,
          },
        ],
      },
      'location': {'latitude': 29.1, 'longitude': -110.9},
      'signal': {'isConnected': true},
      'conflict': {
        'hasConflict': true,
        'type': 'concurrent_edit',
        'message': 'preservado',
      },
    }, currentUserId: 'u');
    expect(report.accountNumber, '001-A');
    expect(report.sections.single.items.single.displayValue, 'Sí');
    expect(report.photos.required.single.integrityVerified, isTrue);
    expect(report.location?.altitude, 'No capturado');
    expect(report.signal?.connected, 'Sí');
    expect(report.conflict?.type, 'concurrent_edit');
    expect(report.isOwn, isTrue);
    expect(report.syncStatus, 'synchronized');
  });
  test('legacy missing values become No capturado', () {
    final report = VisualReport.fromJson({
      'visualReportId': 'r',
      'reviewer': {},
      'sections': [
        {
          'items': [
            {'label': 'Legacy'},
          ],
        },
      ],
    });
    expect(report.accountNumber, 'No capturado');
    expect(report.reviewer.displayName, 'No capturado');
    expect(report.sections.single.items.single.displayValue, 'No capturado');
  });
  test('viewer source contains no privacy or export actions', () {
    final source = File(
      'lib/features/visual_reports/presentation/rv_visual_report_page.dart',
    ).readAsStringSync();
    expect(source, contains('InteractiveViewer'));
    expect(source, contains('PageView'));
    expect(source, contains('Semantics'));
    expect(source, contains('Reintentar fotografía'));
    expect(source, contains('Versión actual'));
    expect(source, contains('Fotografías obligatorias'));
    expect(source, contains('Fotografías generales'));
    expect(source, contains("? 'Sincronizado'"));
    expect(source, isNot(contains('localidad')));
    expect(source, isNot(contains('municipio')));
    expect(source, isNot(contains('correo')));
    expect(source, isNot(contains('teléfono')));
    expect(source, isNot(contains('Compartir')));
    expect(source, isNot(contains('Descargar')));
  });
  test('photo downloads do not duplicate the API v1 prefix', () {
    final source = File(
      'lib/features/visual_reports/data/visual_report_repository.dart',
    ).readAsStringSync();
    expect(source, contains("trimmed.startsWith('/api/v1/')"));
    expect(source, contains("substring('/api/v1'.length)"));
    expect(source, contains('_apiRelativePath(path)'));
  });
  test('navigation opens reports for unavailable hydrants', () {
    final map = File('lib/features/map/map_page.dart').readAsStringSync();
    final search = File(
      'lib/features/hydrants/new_survey_page.dart',
    ).readAsStringSync();
    final history = File(
      'lib/features/hydrants/hydrant_pages.dart',
    ).readAsStringSync();
    expect(map, contains('/visual-report/'));
    expect(search, contains('/visual-report/'));
    expect(history, contains('/visual-report/'));
    expect(map, contains('if (hydrant.availableForRv)'));
  });
}
