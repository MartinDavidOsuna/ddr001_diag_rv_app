import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../media/inspection_photo.dart';
import '../media/media_sync_status.dart';
import '../../data/catalogs/damage_component_catalog.dart';
import '../network/cellular_network_diagnostic.dart';
import '../network/wifi_technical_assessment.dart';
import '../network/wifi_assessment_rules.dart';
import 'visual_inspection.dart';
import '../../features/visual_report/domain/visual_component_rules.dart';
import '../../features/visual_report/domain/visual_component_models.dart';

class InspectionValidationError {
  const InspectionValidationError(this.stepNumber, this.fieldKey, this.message);
  final int stepNumber;
  final String fieldKey, message;
}

class InspectionValidationResult {
  const InspectionValidationResult(this.errors);
  final List<InspectionValidationError> errors;
  bool get isValid => errors.isEmpty;
}

class VisualInspectionStepValidator {
  const VisualInspectionStepValidator({
    required this.photos,
    required this.damageDocuments,
  });
  final List<InspectionPhoto> photos;
  final Map<String, Map<String, dynamic>> damageDocuments;

  InspectionValidationResult validateStep(VisualInspection value, int step) =>
      switch (step) {
        1 => validateIdentification(value),
        2 => validateLocation(value),
        3 => validateAccess(value),
        4 => validateFlowMeter(value),
        5 => validatePublicComponents(value),
        6 => validatePrivateComponents(value),
        7 => validateEnergyCommunication(value),
        8 => validateDamage(value),
        9 => validatePhotosAndClose(value),
        _ => const InspectionValidationResult([]),
      };

  InspectionValidationResult validateAll(VisualInspection value) =>
      InspectionValidationResult([
        for (var step = 1; step <= 9; step++)
          ...validateStep(value, step).errors,
      ]);

  InspectionValidationResult validateIdentification(VisualInspection value) =>
      _result(1, {
        'matchesAssignment': value.identification.matchesAssignment == null
            ? 'Confirma si corresponde con el hidrante asignado.'
            : null,
        'identificationStatus': value.identification.status == null
            ? 'Selecciona el estado de identificación.'
            : null,
        'observedCode':
            value.identification.matchesAssignment == MatchAnswer.no &&
                (value.identification.observedCode ?? '').trim().isEmpty
            ? 'Captura el código observado o una justificación.'
            : null,
        'identificationJustification':
            value.identification.matchesAssignment == MatchAnswer.unknown &&
                value.identification.comments.trim().isEmpty
            ? 'Justifica por qué no puede identificarse.'
            : null,
        'identificationPhoto': !_hasValidCategory('identificación')
            ? 'Toma al menos una fotografía de identificación.'
            : null,
      });

  InspectionValidationResult validateLocation(VisualInspection value) {
    final technicalFailure =
        value.geoReference.pendingGeoreference &&
        (value.geoReference.technicalFailureReason ?? '').isNotEmpty;
    return _result(2, {
      'location': !value.geoReference.hasValidPosition && !technicalFailure
          ? 'Espera la captura automática o el diagnóstico técnico.'
          : null,
    });
  }

  InspectionValidationResult validateAccess(VisualInspection value) =>
      _result(3, {
        'accessType': value.access.accessType == null
            ? 'Selecciona el tipo de acceso.'
            : null,
        'roadType': value.access.roadType == null
            ? 'Selecciona el tipo de camino.'
            : null,
        'condition': value.access.condition == null
            ? 'Selecciona la condición del acceso.'
            : null,
        'risks': value.access.risks.isEmpty
            ? 'Selecciona los riesgos o confirma “Ninguno”.'
            : null,
      });

  InspectionValidationResult validateFlowMeter(VisualInspection value) =>
      _result(4, {
        'exists': value.flowMeter.exists == null
            ? 'Indica si existe medidor.'
            : null,
        if (value.flowMeter.exists == true)
          'condition': value.flowMeter.condition == null
              ? 'Indica la condición del medidor.'
              : null,
        if (value.flowMeter.exists == true)
          'operation': value.flowMeter.operation == null
              ? 'Indica su funcionamiento aparente.'
              : null,
      });

  InspectionValidationResult validatePressureValve(VisualInspection value) =>
      _result(5, {
        'exists': value.pressureValve.exists == null
            ? 'Indica si existe válvula reductora.'
            : null,
        if (value.pressureValve.exists == true)
          'quantity': value.pressureValve.quantity < 1
              ? 'Indica la cantidad de válvulas.'
              : null,
        if (value.pressureValve.exists == true)
          'condition': value.pressureValve.condition == null
              ? 'Indica la condición física.'
              : null,
        if (value.pressureValve.exists == true)
          'solenoid': value.pressureValve.solenoidExists == null
              ? 'Indica si existe solenoide.'
              : null,
        if (value.pressureValve.solenoidExists == true)
          'solenoidType': (value.pressureValve.solenoidType ?? '').isEmpty
              ? 'Indica el tipo de solenoide.'
              : null,
      });

  InspectionValidationResult validateVisualComponents(VisualInspection value) {
    if (value.hydrantConfiguration == null ||
        value.componentInspections.isEmpty) {
      return validatePressureValve(value);
    }
    final errors = <InspectionValidationError>[];
    for (final component in value.componentInspections) {
      final hasPhoto = photos.any(
        (photo) => photo.componentId == component.id && _counts(photo),
      );
      for (final issue in VisualComponentRules.validate(
        component,
        hasValidPhoto: hasPhoto,
      )) {
        errors.add(
          InspectionValidationError(
            5,
            'component:${component.id}:${issue.code}',
            issue.message,
          ),
        );
      }
    }
    return InspectionValidationResult(errors);
  }

  InspectionValidationResult validatePublicComponents(VisualInspection value) {
    final errors = <InspectionValidationError>[
      ...validateFlowMeter(value).errors.map(
        (error) => InspectionValidationError(5, error.fieldKey, error.message),
      ),
      if (!value.flowMeterComponentConfirmed)
        const InspectionValidationError(
          5,
          'flowMeterComponentConfirmation',
          'Confirma el resumen del medidor dentro de la red pública.',
        ),
      if (value.victaulicGroupInspection == null ||
          value.victaulicGroupInspection!.quantity < 1)
        const InspectionValidationError(
          5,
          'victaulicQuantity',
          'Indica la cantidad de juntas Victaulic.',
        ),
      if (value.victaulicGroupInspection != null &&
          value.victaulicGroupInspection!.material.trim().isEmpty)
        const InspectionValidationError(
          5,
          'victaulicMaterial',
          'Indica el material de las juntas Victaulic.',
        ),
      ..._validateComponents(
        value,
        step: 5,
        compartments: const {VisualCompartment.publicNetwork},
      ),
    ];
    return InspectionValidationResult(errors);
  }

  InspectionValidationResult validatePrivateComponents(VisualInspection value) {
    return InspectionValidationResult(
      _validateComponents(
        value,
        step: 6,
        compartments: const {
          VisualCompartment.privateNetwork,
          VisualCompartment.outlet,
        },
      ),
    );
  }

  List<InspectionValidationError> _validateComponents(
    VisualInspection value, {
    required int step,
    required Set<VisualCompartment> compartments,
  }) {
    if (value.hydrantConfiguration == null ||
        value.componentInspections.isEmpty) {
      return step == 5
          ? validatePressureValve(value).errors
              .map((error) => InspectionValidationError(
                    step,
                    error.fieldKey,
                    error.message,
                  ))
              .toList()
          : const [];
    }
    final errors = <InspectionValidationError>[];
    for (final component in value.componentInspections.where(
      (component) =>
          component.active && compartments.contains(component.compartment),
    )) {
      final hasPhoto = photos.any(
        (photo) => photo.componentId == component.id && _counts(photo),
      );
      for (final issue in VisualComponentRules.validate(
        component,
        hasValidPhoto: hasPhoto,
      )) {
        errors.add(InspectionValidationError(
          step,
          'component:${component.id}:${issue.code}',
          issue.message,
        ));
      }
    }
    return errors;
  }

  InspectionValidationResult validateEnergyCommunication(
    VisualInspection value,
  ) {
    final wifi = WifiTechnicalAssessment.fromJson(
      value.energyCommunication.wifiAssessment,
    );
    final wifiValidation = WifiAssessmentRules.validate(wifi);
    final cellular = value.energyCommunication.cellularDiagnostic.isEmpty
        ? null
        : CellularNetworkDiagnostic.fromJson(
            value.energyCommunication.cellularDiagnostic,
          );
    return _result(7, {
      'energy': value.energyCommunication.energyAvailabilityAnswer == null
          ? 'Indica si hay energía disponible.'
          : null,
      if (value.energyCommunication.energyAvailable == true)
        'sources': value.energyCommunication.sources.isEmpty
            ? 'Selecciona al menos una fuente de energía.'
            : null,
      if (value.energyCommunication.energyAvailable == true)
        'voltage': (value.energyCommunication.voltage ?? '').isEmpty
            ? 'Registra el voltaje observado.'
            : null,
      'cellularDiagnostic': cellular == null || cellular.isRunning
          ? 'Completa o cancela el diagnóstico de red GPRS.'
          : null,
      'wifiNearby': wifiValidation.errors[WifiAssessmentQuestion.nearby],
      'wifiConnection':
          wifiValidation.errors[WifiAssessmentQuestion.connectionPossible],
      'wifiSignal': wifiValidation.errors[WifiAssessmentQuestion.signal],
      'wifiInternet': wifiValidation.errors[WifiAssessmentQuestion.internet],
    });
  }

  InspectionValidationResult validateDamage(VisualInspection value) {
    final errors = <InspectionValidationError>[];
    final damagedComponents = value.damageAssessments.entries
        .where((entry) => entry.value['status'] == 'damaged')
        .map((entry) => entry.key)
        .toList();
    if (value.damageIds.isEmpty &&
        damagedComponents.isEmpty &&
        !value.noVisibleDamageConfirmed &&
        value.damageAssessments.length <
            DamageComponentCatalog.components.length) {
      errors.add(
        const InspectionValidationError(
          8,
          'noDamage',
          'Confirma “Sin daños visibles” o registra los daños encontrados.',
        ),
      );
    }
    if ((value.damageIds.isNotEmpty || damagedComponents.isNotEmpty) &&
        value.noVisibleDamageConfirmed) {
      errors.add(
        const InspectionValidationError(
          8,
          'damageConflict',
          'No puedes confirmar “Sin daños visibles” y registrar daños simultáneamente.',
        ),
      );
    }
    if (!value.noVisibleDamageConfirmed) {
      for (final component in DamageComponentCatalog.components) {
        if ((value.damageAssessments[component]?['status'] as String? ?? '')
            .isEmpty) {
          errors.add(
            InspectionValidationError(
              8,
              'damageAssessment:$component',
              'Evalúa el componente $component.',
            ),
          );
        }
      }
    }
    for (final component in damagedComponents) {
      if (!_hasValidCategory('daño:$component')) {
        errors.add(
          InspectionValidationError(
            8,
            'damageEvidence:$component',
            'El daño de $component requiere evidencia fotográfica.',
          ),
        );
      }
    }
    for (final id in value.damageIds) {
      final damage = damageDocuments[id] ?? const {};
      if ((damage['category'] as String? ?? '').isEmpty) {
        errors.add(
          const InspectionValidationError(
            8,
            'damageCategory',
            'Un daño no tiene categoría.',
          ),
        );
      }
      if ((damage['affectedComponent'] as String? ?? '').isEmpty) {
        errors.add(
          const InspectionValidationError(
            8,
            'damageComponent',
            'Un daño no tiene componente.',
          ),
        );
      }
      if ((damage['severity'] as String? ?? '').isEmpty) {
        errors.add(
          const InspectionValidationError(
            8,
            'damageSeverity',
            'Un daño no tiene severidad.',
          ),
        );
      }
      if ((damage['photoIds'] as List? ?? []).isEmpty) {
        errors.add(
          const InspectionValidationError(
            8,
            'damagePhoto',
            'Cada daño requiere al menos una fotografía.',
          ),
        );
      }
    }
    return InspectionValidationResult(errors);
  }

  InspectionValidationResult validatePhotosAndClose(VisualInspection value) =>
      _result(9, {
        for (final category in _requiredPhotoCategories(value))
          category: !_hasValidCategory(category)
              ? 'Falta la fotografía obligatoria de ${_label(category)}.'
              : null,
        'classification': value.result.classification == null
            ? 'Selecciona la clasificación final.'
            : null,
        'missingFile':
            photos.any((p) => !p.isDeleted && !File(p.localPath).existsSync())
            ? 'Existe una fotografía con archivo local faltante.'
            : null,
        'corruptPhoto':
            photos.any(
              (p) => !p.isDeleted && (p.fileSize <= 0 || p.sha256.isEmpty),
            )
            ? 'Existe una fotografía corrupta o sin integridad.'
            : null,
        'processing':
            photos.any(
              (p) => const {
                MediaSyncStatus.captured,
                MediaSyncStatus.validating,
                MediaSyncStatus.processing,
              }.contains(p.syncStatus),
            )
            ? 'Espera a que termine el procesamiento fotográfico.'
            : null,
      });

  List<String> _requiredPhotoCategories(VisualInspection value) => [
    'acceso',
    'panorámica',
    'vistaGeneral',
    'identificación',
    if (value.flowMeter.exists == true) 'medidor',
    if (value.pressureValve.exists == true) 'válvula',
    if (value.pressureValve.solenoidExists == true) 'solenoide',
    if (value.energyCommunication.energyAvailable == true) 'energía',
    if (value.energyCommunication.cellularDiagnostic.isNotEmpty) 'comunicación',
  ];

  bool _hasValidCategory(String category) =>
      photos.any((p) => p.category == category && _counts(p));
  bool _counts(InspectionPhoto p) =>
      !p.isDeleted &&
      File(p.localPath).existsSync() &&
      p.fileSize > 0 &&
      p.sha256.isNotEmpty &&
      const {
        MediaSyncStatus.storedLocal,
        MediaSyncStatus.pendingUpload,
        MediaSyncStatus.uploading,
        MediaSyncStatus.uploadedUnverified,
        MediaSyncStatus.verified,
      }.contains(p.syncStatus);
  InspectionValidationResult _result(int step, Map<String, String?> fields) =>
      InspectionValidationResult([
        for (final entry in fields.entries)
          if (entry.value != null)
            InspectionValidationError(step, entry.key, entry.value!),
      ]);
  String _label(String value) =>
      value == 'vistaGeneral' ? 'vista general' : value;

  static VisualInspectionStepValidator fromHive(VisualInspection inspection) {
    final photoBox = Hive.box<String>('inspection_photos_v1');
    final damageBox = Hive.box<String>('damage_records_v1');
    return VisualInspectionStepValidator(
      photos: [
        for (final id in inspection.photoIds)
          if (photoBox.get(id) case final String raw)
            InspectionPhoto.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            ),
      ],
      damageDocuments: {
        for (final id in inspection.damageIds)
          if (damageBox.get(id) case final String raw)
            id: Map<String, dynamic>.from(jsonDecode(raw) as Map),
      },
    );
  }
}
