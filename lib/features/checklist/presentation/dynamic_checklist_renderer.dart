import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';

import '../../inspections/domain/rv_draft.dart';
import '../../inspections/domain/parcel_valve_configuration.dart';
import '../../inspections/domain/filter_element_selection.dart';
import '../../inspections/presentation/rv_inspection_controller.dart';
import '../../inspections/presentation/rv_review_navigation.dart';
import '../../catalogs/dynamic_catalog_repository.dart';
import '../../catalogs/pressure_range_selector.dart';
import '../../catalogs/brand_selection.dart';
import '../data/checklist_models.dart';

class DynamicChecklistRenderer extends StatefulWidget {
  const DynamicChecklistRenderer({
    required this.controller,
    required this.stepOne,
    required this.stepTwo,
    required this.onExitRequested,
    this.onSummary,
    super.key,
  });
  final RvInspectionController controller;
  final Widget stepOne, stepTwo;
  final VoidCallback? onSummary;
  final Future<void> Function() onExitRequested;

  @override
  State<DynamicChecklistRenderer> createState() =>
      _DynamicChecklistRendererState();
}

class _DynamicChecklistRendererState extends State<DynamicChecklistRenderer> {
  final _headingKey = GlobalKey();
  final _targetKey = GlobalKey();
  bool _targetScheduled = false;
  bool _transitioning = false;
  int? _renderedStep;

  void _scheduleStepFocus(int step) {
    if (_renderedStep == step) return;
    _renderedStep = step;
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final heading = _headingKey.currentContext;
      if (heading == null) return;
      Scrollable.ensureVisible(
        heading,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0,
      );
      SemanticsService.sendAnnouncement(
        View.of(heading),
        'Paso ${step + 1}',
        Directionality.of(heading),
      );
    });
  }

  Future<void> _previous() async {
    if (_transitioning) return;
    final current = widget.controller.draft!;
    if (current.activeFormStep == 0) {
      await widget.onExitRequested();
      return;
    }
    _transitioning = true;
    try {
      await widget.controller.goToPreviousStep();
    } finally {
      _transitioning = false;
    }
  }

  Future<void> _next() async {
    if (_transitioning) return;
    _transitioning = true;
    try {
      final openSummary = await widget.controller.goToNextStep();
      if (openSummary && mounted) widget.onSummary?.call();
    } finally {
      _transitioning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.controller.draft!;
    final sections = draft.checklist.sections;
    if (sections.isEmpty) return const Text('El checklist no contiene pasos.');
    final currentStep = draft.activeFormStep.clamp(0, sections.length - 1);
    _scheduleStepFocus(currentStep);
    if ((draft.navigationQuestionId != null ||
            draft.navigationFieldId != null) &&
        !_targetScheduled) {
      _targetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final target = _targetKey.currentContext;
        if (target != null) {
          await Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: .15,
          );
        }
        await widget.controller.clearNavigationTarget();
        _targetScheduled = false;
      });
    }
    return RvSwipeNavigationDetector(
      onNext: _next,
      onPrevious: _previous,
      child: RvStepLayout(
        headingKey: _headingKey,
        currentStep: currentStep,
        totalFormSteps: sections.length,
        onPrevious: _previous,
        onNext: _next,
        content: KeyedSubtree(
          key: ValueKey('rv-step-${currentStep + 1}'),
          child: switch (currentStep) {
            0 => widget.stepOne,
            1 => Column(
              children: [
                _Section(
                  section: sections[currentStep],
                  controller: widget.controller,
                  collapsible: false,
                ),
                widget.stepTwo,
              ],
            ),
            _ =>
              sections[currentStep].code == 'valvulas_parcelarias'
                  ? _ParcelValveSection(
                      controller: widget.controller,
                      targetSubItemId: draft.navigationSubItemId,
                      targetFieldId: draft.navigationFieldId,
                      targetKey: _targetKey,
                    )
                  : _Section(
                      section: sections[currentStep],
                      controller: widget.controller,
                      collapsible: false,
                      targetQuestionId: draft.navigationQuestionId,
                      targetKey: _targetKey,
                    ),
          },
        ),
      ),
    );
  }
}

class _ParcelValveSection extends StatelessWidget {
  const _ParcelValveSection({
    required this.controller,
    this.targetSubItemId,
    this.targetFieldId,
    this.targetKey,
  });
  final RvInspectionController controller;
  final String? targetSubItemId, targetFieldId;
  final GlobalKey? targetKey;

  Map<String, dynamic> _brand(BrandOption option) => {
    'mode': 'readable',
    'brandId': option.remoteId,
    'catalogId': option.remoteId,
    'localCatalogId': option.localId,
    'displayValue': option.name,
    'elementType': option.elementType?.wireName,
    'source': option.userCreated ? 'user_created' : 'system',
    'isPendingSync': option.remoteId == null,
  };

  Map<String, dynamic> _diameter(DiameterOption option) => {
    'catalogId': option.remoteId,
    'localCatalogId': option.localId,
    'numericValue': option.value,
    'nominalValue': option.value,
    'unit': option.unit,
    'displayValue': option.display,
    'isPendingSync': option.remoteId == null,
  };

  RvAnswer? _answer(Map<String, dynamic>? value) => value == null
      ? null
      : RvAnswer(
          questionId: 'parcel-valve',
          sectionId: 'parcel-valves',
          answerType: 'catalog',
          value: value,
          updatedAt: DateTime.now().toUtc(),
        );

  Future<void> _select(
    BuildContext context,
    ParcelValveConfigurationType type,
  ) async {
    final old = controller.draft!.parcelValveConfiguration;
    final count = type.fixedCount ?? old?.valveCount ?? 1;
    if (old != null && count < old.valveCount) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cambiar configuración'),
          content: Text(
            'La nueva configuración contiene menos válvulas.\n\n'
            'La información de las válvulas ${count + 1} a '
            '${old.valveCount} dejará de formar parte de la revisión.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    final kept = old?.valves.take(count).toList() ?? <ParcelValve>[];
    final retired = [
      ...old?.retiredValves ?? const <ParcelValve>[],
      ...?old?.valves.skip(count),
    ];
    while (kept.length < count) {
      kept.add(ParcelValve(index: kept.length + 1));
    }
    if (type.fixedDiameter != null) {
      for (var index = 0; index < kept.length; index++) {
        final value = type.fixedDiameter!.toDouble();
        kept[index] = kept[index].copyWith(
          diameter: {
            'catalogId': type.fixedDiameter == 3
                ? '30000000-0000-4000-8000-000000000003'
                : '40000000-0000-4000-8000-000000000004',
            'localCatalogId': type.fixedDiameter == 3
                ? '30000000-0000-4000-8000-000000000003'
                : '40000000-0000-4000-8000-000000000004',
            'nominalValue': value,
            'numericValue': value,
            'unit': 'in',
            'displayValue': '${type.fixedDiameter}"',
            'source': 'system',
            'isPendingSync': false,
          },
        );
      }
    }
    await controller.saveParcelValveConfiguration(
      ParcelValveConfiguration(
        type: type,
        valveCount: count,
        valves: kept,
        retiredValves: retired,
        customDescription: type == ParcelValveConfigurationType.other
            ? old?.customDescription
            : null,
      ),
    );
  }

  Future<void> _updateValve(
    ParcelValveConfiguration config,
    ParcelValve valve,
  ) => controller.saveParcelValveConfiguration(
    config.copyWith(
      valves: [
        for (final item in config.valves)
          if (item.index == valve.index) valve else item,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    final config = draft.parcelValveConfiguration;
    final catalogs = controller.catalogs;
    if (catalogs == null) {
      return const Text('Los catálogos no están disponibles.');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Válvulas parcelarias',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ParcelValveConfigurationType.values
                  .map(
                    (type) => ChoiceChip(
                      key:
                          targetFieldId == 'configuration' &&
                              type == ParcelValveConfigurationType.one3
                          ? targetKey
                          : ValueKey('parcel-config-${type.wireName}'),
                      label: Text(type.label),
                      selected: config?.type == type,
                      onSelected: draft.isReadOnly
                          ? null
                          : (_) => _select(context, type),
                    ),
                  )
                  .toList(),
            ),
            if (config?.type == ParcelValveConfigurationType.other) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: targetFieldId == 'customDescription'
                    ? targetKey
                    : const ValueKey('parcel-custom-description'),
                initialValue: config?.customDescription,
                decoration: const InputDecoration(
                  labelText: 'Especifique la configuración de válvulas',
                ),
                onChanged: (value) => unawaited(
                  controller.saveParcelValveConfiguration(
                    config!.copyWith(customDescription: value),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: targetFieldId == 'valveCount' ? targetKey : null,
                initialValue: config?.valveCount,
                decoration: const InputDecoration(
                  labelText: 'Cantidad de válvulas',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                ],
                onChanged: draft.isReadOnly
                    ? null
                    : (count) {
                        if (count == null || count == config!.valveCount) {
                          return;
                        }
                        unawaited(_setCustomCount(context, config, count));
                      },
              ),
            ],
            for (final valve in config?.valves ?? const <ParcelValve>[]) ...[
              const SizedBox(height: 16),
              _ParcelValveCard(
                key: ValueKey('parcel-valve-${valve.index}'),
                valve: valve,
                fixedDiameter: config!.type.fixedDiameter,
                catalogs: catalogs,
                readOnly: draft.isReadOnly,
                answer: _answer,
                brandValue: _brand,
                diameterValue: _diameter,
                onChanged: (value) => _updateValve(config, value),
                targetFieldId: targetSubItemId == 'valve-${valve.index}'
                    ? targetFieldId
                    : null,
                targetKey: targetKey,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setCustomCount(
    BuildContext context,
    ParcelValveConfiguration config,
    int count,
  ) async {
    if (count < config.valveCount) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            'La nueva configuración contiene menos válvulas. '
            'La información excedente dejará de formar parte de la revisión.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    final valves = config.valves.take(count).toList();
    while (valves.length < count) {
      valves.add(ParcelValve(index: valves.length + 1));
    }
    await controller.saveParcelValveConfiguration(
      config.copyWith(
        valveCount: count,
        valves: valves,
        retiredValves: [...config.retiredValves, ...config.valves.skip(count)],
      ),
    );
  }
}

class _ParcelValveCard extends StatelessWidget {
  const _ParcelValveCard({
    required this.valve,
    required this.fixedDiameter,
    required this.catalogs,
    required this.readOnly,
    required this.answer,
    required this.brandValue,
    required this.diameterValue,
    required this.onChanged,
    this.targetFieldId,
    this.targetKey,
    super.key,
  });
  final ParcelValve valve;
  final int? fixedDiameter;
  final DynamicCatalogRepository catalogs;
  final bool readOnly;
  final RvAnswer? Function(Map<String, dynamic>?) answer;
  final Map<String, dynamic> Function(BrandOption) brandValue;
  final Map<String, dynamic> Function(DiameterOption) diameterValue;
  final ValueChanged<ParcelValve> onChanged;
  final String? targetFieldId;
  final GlobalKey? targetKey;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('parcel-valve-${valve.index}-container'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Válvula ${valve.index}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text('Marca de la válvula *'),
        _BrandField(
          key: targetFieldId == 'valveBrand'
              ? targetKey
              : ValueKey('parcel-valve-${valve.index}-valveBrand'),
          repository: catalogs,
          elementType: BrandElementType.valve,
          answer: answer(valve.valveBrand),
          readOnly: readOnly,
          onSelected: (value) =>
              onChanged(valve.copyWith(valveBrand: brandValue(value))),
          onIllegible: (reason) =>
              onChanged(valve.copyWith(valveBrand: illegibleBrandMap(reason))),
        ),
        const SizedBox(height: 12),
        if (fixedDiameter != null)
          Text('Diámetro: $fixedDiameter" (derivado)')
        else ...[
          const Text('Diámetro *'),
          _DiameterField(
            key: targetFieldId == 'diameter'
                ? targetKey
                : ValueKey('parcel-valve-${valve.index}-diameter'),
            repository: catalogs,
            answer: answer(valve.diameter),
            readOnly: readOnly,
            onSelected: (value) =>
                onChanged(valve.copyWith(diameter: diameterValue(value))),
          ),
        ],
        _ComponentField(
          key: targetFieldId == 'solenoidBrand' ? targetKey : null,
          label: 'Solenoide',
          hasValue: valve.hasSolenoid,
          brand: valve.solenoidBrand,
          type: BrandElementType.solenoid,
          catalogs: catalogs,
          readOnly: readOnly,
          answer: answer,
          brandValue: brandValue,
          onPresence: (value) => onChanged(valve.copyWith(hasSolenoid: value)),
          onBrand: (value) =>
              onChanged(valve.copyWith(solenoidBrand: brandValue(value))),
          onIllegible: (reason) => onChanged(
            valve.copyWith(solenoidBrand: illegibleBrandMap(reason)),
          ),
        ),
        _ComponentField(
          key: targetFieldId == 'pilotBrand' ? targetKey : null,
          label: 'Piloto',
          hasValue: valve.hasPilot,
          brand: valve.pilotBrand,
          type: BrandElementType.pilot,
          catalogs: catalogs,
          readOnly: readOnly,
          answer: answer,
          brandValue: brandValue,
          onPresence: (value) => onChanged(valve.copyWith(hasPilot: value)),
          onBrand: (value) =>
              onChanged(valve.copyWith(pilotBrand: brandValue(value))),
          onIllegible: (reason) =>
              onChanged(valve.copyWith(pilotBrand: illegibleBrandMap(reason))),
        ),
        if (valve.hasPilot) ...[
          const SizedBox(height: 8),
          Semantics(
            label: '¿El piloto está conectado?',
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Sí')),
                ButtonSegment(value: false, label: Text('No')),
              ],
              selected: valve.pilotConnected == null
                  ? const <bool>{}
                  : {valve.pilotConnected!},
              emptySelectionAllowed: true,
              onSelectionChanged: readOnly
                  ? null
                  : (selection) => onChanged(
                      valve.copyWith(pilotConnected: selection.first),
                    ),
            ),
          ),
        ],
        _ComponentField(
          key: targetFieldId == 'pressureGaugeBrand' ? targetKey : null,
          label: 'Manómetro',
          hasValue: valve.hasPressureGauge,
          brand: valve.pressureGaugeBrand,
          type: BrandElementType.pressureGauge,
          catalogs: catalogs,
          readOnly: readOnly,
          answer: answer,
          brandValue: brandValue,
          onPresence: (value) =>
              onChanged(valve.copyWith(hasPressureGauge: value)),
          onBrand: (value) =>
              onChanged(valve.copyWith(pressureGaugeBrand: brandValue(value))),
          onIllegible: (reason) => onChanged(
            valve.copyWith(pressureGaugeBrand: illegibleBrandMap(reason)),
          ),
        ),
      ],
    ),
  );
}

class _ComponentField extends StatelessWidget {
  const _ComponentField({
    required this.label,
    required this.hasValue,
    required this.brand,
    required this.type,
    required this.catalogs,
    required this.readOnly,
    required this.answer,
    required this.brandValue,
    required this.onPresence,
    required this.onBrand,
    required this.onIllegible,
    super.key,
  });
  final String label;
  final bool hasValue, readOnly;
  final Map<String, dynamic>? brand;
  final BrandElementType type;
  final DynamicCatalogRepository catalogs;
  final RvAnswer? Function(Map<String, dynamic>?) answer;
  final Map<String, dynamic> Function(BrandOption) brandValue;
  final ValueChanged<bool> onPresence;
  final ValueChanged<BrandOption> onBrand;
  final ValueChanged<String> onIllegible;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label *'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Sí')),
            ButtonSegment(value: false, label: Text('No')),
          ],
          selected: {hasValue},
          onSelectionChanged: readOnly
              ? null
              : (value) => onPresence(value.first),
        ),
        if (hasValue) ...[
          const SizedBox(height: 8),
          Text('Marca del ${label.toLowerCase()} *'),
          _BrandField(
            repository: catalogs,
            elementType: type,
            answer: answer(brand),
            readOnly: readOnly,
            onSelected: onBrand,
            onIllegible: onIllegible,
          ),
        ],
      ],
    ),
  );
}

class RvStepLayout extends StatelessWidget {
  const RvStepLayout({
    required this.currentStep,
    required this.totalFormSteps,
    required this.content,
    required this.onPrevious,
    required this.onNext,
    this.headingKey,
    super.key,
  });
  final int currentStep, totalFormSteps;
  final Widget content;
  final VoidCallback? onPrevious, onNext;
  final Key? headingKey;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      LinearProgressIndicator(value: (currentStep + 1) / (totalFormSteps + 1)),
      const SizedBox(height: 8),
      Text(
        'Paso ${currentStep + 1} de ${totalFormSteps + 1}',
        key: headingKey,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      content,
      const SizedBox(height: 24),
      Row(
        key: const ValueKey('step-navigation'),
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onPrevious,
              child: const Text('Anterior'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: onNext,
              child: const Text('Siguiente'),
            ),
          ),
        ],
      ),
      if (currentStep == totalFormSteps - 1)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('El paso final es Resumen y envío.'),
        ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.section,
    required this.controller,
    this.collapsible = true,
    this.targetQuestionId,
    this.targetKey,
  });
  final ChecklistSectionDefinition section;
  final RvInspectionController controller;
  final bool collapsible;
  final String? targetQuestionId;
  final GlobalKey? targetKey;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    final visible = section.items
        .where(
          (item) => controller.validator.isVisible(
            item,
            draft.checklist,
            draft.answers,
          ),
        )
        .toList();
    final answerable = visible
        .where(
          (item) => !const {
            'photo',
            'coordinates',
            'signal',
            'readonly',
          }.contains(item.type),
        )
        .toList();
    if (answerable.isEmpty) return const SizedBox.shrink();
    final missing = answerable
        .where((item) => item.required && !draft.answers.containsKey(item.id))
        .length;
    final questions = [
      for (final item in answerable)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: _Question(
            key: item.id == targetQuestionId ? targetKey : null,
            section: section,
            item: item,
            controller: controller,
          ),
        ),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: collapsible
          ? ExpansionTile(
              initiallyExpanded: true,
              title: Text(
                section.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                missing == 0
                    ? 'Sección completa'
                    : '$missing respuestas pendientes',
              ),
              children: questions,
            )
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      section.title,
                      key: const ValueKey('step-2-fixed-title'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      missing == 0
                          ? 'Sección completa'
                          : '$missing respuestas pendientes',
                    ),
                  ),
                  ...questions,
                ],
              ),
            ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.section,
    required this.item,
    required this.controller,
    super.key,
  });
  final ChecklistSectionDefinition section;
  final ChecklistItemDefinition item;
  final RvInspectionController controller;

  @override
  Widget build(BuildContext context) {
    final answer = controller.draft!.answers[item.id];
    final readOnly = controller.draft!.isReadOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.label}${item.required ? ' *' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (item.helpText != null)
          Text(item.helpText!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _field(context, answer, readOnly),
        if (!item.required)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: answer?.notApplicable ?? false,
            onChanged: readOnly
                ? null
                : (value) => unawaited(
                    controller.answer(
                      section,
                      item,
                      value: answer?.value,
                      selected: answer?.selectedOptions ?? const [],
                      notApplicable: value ?? false,
                      comment: answer?.comment ?? '',
                    ),
                  ),
            title: const Text('No aplica'),
          ),
      ],
    );
  }

  Widget _field(BuildContext context, RvAnswer? answer, bool readOnly) {
    final catalogs = controller.catalogs;
    if (item.code == 'filter_element') {
      final selection = answer?.value == null
          ? null
          : FilterElementSelection.fromValue(answer!.value);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<FilterElementState>(
            segments: const [
              ButtonSegment(
                value: FilterElementState.present,
                label: Text('Sí'),
              ),
              ButtonSegment(
                value: FilterElementState.absent,
                label: Text('No'),
              ),
              ButtonSegment(
                value: FilterElementState.undetermined,
                label: Text('Indefinido'),
              ),
            ],
            selected: selection == null
                ? <FilterElementState>{}
                : {selection.state},
            emptySelectionAllowed: true,
            onSelectionChanged: readOnly
                ? null
                : (states) => unawaited(
                    controller.answer(
                      section,
                      item,
                      value: FilterElementSelection(states.first).toJson(),
                    ),
                  ),
          ),
          if (selection?.state == FilterElementState.undetermined)
            TextFormField(
              initialValue: selection?.undefinedReason,
              enabled: !readOnly,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Explica por qué no puede determinarse *',
                helperText: 'Mínimo 10 caracteres',
              ),
              validator: (value) => (value?.trim().length ?? 0) < 10
                  ? 'Escribe al menos 10 caracteres.'
                  : null,
              onChanged: (reason) => unawaited(
                controller.answer(
                  section,
                  item,
                  value: FilterElementSelection(
                    FilterElementState.undetermined,
                    undefinedReason: reason,
                  ).toJson(),
                ),
              ),
            ),
        ],
      );
    }
    if (catalogs != null && item.code.contains('brand')) {
      return _BrandField(
        repository: catalogs,
        elementType: _brandElementType(item.code),
        answer: answer,
        readOnly: readOnly,
        onSelected: (value) => controller.answer(
          section,
          item,
          value: {
            'mode': 'readable',
            'brandId': value.remoteId,
            'catalogId': value.remoteId,
            'localCatalogId': value.localId,
            'displayValue': value.name,
            'legacyText': answer?.value is String ? answer?.value : null,
            'elementType': value.elementType?.wireName,
            'source': value.userCreated ? 'user_created' : 'system',
            'isPendingSync': value.status != CatalogSyncStatus.synced,
            'userCreated': value.userCreated,
          },
        ),
        onIllegible: (reason) =>
            controller.answer(section, item, value: illegibleBrandMap(reason)),
        onEvidence: () => controller.addPhoto(
          'brand_illegible:${item.id}',
          ImageSource.camera,
        ),
      );
    }
    if (catalogs != null && item.code.contains('diameter')) {
      return _DiameterField(
        repository: catalogs,
        answer: answer,
        readOnly: readOnly,
        onSelected: (value) => controller.answer(
          section,
          item,
          value: {
            'catalogId': value.remoteId,
            'localCatalogId': value.localId,
            'displayValue': value.display,
            'legacyText': answer?.value is num || answer?.value is String
                ? '${answer?.value}'
                : null,
            'nominalValue': value.value,
            'unit': value.unit,
            'userCreated': value.userCreated,
            'isPendingSync': value.status != CatalogSyncStatus.synced,
          },
        ),
      );
    }
    const pressureRangeCodes = {
      'sustaining_gauge_range',
      'regulating_gauge_range',
      'filter_gauge_before_range',
      'filter_gauge_after_range',
      'parcel_gauge_range',
    };
    if (catalogs != null && pressureRangeCodes.contains(item.code)) {
      return PressureRangeSelector(
        value: answer?.value is Map
            ? Map<String, dynamic>.from(answer!.value! as Map)
            : null,
        enabled: !readOnly,
        onChanged: (range) =>
            unawaited(controller.answer(section, item, value: range)),
      );
    }
    return switch (item.type) {
      'boolean' => SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(72, 48)),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
          ),
          segments: const [
            ButtonSegment(value: true, label: Text('Sí')),
            ButtonSegment(value: false, label: Text('No')),
          ],
          selected: answer?.value is bool ? {answer!.value! as bool} : <bool>{},
          emptySelectionAllowed: true,
          onSelectionChanged: readOnly
              ? null
              : (values) => unawaited(
                  controller.answer(section, item, value: values.firstOrNull),
                ),
        ),
      ),
      'select' => DropdownButtonFormField<Object?>(
        initialValue: answer?.value,
        items: item.options
            .map(
              (value) => DropdownMenuItem(value: value, child: Text('$value')),
            )
            .toList(),
        onChanged: readOnly
            ? null
            : (value) =>
                  unawaited(controller.answer(section, item, value: value)),
      ),
      'multiselect' => Wrap(
        spacing: 8,
        children: item.options.map((option) {
          final selected = answer?.selectedOptions.contains(option) ?? false;
          return FilterChip(
            label: Text('$option'),
            selected: selected,
            onSelected: readOnly
                ? null
                : (enabled) {
                    final values = [...answer?.selectedOptions ?? const []];
                    enabled ? values.add(option) : values.remove(option);
                    unawaited(
                      controller.answer(section, item, selected: values),
                    );
                  },
          );
        }).toList(),
      ),
      'integer' || 'decimal' => TextFormField(
        initialValue: answer?.value?.toString(),
        enabled: !readOnly,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        onChanged: (value) {
          final parsed = item.type == 'integer'
              ? int.tryParse(value)
              : double.tryParse(value);
          unawaited(controller.answer(section, item, value: parsed));
        },
      ),
      'date' => TextFormField(
        initialValue: answer?.value?.toString(),
        enabled: !readOnly,
        decoration: const InputDecoration(hintText: 'AAAA-MM-DD'),
        onChanged: (value) =>
            unawaited(controller.answer(section, item, value: value)),
      ),
      _ => TextFormField(
        initialValue: answer?.value?.toString(),
        enabled: !readOnly,
        maxLines: 3,
        onChanged: (value) =>
            unawaited(controller.answer(section, item, value: value)),
      ),
    };
  }

  BrandElementType _brandElementType(String code) {
    if (code.contains('flow_meter')) return BrandElementType.flowMeter;
    if (code.contains('filter') && !code.contains('drain_brand')) {
      return BrandElementType.filter;
    }
    if (code.contains('solenoid')) return BrandElementType.solenoid;
    if (code.contains('pilot')) return BrandElementType.pilot;
    if (code.contains('reg_') || code.contains('pilot')) {
      return BrandElementType.regulatingValve;
    }
    return BrandElementType.valve;
  }
}

class _BrandField extends StatelessWidget {
  const _BrandField({
    required this.repository,
    required this.elementType,
    required this.answer,
    required this.readOnly,
    required this.onSelected,
    this.onIllegible,
    this.onEvidence,
    super.key,
  });
  final DynamicCatalogRepository repository;
  final BrandElementType elementType;
  final RvAnswer? answer;
  final bool readOnly;
  final ValueChanged<BrandOption> onSelected;
  final ValueChanged<String>? onIllegible;
  final Future<void> Function()? onEvidence;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      final options = repository.brands(elementType);
      final selected = answer?.value is Map
          ? (answer!.value as Map)['localCatalogId']?.toString()
          : null;
      final raw = answer?.value is Map
          ? Map<String, dynamic>.from(answer!.value! as Map)
          : const <String, dynamic>{};
      final illegible = raw['mode'] == 'illegible';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoiceChip(
            avatar: const Icon(Icons.visibility_off_outlined),
            label: const Text('Ilegible · condición especial'),
            selected: illegible,
            onSelected: readOnly || onIllegible == null
                ? null
                : (_) => onIllegible!(raw['reason']?.toString() ?? ''),
          ),
          if (illegible) ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: raw['reason']?.toString(),
              enabled: !readOnly,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Explica por qué la marca es ilegible *',
                helperText: 'Mínimo 10 caracteres',
              ),
              validator: (value) => (value?.trim().length ?? 0) < 10
                  ? 'Escribe al menos 10 caracteres.'
                  : null,
              onChanged: onIllegible,
            ),
            Text(
              raw['evidencePhotoId'] == null
                  ? 'Evidencia: No agregada (opcional)'
                  : 'Evidencia: 1 fotografía',
            ),
            if (!readOnly && onEvidence != null)
              OutlinedButton.icon(
                onPressed: onEvidence,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Agregar fotografía de evidencia'),
              ),
          ],
          const SizedBox(height: 8),
          if (options.length < 6)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options
                  .map(
                    (option) => ChoiceChip(
                      label: Text(option.name),
                      selected: selected == option.localId,
                      onSelected: readOnly ? null : (_) => onSelected(option),
                    ),
                  )
                  .toList(),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Buscar marca'),
              items: options
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.localId,
                      child: Text(option.name),
                    ),
                  )
                  .toList(),
              onChanged: readOnly
                  ? null
                  : (id) => onSelected(
                      options.firstWhere((option) => option.localId == id),
                    ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: readOnly
                ? null
                : () async {
                    final value = await _newBrand(context, elementType);
                    if (value != null) onSelected(value);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Registrar otra marca'),
          ),
        ],
      );
    },
  );

  Future<BrandOption?> _newBrand(
    BuildContext context,
    BrandElementType elementType,
  ) async {
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar otra marca'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipo de componente: ${elementType.label}'),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre de la marca',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar marca'),
          ),
        ],
      ),
    );
    if (accepted != true) return null;
    try {
      return await repository.createBrand(name.text, elementType);
    } on FormatException {
      return null;
    }
  }
}

class _DiameterField extends StatelessWidget {
  const _DiameterField({
    required this.repository,
    required this.answer,
    required this.readOnly,
    required this.onSelected,
    super.key,
  });
  final DynamicCatalogRepository repository;
  final RvAnswer? answer;
  final bool readOnly;
  final ValueChanged<DiameterOption> onSelected;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      final options = repository.diameters;
      final selected = answer?.value is Map
          ? (answer!.value as Map)['localCatalogId']?.toString()
          : null;
      final selector = options.length < 6
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options
                  .map(
                    (option) => ChoiceChip(
                      label: Text(option.display),
                      selected: selected == option.localId,
                      onSelected: readOnly ? null : (_) => onSelected(option),
                    ),
                  )
                  .toList(),
            )
          : DropdownButtonFormField<String>(
              initialValue: selected,
              items: options
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.localId,
                      child: Text(option.display),
                    ),
                  )
                  .toList(),
              onChanged: readOnly
                  ? null
                  : (id) => onSelected(
                      options.firstWhere((option) => option.localId == id),
                    ),
            );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          selector,
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: readOnly
                ? null
                : () async {
                    final option = await _newDiameter(context);
                    if (option != null) onSelected(option);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Registrar otro diámetro'),
          ),
        ],
      );
    },
  );

  Future<DiameterOption?> _newDiameter(BuildContext context) async {
    final value = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar otro diámetro'),
        content: TextField(
          controller: value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Diámetro nominal',
            suffixText: 'pulgadas',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar diámetro'),
          ),
        ],
      ),
    );
    if (accepted != true) return null;
    final parsed = double.tryParse(value.text.replaceAll(',', '.'));
    if (parsed == null) return null;
    try {
      return await repository.createDiameter(parsed);
    } on FormatException {
      return null;
    }
  }
}

extension _FirstOrNull<T> on Set<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
