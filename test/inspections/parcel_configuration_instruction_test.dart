import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/domain/parcel_valve_configuration.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Otro no exige una descripción de texto adicional', () {
    final now = DateTime.utc(2026, 8, 8);
    const section = ChecklistSectionDefinition(
      id: 'parcel-section',
      code: 'valvulas_parcelarias',
      title: 'Válvulas parcelarias',
      order: 8,
      items: [],
    );
    final checklist = DynamicChecklist(
      id: 'checklist',
      code: 'RV',
      version: 2,
      title: 'RV',
      etag: 'fixture',
      cachedAt: now,
      sections: const [section],
    );
    final draft = RvDraft(
      clientInspectionId: 'inspection',
      hydrantId: 'hydrant',
      accountNumber: '1001',
      fieldSessionId: 'session',
      checklistId: checklist.id,
      checklistVersion: checklist.version,
      checklistSnapshot: checklist.toJson(),
      createdAt: now,
      updatedAt: now,
      parcelValveConfiguration: const ParcelValveConfiguration(
        type: ParcelValveConfigurationType.other,
        valveCount: 1,
        valves: [
          ParcelValve(
            index: 1,
            valveBrand: {'localCatalogId': 'brand', 'displayValue': 'MARCA'},
            diameter: {
              'localCatalogId': 'diameter',
              'displayValue': '2"',
              'nominalValue': 2,
              'unit': 'in',
            },
          ),
        ],
      ),
    );

    final issues = const RvValidator().validate(draft).issues;
    expect(
      issues.where(
        (issue) => issue.code == 'parcel_custom_description_missing',
      ),
      isEmpty,
    );
  });
}
