import 'dart:async';

import 'package:flutter/material.dart';

import '../../inspections/domain/rv_draft.dart';
import '../../inspections/presentation/rv_inspection_controller.dart';
import '../data/checklist_models.dart';

class DynamicChecklistRenderer extends StatefulWidget {
  const DynamicChecklistRenderer({required this.controller, super.key});
  final RvInspectionController controller;

  @override
  State<DynamicChecklistRenderer> createState() =>
      _DynamicChecklistRendererState();
}

class _DynamicChecklistRendererState extends State<DynamicChecklistRenderer> {
  int currentStep = 0;

  @override
  Widget build(BuildContext context) {
    final draft = widget.controller.draft!;
    final sections = draft.checklist.sections;
    if (sections.isEmpty) return const Text('El checklist no contiene pasos.');
    if (currentStep >= sections.length) currentStep = sections.length - 1;
    return Column(
      children: [
        LinearProgressIndicator(
          value: (currentStep + 1) / (sections.length + 1),
        ),
        const SizedBox(height: 8),
        Text(
          'Paso ${currentStep + 1} de ${sections.length + 1}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _Section(section: sections[currentStep], controller: widget.controller),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: currentStep == 0
                    ? null
                    : () => setState(() => currentStep--),
                child: const Text('Anterior'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: currentStep == sections.length - 1
                    ? null
                    : () => setState(() => currentStep++),
                child: const Text('Siguiente'),
              ),
            ),
          ],
        ),
        if (currentStep == sections.length - 1)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('El paso final es Resumen y envío.'),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section, required this.controller});
  final ChecklistSectionDefinition section;
  final RvInspectionController controller;

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
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          missing == 0 ? 'Sección completa' : '$missing respuestas pendientes',
        ),
        children: [
          for (final item in answerable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: _Question(
                section: section,
                item: item,
                controller: controller,
              ),
            ),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.section,
    required this.item,
    required this.controller,
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
        _field(answer, readOnly),
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

  Widget _field(RvAnswer? answer, bool readOnly) => switch (item.type) {
    'boolean' => SegmentedButton<bool>(
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
    'select' => DropdownButtonFormField<Object?>(
      initialValue: answer?.value,
      items: item.options
          .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
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
                  unawaited(controller.answer(section, item, selected: values));
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

extension _FirstOrNull<T> on Set<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
