import 'package:ddr001diag/core/formatters/person_name_formatter.dart';
import 'package:ddr001diag/features/catalogs/dynamic_catalog_repository.dart';
import 'package:ddr001diag/features/inspections/domain/parcel_valve_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catálogos tipificados', () {
    test('mantiene tipos independientes', () {
      expect(BrandElementType.parse('VALVE'), BrandElementType.valve);
      expect(BrandElementType.parse('SOLENOID'), BrandElementType.solenoid);
      expect(BrandElementType.valve, isNot(BrandElementType.solenoid));
    });

    test('una marca conserva su tipo al serializar', () {
      const option = BrandOption(
        localId: 'local-1',
        name: 'MARCA-PRUEBA',
        normalizedName: 'MARCA-PRUEBA',
        elementType: BrandElementType.filter,
        status: CatalogSyncStatus.pending,
      );
      expect(
        BrandOption.fromJson(option.toJson()).elementType,
        BrandElementType.filter,
      );
    });
  });

  group('configuración de válvulas parcelarias', () {
    test('mapea las cuatro configuraciones predeterminadas', () {
      expect(ParcelValveConfigurationType.one3.fixedCount, 1);
      expect(ParcelValveConfigurationType.two3.fixedCount, 2);
      expect(ParcelValveConfigurationType.three3.fixedDiameter, 3);
      expect(ParcelValveConfigurationType.three4.fixedDiameter, 4);
    });

    test('persiste información individual y válvulas retiradas', () {
      const configuration = ParcelValveConfiguration(
        type: ParcelValveConfigurationType.two3,
        valveCount: 2,
        valves: [
          ParcelValve(
            index: 1,
            valveBrand: {
              'localCatalogId': 'brand-1',
              'displayValue': 'Marca Uno',
              'elementType': 'VALVE',
            },
            diameter: {
              'localCatalogId': 'diameter-3',
              'displayValue': '3"',
              'nominalValue': 3.0,
              'unit': 'in',
            },
          ),
          ParcelValve(index: 2),
        ],
        retiredValves: [ParcelValve(index: 3)],
      );
      final restored = ParcelValveConfiguration.fromJson(
        configuration.toJson(),
      );
      expect(restored.valves, hasLength(2));
      expect(restored.valves.first.index, 1);
      expect(restored.retiredValves.single.index, 3);
    });
  });

  group('presentación de nombres', () {
    test('normaliza mayúsculas, espacios y nombres compuestos', () {
      expect(formatPersonName('  JUAN   CARLOS  '), 'Juan Carlos');
      expect(formatPersonName('oSuNa'), 'Osuna');
    });

    test('conserva acentos, guiones y apóstrofes', () {
      expect(formatPersonName('josé luis'), 'José Luis');
      expect(formatPersonName('ANA-MARÍA'), 'Ana-María');
      expect(formatPersonName("o'connor"), "O'Connor");
    });
  });
}
