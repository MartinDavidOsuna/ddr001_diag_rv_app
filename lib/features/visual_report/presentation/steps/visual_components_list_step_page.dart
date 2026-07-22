import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/visual_component_models.dart';
import '../../domain/visual_component_rules.dart';
import '../../domain/visual_component_sequence.dart';
import '../../domain/visual_hydrant_configuration.dart';

enum VisualComponentsSection { publicNetwork, privateNetwork }
enum _SaveState { saved, dirty, saving, error }

class VisualComponentsListStepPage extends StatefulWidget {
  const VisualComponentsListStepPage({
    required this.configuration,
    required this.components,
    required this.victaulicGroup,
    required this.section,
    required this.flowMeterComplete,
    required this.flowMeterConfirmed,
    required this.initialIndex,
    required this.readOnly,
    required this.actorId,
    required this.onChanged,
    required this.onVictaulicChanged,
    required this.onComponentConfirmed,
    required this.onFlowMeterConfirmed,
    required this.onIndexChanged,
    required this.onStepCompleted,
    required this.onPreviousStep,
    required this.onEditFlowMeter,
    required this.onCapturePhoto,
    super.key,
  });

  final VisualHydrantConfiguration configuration;
  final List<VisualComponentInspection> components;
  final VisualVictaulicGroupInspection? victaulicGroup;
  final VisualComponentsSection section;
  final bool flowMeterComplete, flowMeterConfirmed, readOnly;
  final int initialIndex;
  final String actorId;
  final Future<void> Function(List<VisualComponentInspection>) onChanged;
  final Future<void> Function(VisualVictaulicGroupInspection) onVictaulicChanged;
  final Future<void> Function(String componentId) onComponentConfirmed;
  final Future<void> Function() onFlowMeterConfirmed;
  final Future<void> Function(int index) onIndexChanged;
  final Future<void> Function() onStepCompleted;
  final Future<void> Function() onPreviousStep;
  final VoidCallback onEditFlowMeter;
  final void Function(String componentId, ImageSource source) onCapturePhoto;

  @override
  State<VisualComponentsListStepPage> createState() =>
      _VisualComponentsListStepPageState();
}

class _VisualComponentsListStepPageState
    extends State<VisualComponentsListStepPage> {
  int _index = 0;
  VisualComponentInspection? _draft;
  VisualVictaulicGroupInspection? _victaulicDraft;
  _SaveState _saveState = _SaveState.saved;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    final last = _sequence.length;
    _index = widget.initialIndex.clamp(0, last);
  }

  @override
  void didUpdateWidget(covariant VisualComponentsListStepPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final draft = _draft;
    if (draft != null) {
      for (final stored in widget.components) {
        if (stored.id == draft.id && stored.photoIds != draft.photoIds) {
          _draft = draft.copyWith(photoIds: stored.photoIds);
          break;
        }
      }
    }
  }

  List<VisualComponentSequenceItem> get _sequence =>
      widget.section == VisualComponentsSection.publicNetwork
          ? VisualComponentSequence.publicNetwork(widget.configuration)
          : VisualComponentSequence.privateNetwork(widget.configuration);

  VisualComponentInspection? _storedFor(VisualComponentSequenceItem item) {
    if (item.kind == VisualSequenceItemKind.canonicalFlowMeter) return null;
    for (final value in widget.components) {
      if (value.active && value.componentDefinitionId == item.definition!.id) {
        return value;
      }
    }
    return null;
  }

  VisualComponentInspection? _editableFor(VisualComponentSequenceItem item) {
    final stored = _storedFor(item);
    return stored == null ? null : VisualComponentRules.suggestedDefaults(stored);
  }

  bool _confirmed(VisualComponentSequenceItem item) =>
      item.kind == VisualSequenceItemKind.canonicalFlowMeter
          ? widget.flowMeterConfirmed
          : _storedFor(item)?.isReviewed == true;

  @override
  Widget build(BuildContext context) {
    final sequence = _sequence;
    if (_index >= sequence.length) return _summary(sequence);
    final item = sequence[_index];
    _draft ??= _editableFor(item);
    if (item.definition?.type == VisualComponentType.victaulicGroup &&
        _victaulicDraft == null &&
        _draft != null) {
      _victaulicDraft = widget.victaulicGroup ??
          VisualVictaulicGroupInspection(componentInspectionId: _draft!.id);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(item, sequence.length),
        const SizedBox(height: 12),
        if (item.outlet != null) _outletHeader(item.outlet!),
        if (item.kind == VisualSequenceItemKind.canonicalFlowMeter)
          _flowMeterCard()
        else if (_draft != null)
          _componentForm(item.definition!, _draft!),
        if (_validationMessage != null)
          Card(
            color: const Color(0xffffecec),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_validationMessage!),
            ),
          ),
        if (_saveState == _SaveState.error && _draft != null)
          TextButton.icon(
            onPressed: () => _persist(_draft!),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar guardado'),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openIndex,
          icon: const Icon(Icons.list_alt),
          label: const Text('Ver índice de componentes'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _previous,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Anterior'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: widget.readOnly ? _nextReadOnly : _confirmAndContinue,
              icon: const Icon(Icons.check),
              label: Text(_buttonLabel(item)),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _header(VisualComponentSequenceItem item, int total) {
    final confirmed = _confirmed(item);
    final title = widget.section == VisualComponentsSection.publicNetwork
        ? 'Red pública'
        : 'Red privada';
    return Card(
      color: const Color(0xffeaf2ff),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              _SaveBadge(state: _saveState),
            ]),
            Text('Componente ${_index + 1} de $total'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (_index + 1) / total),
            const SizedBox(height: 10),
            Text(item.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(confirmed ? 'Revisado' : 'Sin confirmar'),
            if (!confirmed && !widget.readOnly)
              const Text(
                'Valores sugeridos — confirme la revisión.',
                style: TextStyle(color: Color(0xff8a5b00), fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }

  Widget _outletHeader(VisualOutletInspection outlet) => Card(
    child: ListTile(
      leading: const Icon(Icons.call_split),
      title: Text('Salida ${outlet.outletNumber} · ${outlet.expectedDiameter}'),
      subtitle: outlet.observedDiameter == null
          ? const Text('Diámetro observado pendiente')
          : Text('Observado: ${outlet.observedDiameter}'),
    ),
  );

  Widget _flowMeterCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Resumen canónico del paso 4', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(widget.flowMeterComplete
              ? 'La captura obligatoria del medidor está completa.'
              : 'Faltan datos obligatorios del medidor.'),
          const Text('No se crea una inspección duplicada para este componente.'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: widget.readOnly ? null : widget.onEditFlowMeter,
            child: const Text('Revisar o editar medidor'),
          ),
        ],
      ),
    ),
  );

  Widget _componentForm(
    VisualComponentDefinition definition,
    VisualComponentInspection value,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('¿Está instalado?', style: TextStyle(fontWeight: FontWeight.w800)),
          _choiceWrap<PresenceAnswer>(
            values: PresenceAnswer.values,
            selected: value.presenceAnswer,
            label: (item) => item.label,
            onSelected: (answer) => _updateDraft(
              VisualComponentRules.changePresence(value, answer),
            ),
          ),
          if (value.presenceAnswer == PresenceAnswer.installed) ...[
            const SizedBox(height: 12),
            const Text('Estado visual', style: TextStyle(fontWeight: FontWeight.w800)),
            _choiceWrap<VisualComponentCondition>(
              values: VisualComponentCondition.values,
              selected: value.visualCondition,
              label: (item) => item.label,
              onSelected: (condition) => _updateDraft(
                VisualComponentRules.changeCondition(value, condition),
              ),
            ),
            if (value.visualCondition != VisualComponentCondition.good)
              _observedConditions(value),
            _specificFields(definition, value),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: widget.readOnly
                  ? null
                  : () => widget.onCapturePhoto('component:${value.id}', ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Cámara'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: widget.readOnly
                  ? null
                  : () => widget.onCapturePhoto('component:${value.id}', ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: Text('${value.photoIds.length} fotos'),
            )),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('comment-${value.id}-${value.comment}'),
            initialValue: value.comment,
            enabled: !widget.readOnly,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Comentario adicional'),
            onChanged: (text) => _updateDraft(value.copyWith(
              comment: text,
              explicitlyConfirmed: false,
              reviewStatus: ComponentReviewStatus.inProgress,
              clearReviewedAt: true,
              clearReviewedBy: true,
            )),
          ),
        ],
      ),
    ),
  );

  Widget _specificFields(
    VisualComponentDefinition definition,
    VisualComponentInspection value,
  ) {
    if (definition.type == VisualComponentType.pressureGauge) {
      return Column(children: [
        SwitchListTile(
          title: const Text('Carátula legible'),
          value: value.specificData.faceLegible ?? true,
          onChanged: widget.readOnly ? null : (answer) => _updateDraft(value.copyWith(
            specificData: value.specificData.copyWith(faceLegible: answer),
            explicitlyConfirmed: false,
          )),
        ),
        SwitchListTile(
          title: const Text('Cristal íntegro'),
          value: value.specificData.glassIntact ?? true,
          onChanged: widget.readOnly ? null : (answer) {
            final json = value.specificData.toJson()..['glassIntact'] = answer;
            _updateDraft(value.copyWith(
              specificData: VisualComponentSpecificData.fromJson(json),
              explicitlyConfirmed: false,
            ));
          },
        ),
        SwitchListTile(
          title: const Text('Aguja visible'),
          value: value.specificData.needleVisible ?? true,
          onChanged: widget.readOnly ? null : (answer) {
            final json = value.specificData.toJson()..['needleVisible'] = answer;
            _updateDraft(value.copyWith(
              specificData: VisualComponentSpecificData.fromJson(json),
              explicitlyConfirmed: false,
            ));
          },
        ),
        TextFormField(
          initialValue: value.specificData.visibleRange,
          enabled: !widget.readOnly,
          decoration: const InputDecoration(labelText: 'Rango visible'),
          onChanged: (text) => _updateDraft(value.copyWith(
            specificData: value.specificData.copyWith(visibleRange: text),
            explicitlyConfirmed: false,
          )),
        ),
        TextFormField(
          initialValue: value.specificData.visibleUnit,
          enabled: !widget.readOnly,
          decoration: const InputDecoration(labelText: 'Unidad visible'),
          onChanged: (text) => _updateDraft(value.copyWith(
            specificData: value.specificData.copyWith(visibleUnit: text),
            explicitlyConfirmed: false,
          )),
        ),
        const Text('Lectura visual no certificada. No sustituye una medición del REPORTE FUNCIONAL.'),
      ]);
    }
    if (definition.type == VisualComponentType.victaulicGroup) {
      final group = _victaulicDraft!;
      return Column(children: [
        TextFormField(
          initialValue: group.quantity == 0 ? '' : '${group.quantity}',
          enabled: !widget.readOnly,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Cantidad de juntas'),
          onChanged: (text) => setState(() {
            _victaulicDraft = group.withQuantity(int.tryParse(text) ?? 0);
            _saveState = _SaveState.dirty;
          }),
        ),
        DropdownButtonFormField<String>(
          initialValue: group.material.isEmpty ? null : group.material,
          decoration: const InputDecoration(labelText: 'Material'),
          items: const [
            DropdownMenuItem(value: 'metal', child: Text('Metal')),
            DropdownMenuItem(value: 'plastic', child: Text('Plástico')),
            DropdownMenuItem(value: 'mixed', child: Text('Mixto')),
            DropdownMenuItem(value: 'unidentified', child: Text('No identificable')),
          ],
          onChanged: widget.readOnly ? null : (material) => setState(() {
            _victaulicDraft = group.copyWith(material: material);
            _saveState = _SaveState.dirty;
          }),
        ),
        SwitchListTile(
          title: const Text('Aplicar el mismo estado a todas'),
          value: group.sameConditionForAll,
          onChanged: widget.readOnly ? null : (same) => setState(() {
            _victaulicDraft = group.copyWith(sameConditionForAll: same);
            _saveState = _SaveState.dirty;
          }),
        ),
        if (!group.sameConditionForAll)
          for (final joint in group.individualJoints)
            ExpansionTile(
              title: Text('Junta ${joint.number}'),
              subtitle: Text(joint.condition?.label ?? 'Pendiente'),
              children: [
                DropdownButtonFormField<VisualComponentCondition>(
                  initialValue: joint.condition,
                  decoration: const InputDecoration(labelText: 'Estado individual'),
                  items: VisualComponentCondition.values
                      .map((condition) => DropdownMenuItem(
                            value: condition,
                            child: Text(condition.label),
                          ))
                      .toList(),
                  onChanged: widget.readOnly
                      ? null
                      : (condition) => _updateJoint(joint, condition),
                ),
              ],
            ),
      ]);
    }
    if (definition.type == VisualComponentType.filterAssembly) {
      return Column(children: [
        ..._technicalChecklist(definition.type, value),
        DropdownButtonFormField<String>(
          initialValue: value.specificData.internalVisibility,
          decoration: const InputDecoration(labelText: 'Visibilidad del conjunto'),
          items: const [
            DropdownMenuItem(value: 'visible', child: Text('Visible exteriormente')),
            DropdownMenuItem(value: 'notVerifiable', child: Text('No verificable visualmente')),
          ],
          onChanged: widget.readOnly ? null : (answer) => _updateDraft(value.copyWith(
            specificData: value.specificData.copyWith(internalVisibility: answer),
            explicitlyConfirmed: false,
          )),
        ),
      ]);
    }
    return Column(children: _technicalChecklist(definition.type, value));
  }

  void _updateJoint(
    VisualJointInspection joint,
    VisualComponentCondition? condition,
  ) {
    final group = _victaulicDraft!;
    final updated = VisualJointInspection(
      id: joint.id,
      number: joint.number,
      location: joint.location,
      material: joint.material,
      condition: condition,
      observedConditions: joint.observedConditions,
      photoIds: joint.photoIds,
      comments: joint.comments,
    );
    setState(() {
      _victaulicDraft = group.copyWith(individualJoints: [
        for (final item in group.individualJoints)
          if (item.id == joint.id) updated else item,
      ]);
      _saveState = _SaveState.dirty;
    });
  }

  List<Widget> _technicalChecklist(
    VisualComponentType type,
    VisualComponentInspection value,
  ) {
    final labels = switch (type) {
      VisualComponentType.serviceValve ||
      VisualComponentType.sectioningValve ||
      VisualComponentType.filterWashValve => const {
        'bodyCondition': 'Cuerpo íntegro',
        'mechanismCondition': 'Mecanismo presente e íntegro',
        'fixingCondition': 'Fijación adecuada',
        'accessibility': 'Accesible visualmente',
      },
      VisualComponentType.regulatingValve => const {
        'bodyCondition': 'Cuerpo íntegro',
        'coverCondition': 'Tapa íntegra',
        'connectionsCondition': 'Conexiones íntegras',
        'tubingCondition': 'Tubing íntegro',
        'fixingCondition': 'Fijación adecuada',
      },
      VisualComponentType.pilotValve => const {
        'bodyCondition': 'Cuerpo íntegro',
        'fixingCondition': 'Fijación adecuada',
        'tubingCondition': 'Mangueras íntegras',
        'connectionsCondition': 'Conexiones íntegras',
      },
      VisualComponentType.airValve => const {
        'bodyCondition': 'Cuerpo íntegro',
        'coverCondition': 'Tapa íntegra',
        'connectionsCondition': 'Conexión íntegra',
        'dischargeCondition': 'Descarga sin obstrucción visible',
      },
      VisualComponentType.venturi => const {
        'bodyCondition': 'Cuerpo sin fisuras ni deformación',
        'connectionsCondition': 'Conexiones íntegras',
        'pressureTapsCondition': 'Tomas de presión íntegras',
      },
      VisualComponentType.filter => const {
        'bodyCondition': 'Cuerpo íntegro',
        'coverCondition': 'Tapa íntegra',
        'mechanismCondition': 'Cierre visible completo',
        'connectionsCondition': 'Conexiones íntegras',
        'maintenanceAccess': 'Acceso para mantenimiento',
      },
      VisualComponentType.filterAssembly => const {
        'connectionsCondition': 'Uniones y accesorios íntegros',
        'fixingCondition': 'Montaje adecuado',
      },
      VisualComponentType.outletConnection => const {
        'bodyCondition': 'Cuerpo íntegro',
        'protectionCondition': 'Tapa o protección íntegra',
        'connectionThreadCondition': 'Rosca o conexión íntegra',
      },
      VisualComponentType.solenoid => const {
        'bodyCondition': 'Carcasa íntegra',
        'fixingCondition': 'Fijación adecuada',
        'connectionsCondition': 'Cableado y conectores íntegros',
        'protectionCondition': 'Protección presente',
      },
      _ => const <String, String>{},
    };
    return [
      for (final entry in labels.entries)
        SwitchListTile(
          title: Text(entry.value),
          value: value.specificData.toJson()[entry.key] != 'finding',
          onChanged: widget.readOnly
              ? null
              : (favorable) {
                  final json = value.specificData.toJson()
                    ..[entry.key] = favorable ? 'good' : 'finding';
                  _updateDraft(value.copyWith(
                    specificData: VisualComponentSpecificData.fromJson(json),
                    explicitlyConfirmed: false,
                  ));
                },
        ),
    ];
  }

  Widget _observedConditions(VisualComponentInspection value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      const Text('Condiciones observadas', style: TextStyle(fontWeight: FontWeight.w800)),
      for (final condition in ObservedCondition.values)
        if (condition != ObservedCondition.noVisibleDamage)
          CheckboxListTile(
            value: value.observedConditions.contains(condition),
            title: Text(condition.label),
            onChanged: widget.readOnly ? null : (selected) {
              final next = {...value.observedConditions}..remove(ObservedCondition.noVisibleDamage);
              if (selected == true) {
                next.add(condition);
              } else {
                next.remove(condition);
              }
              _updateDraft(value.copyWith(
                observedConditions: next,
                explicitlyConfirmed: false,
              ));
            },
          ),
    ],
  );

  Widget _choiceWrap<T>({
    required List<T> values,
    required T? selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(label(value)),
          selected: selected == value,
          onSelected: widget.readOnly ? null : (_) => onSelected(value),
        ),
    ],
  );

  void _updateDraft(VisualComponentInspection value) {
    setState(() {
      _draft = value;
      _saveState = _SaveState.dirty;
      _validationMessage = null;
    });
  }

  String _buttonLabel(VisualComponentSequenceItem item) {
    if (widget.readOnly) return _index == _sequence.length - 1 ? 'Ver resumen' : 'Siguiente';
    if (item.kind == VisualSequenceItemKind.canonicalFlowMeter) {
      return 'Confirmar medidor y continuar';
    }
    return _draft?.hasFinding == true
        ? 'Guardar hallazgo y continuar'
        : 'Confirmar componente y continuar';
  }

  Future<void> _confirmAndContinue() async {
    final item = _sequence[_index];
    if (item.kind == VisualSequenceItemKind.canonicalFlowMeter) {
      if (!widget.flowMeterComplete) {
        setState(() => _validationMessage = 'Completa primero los datos obligatorios del paso 4.');
        return;
      }
      setState(() => _saveState = _SaveState.saving);
      try {
        await widget.onFlowMeterConfirmed();
        if (!mounted) return;
        setState(() => _saveState = _SaveState.saved);
        _advance();
      } on Object {
        if (mounted) setState(() => _saveState = _SaveState.error);
      }
      return;
    }
    final draft = _draft!;
    final candidate = VisualComponentRules.confirm(
      draft,
      actor: widget.actorId,
      timestamp: DateTime.now().toUtc(),
    );
    final issues = VisualComponentRules.validate(
      candidate,
      hasValidPhoto: candidate.photoIds.isNotEmpty,
    );
    if (issues.isNotEmpty) {
      setState(() => _validationMessage = issues.first.message);
      return;
    }
    if (draft.componentType == VisualComponentType.victaulicGroup &&
        _victaulicDraft != null) {
      await widget.onVictaulicChanged(_victaulicDraft!);
    }
    await _persist(candidate);
    if (mounted && _saveState == _SaveState.saved) {
      await widget.onComponentConfirmed(candidate.id);
      _advance();
    }
  }

  Future<void> _persist(VisualComponentInspection value) async {
    setState(() => _saveState = _SaveState.saving);
    try {
      await widget.onChanged([
        for (final item in widget.components)
          if (item.id == value.id) value else item,
      ]);
      if (!mounted) return;
      setState(() {
        _draft = value;
        _saveState = _SaveState.saved;
      });
    } on Object {
      if (mounted) setState(() => _saveState = _SaveState.error);
    }
  }

  Future<void> _persistUnconfirmedIfNeeded() async {
    final draft = _draft;
    if (_saveState != _SaveState.dirty || draft == null) return;
    await _persist(draft.copyWith(
      explicitlyConfirmed: false,
      reviewStatus: ComponentReviewStatus.inProgress,
      clearReviewedAt: true,
      clearReviewedBy: true,
    ));
  }

  Future<void> _previous() async {
    await _persistUnconfirmedIfNeeded();
    if (!mounted) return;
    if (_index == 0) {
      await widget.onPreviousStep();
      return;
    }
    setState(() {
      _index--;
      _draft = _editableFor(_sequence[_index]);
      _victaulicDraft = null;
      _validationMessage = null;
    });
    await widget.onIndexChanged(_index);
  }

  void _nextReadOnly() => _advance();

  void _advance() {
    setState(() {
      _index++;
      _draft = _index < _sequence.length ? _editableFor(_sequence[_index]) : null;
      _victaulicDraft = null;
      _validationMessage = null;
    });
    widget.onIndexChanged(_index);
  }

  Future<void> _openIndex() async {
    await _persistUnconfirmedIfNeeded();
    if (!mounted) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _sequence.length,
          itemBuilder: (context, index) {
            final item = _sequence[index];
            final confirmed = _confirmed(item);
            final finding = _storedFor(item)?.hasFinding == true;
            return ListTile(
              minVerticalPadding: 12,
              leading: Icon(confirmed ? Icons.check_circle : Icons.pending_outlined),
              title: Text(item.name),
              subtitle: Text(finding ? 'Hallazgo confirmado' : confirmed ? 'Revisado' : 'Pendiente'),
              selected: index == _index,
              onTap: () => Navigator.pop(context, index),
            );
          },
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _index = selected;
      _draft = _editableFor(_sequence[_index]);
      _victaulicDraft = null;
      _validationMessage = null;
    });
    await widget.onIndexChanged(_index);
  }

  Widget _summary(List<VisualComponentSequenceItem> sequence) {
    final reviewed = sequence.where(_confirmed).length;
    final findings = sequence.where((item) => _storedFor(item)?.hasFinding == true).length;
    final photos = widget.components.fold<int>(0, (sum, item) =>
        _inCurrentSection(item) ? sum + item.photoIds.length : sum);
    final title = widget.section == VisualComponentsSection.publicNetwork
        ? 'Resumen de red pública'
        : 'Resumen de red privada';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text('$reviewed de ${sequence.length} revisados'),
            Text('${sequence.length - reviewed} pendientes'),
            Text('$findings hallazgos · $photos fotografías'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openIndex,
              icon: const Icon(Icons.list_alt),
              label: const Text('Volver a componentes'),
            ),
            FilledButton(
              onPressed: reviewed == sequence.length
                  ? () => widget.onStepCompleted()
                  : null,
              child: Text(widget.section == VisualComponentsSection.publicNetwork
                  ? 'Completar red pública'
                  : 'Completar red privada'),
            ),
          ],
        ),
      ),
    );
  }

  bool _inCurrentSection(VisualComponentInspection item) =>
      widget.section == VisualComponentsSection.publicNetwork
          ? item.compartment == VisualCompartment.publicNetwork
          : item.compartment != VisualCompartment.publicNetwork;
}

class _SaveBadge extends StatelessWidget {
  const _SaveBadge({required this.state});
  final _SaveState state;

  @override
  Widget build(BuildContext context) {
    final text = switch (state) {
      _SaveState.saved => 'Guardado en este dispositivo',
      _SaveState.dirty => 'Sin guardar',
      _SaveState.saving => 'Guardando…',
      _SaveState.error => 'Error al guardar · Reintentar',
    };
    return Semantics(label: text, child: Text(text, style: const TextStyle(fontSize: 11)));
  }
}
