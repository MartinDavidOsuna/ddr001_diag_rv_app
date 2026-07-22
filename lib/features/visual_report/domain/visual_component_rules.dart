import 'visual_component_models.dart';

class VisualComponentValidationIssue {
  const VisualComponentValidationIssue(
    this.code,
    this.message, {
    this.requiresPhoto = false,
  });
  final String code, message;
  final bool requiresPhoto;
}

abstract final class VisualComponentRules {
  static VisualComponentInspection suggestedDefaults(
    VisualComponentInspection value,
  ) {
    if (value.explicitlyConfirmed ||
        value.presenceAnswer != null ||
        value.visualCondition != null ||
        value.observedConditions.isNotEmpty) {
      return value;
    }
    return value.copyWith(
      presenceAnswer: PresenceAnswer.installed,
      visualCondition: VisualComponentCondition.good,
      observedConditions: const {ObservedCondition.noVisibleDamage},
      specificData: _specificDefaults(value),
      reviewStatus: ComponentReviewStatus.pending,
      suggestedDefaultsApplied: true,
      explicitlyConfirmed: false,
      clearReviewedAt: true,
      clearReviewedBy: true,
      updatedAt: value.updatedAt,
    );
  }

  static VisualComponentSpecificData _specificDefaults(
    VisualComponentInspection value,
  ) {
    final data = value.specificData.toJson();
    void favorable(Iterable<String> keys) {
      for (final key in keys) {
        data[key] ??= 'good';
      }
    }
    switch (value.componentType) {
      case VisualComponentType.serviceValve:
      case VisualComponentType.sectioningValve:
      case VisualComponentType.filterWashValve:
        favorable(const [
          'bodyCondition',
          'mechanismCondition',
          'fixingCondition',
          'accessibility',
        ]);
        break;
      case VisualComponentType.regulatingValve:
        favorable(const [
          'bodyCondition',
          'coverCondition',
          'connectionsCondition',
          'tubingCondition',
          'fixingCondition',
        ]);
        break;
      case VisualComponentType.pilotValve:
        favorable(const [
          'bodyCondition',
          'fixingCondition',
          'tubingCondition',
          'connectionsCondition',
        ]);
        break;
      case VisualComponentType.pressureGauge:
        data['faceLegible'] ??= true;
        data['glassIntact'] ??= true;
        data['needleVisible'] ??= true;
        favorable(const ['orientation', 'connectionsCondition']);
        break;
      case VisualComponentType.airValve:
        favorable(const [
          'bodyCondition',
          'coverCondition',
          'connectionsCondition',
          'dischargeCondition',
        ]);
        break;
      case VisualComponentType.venturi:
        data['directionArrowVisible'] ??= true;
        favorable(const [
          'bodyCondition',
          'connectionsCondition',
          'pressureTapsCondition',
        ]);
        break;
      case VisualComponentType.filter:
        favorable(const [
          'bodyCondition',
          'coverCondition',
          'mechanismCondition',
          'connectionsCondition',
          'maintenanceAccess',
        ]);
        break;
      case VisualComponentType.filterAssembly:
        data['apparentlyPresent'] ??= true;
        favorable(const ['connectionsCondition', 'fixingCondition']);
        break;
      case VisualComponentType.outletConnection:
        favorable(const [
          'bodyCondition',
          'protectionCondition',
          'connectionThreadCondition',
        ]);
        break;
      case VisualComponentType.solenoid:
        favorable(const [
          'bodyCondition',
          'fixingCondition',
          'connectionsCondition',
          'protectionCondition',
        ]);
        break;
      case VisualComponentType.victaulicGroup:
      case VisualComponentType.flowMeter:
      case VisualComponentType.pipe:
      case VisualComponentType.other:
        break;
    }
    return VisualComponentSpecificData.fromJson(data);
  }

  static VisualComponentInspection changePresence(
    VisualComponentInspection value,
    PresenceAnswer answer,
  ) {
    if (answer == PresenceAnswer.installed) {
      return value.copyWith(
        presenceAnswer: answer,
        reviewStatus: ComponentReviewStatus.inProgress,
        explicitlyConfirmed: false,
        clearReviewedAt: true,
        clearReviewedBy: true,
      );
    }
    return value.copyWith(
      presenceAnswer: answer,
      observedConditions: const {},
      reviewStatus: ComponentReviewStatus.inProgress,
      explicitlyConfirmed: false,
      clearVisualCondition: true,
      clearReviewedAt: true,
      clearReviewedBy: true,
    );
  }

  static VisualComponentInspection changeCondition(
    VisualComponentInspection value,
    VisualComponentCondition condition,
  ) {
    final finding = const {
      VisualComponentCondition.minorFinding,
      VisualComponentCondition.majorFinding,
      VisualComponentCondition.critical,
    }.contains(condition);
    final conditions = finding
        ? value.observedConditions
            .where((item) => item != ObservedCondition.noVisibleDamage)
            .toSet()
        : condition == VisualComponentCondition.good
            ? const {ObservedCondition.noVisibleDamage}
            : value.observedConditions;
    return value.copyWith(
      visualCondition: condition,
      observedConditions: conditions,
      reviewStatus: ComponentReviewStatus.inProgress,
      explicitlyConfirmed: false,
      clearReviewedAt: true,
      clearReviewedBy: true,
    );
  }

  static VisualComponentInspection confirm(
    VisualComponentInspection value, {
    required String actor,
    required DateTime timestamp,
  }) => value.copyWith(
    reviewStatus: value.hasFinding
        ? ComponentReviewStatus.needsAttention
        : ComponentReviewStatus.reviewed,
    reviewedBy: actor,
    reviewedAt: timestamp,
    explicitlyConfirmed: true,
    suggestedDefaultsApplied: value.suggestedDefaultsApplied,
    updatedAt: timestamp,
  );

  static List<VisualComponentValidationIssue> validate(
    VisualComponentInspection value, {
    required bool hasValidPhoto,
  }) {
    final issues = <VisualComponentValidationIssue>[];
    if (value.presenceAnswer == null) {
      issues.add(const VisualComponentValidationIssue(
        'presence',
        'Indica si el componente está instalado.',
      ));
    }
    if (value.presenceAnswer == PresenceAnswer.installed &&
        value.visualCondition == null) {
      issues.add(const VisualComponentValidationIssue(
        'condition',
        'Selecciona el estado visual.',
      ));
    }
    if (value.observedConditions.contains(ObservedCondition.noVisibleDamage) &&
        value.observedConditions.length > 1) {
      issues.add(const VisualComponentValidationIssue(
        'conditionConflict',
        'Sin daño visible no puede coexistir con daños.',
      ));
    }
    if (value.hasFinding && value.observedConditions.isEmpty) {
      issues.add(const VisualComponentValidationIssue(
        'observedCondition',
        'Selecciona al menos una condición observada para el hallazgo.',
      ));
    }
    final needsComment =
        value.presenceAnswer == PresenceAnswer.notInstalled ||
        value.presenceAnswer == PresenceAnswer.cannotConfirm ||
        const {
          VisualComponentCondition.majorFinding,
          VisualComponentCondition.critical,
          VisualComponentCondition.notVerifiable,
        }.contains(value.visualCondition) ||
        value.observedConditions.contains(ObservedCondition.other) ||
        value.configurationDifference;
    if (needsComment && value.comment.trim().isEmpty) {
      issues.add(const VisualComponentValidationIssue(
        'comment',
        'Captura un comentario para justificar la condición.',
      ));
    }
    if (value.observedConditions.contains(ObservedCondition.other) &&
        value.otherConditionDescription.trim().isEmpty) {
      issues.add(const VisualComponentValidationIssue(
        'otherDescription',
        'Describe la condición “Otro”.',
      ));
    }
    final needsPhoto =
        value.visualCondition == VisualComponentCondition.majorFinding ||
        value.visualCondition == VisualComponentCondition.critical ||
        (value.expected &&
            value.presenceAnswer == PresenceAnswer.notInstalled) ||
        value.configurationDifference ||
        value.componentType == VisualComponentType.other;
    if (needsPhoto && !hasValidPhoto) {
      issues.add(const VisualComponentValidationIssue(
        'photo',
        'Esta condición requiere evidencia fotográfica.',
        requiresPhoto: true,
      ));
    }
    if (value.componentType == VisualComponentType.pressureGauge &&
        value.presenceAnswer == PresenceAnswer.installed) {
      if (value.specificData.faceLegible == null) {
        issues.add(const VisualComponentValidationIssue(
          'faceLegible',
          'Indica si la carátula es legible.',
        ));
      }
      if (value.specificData.visibleRange == null ||
          value.specificData.visibleRange!.trim().isEmpty) {
        issues.add(const VisualComponentValidationIssue(
          'visibleRange',
          'Captura el rango visible o indica que no es identificable.',
        ));
      }
      if (value.specificData.visibleUnit == null ||
          value.specificData.visibleUnit!.trim().isEmpty) {
        issues.add(const VisualComponentValidationIssue(
          'visibleUnit',
          'Captura la unidad visible o indica que no es identificable.',
        ));
      }
    }
    if (value.componentType == VisualComponentType.filterAssembly &&
        value.presenceAnswer == PresenceAnswer.installed &&
        value.specificData.internalVisibility == null) {
      issues.add(const VisualComponentValidationIssue(
        'internalVisibility',
        'Indica si el conjunto es verificable visualmente.',
      ));
    }
    if (!value.explicitlyConfirmed) {
      issues.add(const VisualComponentValidationIssue(
        'explicitConfirmation',
        'Confirma explícitamente la revisión del componente.',
      ));
    }
    return issues;
  }

  static bool eligibleForQuickReview(
    VisualComponentInspection value,
    VisualComponentDefinition definition,
  ) =>
      definition.quickReviewEligible &&
      value.reviewStatus == ComponentReviewStatus.pending &&
      !value.explicitlyConfirmed &&
      value.presenceAnswer == null &&
      value.visualCondition == null &&
      value.observedConditions.isEmpty &&
      value.photoIds.isEmpty &&
      !value.configurationDifference &&
      value.componentType != VisualComponentType.other;

  static List<VisualComponentInspection> applyQuickReview(
    Iterable<VisualComponentInspection> values,
    Map<String, VisualComponentDefinition> definitions, {
    required String actor,
    required DateTime timestamp,
  }) => [
    for (final value in values)
      if (eligibleForQuickReview(
        value,
        definitions[value.componentDefinitionId]!,
      ))
        suggestedDefaults(value).copyWith(
          quickReviewApplied: true,
          explicitlyConfirmed: false,
          reviewStatus: ComponentReviewStatus.pending,
          clearReviewedAt: true,
          clearReviewedBy: true,
          updatedAt: timestamp,
        )
      else
        value,
  ];
}
