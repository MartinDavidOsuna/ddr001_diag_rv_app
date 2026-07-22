import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/report_type_labels.dart';
import '../../core/constants/report_status_labels.dart';
import '../../core/location/coordinate_conversion_service.dart';
import '../../core/location/location_service.dart';
import '../../core/media/reliable_photo_service.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalogs/f02a_catalogs.dart';
import '../../data/catalogs/damage_component_catalog.dart';
import '../../data/services/cellular_network_diagnostics_controller.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/inspections/visual_inspection.dart';
import '../../domain/inspections/visual_inspection_step_validator.dart';
import '../../domain/media/inspection_photo.dart';
import '../shared/section_photo_counter.dart';
import '../../domain/media/media_sync_status.dart';
import '../../domain/network/cellular_network_diagnostic.dart';
import '../../domain/network/wifi_technical_assessment.dart';
import '../../domain/network/wifi_assessment_rules.dart';
import '../../domain/functional/functional_models.dart';
import '../visual_report/data/visual_report_compatibility_adapter.dart';
import '../visual_report/presentation/steps/visual_components_list_step_page.dart';

class VisualReportPage extends StatefulWidget {
  const VisualReportPage({
    required this.hydrantId,
    required this.type,
    super.key,
  });
  final String hydrantId, type;
  @override
  State<VisualReportPage> createState() => _VisualReportPageState();
}

class _VisualReportPageState extends State<VisualReportPage> {
  VisualInspection? inspection;
  bool loading = true, dirty = false, saving = false;
  bool locationCaptureRunning = false;
  CellularNetworkDiagnosticsController? _cellularController;
  String? error;
  List<InspectionValidationError> validationErrors = [];
  final ScrollController _scrollController = ScrollController();
  double? dragStart;

  static const titles = [
    'Identificación',
    'Ubicación y georreferencia',
    'Acceso',
    'Medidor de caudal',
    'Componentes de red pública',
    'Componentes de red privada',
    'Energía y comunicaciones',
    'Estado físico y daños',
    'Fotografías y cierre',
  ];

  @override
  void dispose() {
    if (_cellularController?.isRunning == true) {
      unawaited(_cellularController!.cancel(interrupted: true));
    }
    _cellularController?.removeListener(_onCellularChanged);
    _cellularController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.type != 'a') {
      setState(() => loading = false);
      return;
    }
    final state = context.read<AppState>();
    final stored = await state.visualInspectionRepository.openOrCreate(
      state.hydrant(widget.hydrantId),
      state.user,
    );
    final value = const VisualReportCompatibilityAdapter().project(stored);
    await state.trace(
      'draft_recovered',
      'Borrador de ${ReportTypeLabels.visualFull} abierto',
      hydrantId: widget.hydrantId,
    );
    if (mounted) {
      setState(() {
        inspection = value;
        loading = false;
      });
      _scheduleAutomaticLocationIfNeeded();
      _scheduleCellularDiagnosticsIfNeeded();
    }
  }

  void _setSectionValue(String section, String key, Object? value) {
    if (inspection?.status == InspectionStatus.completed) {
      return;
    }
    final json = inspection!.toJson();
    if (section == 'root') {
      json[key] = value;
    } else {
      final nested = Map<String, dynamic>.from(json[section] as Map? ?? {});
      nested[key] = value;
      json[section] = nested;
    }
    if (section == 'flowMeter') {
      json['flowMeterComponentConfirmed'] = false;
      json['flowMeterComponentReviewedBy'] = null;
      json['flowMeterComponentReviewedAt'] = null;
    }
    json['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    setState(() {
      inspection = VisualInspection.fromJson(json);
      dirty = true;
      error = null;
      validationErrors = [];
    });
    if (key == 'matchesAssignment' ||
        key == 'energyAvailabilityAnswer' ||
        key == 'wifiAssessment') {
      context.read<AppState>().trace(
        'visual_answer_changed',
        'Respuesta actualizada en REPORTE VISUAL',
        hydrantId: widget.hydrantId,
        entityType: section,
        entityId: key,
        metadata: {'value': value},
      );
    }
  }

  Future<void> _save({int? nextStep}) async {
    if (inspection?.status == InspectionStatus.completed) {
      return;
    }
    final state = context.read<AppState>();
    if (inspection?.currentStep == 7 &&
        nextStep != null &&
        nextStep != 6 &&
        _cellularController?.isRunning == true) {
      await _cellularController!.cancel(interrupted: true);
    }
    setState(() => saving = true);
    final updated = inspection!.copyWith(
      schemaVersion: inspection!.hydrantConfiguration == null
          ? inspection!.schemaVersion
          : 2,
      currentStep: nextStep ?? inspection!.currentStep,
    );
    await state.visualInspectionRepository.save(updated);
    await state.trace(
      'inspection_step_saved',
      'Paso ${updated.currentStep} guardado',
      hydrantId: widget.hydrantId,
    );
    if (mounted) {
      setState(() {
        inspection = updated;
        dirty = false;
        saving = false;
      });
      _scheduleAutomaticLocationIfNeeded();
      _scheduleCellularDiagnosticsIfNeeded();
    }
  }

  void _scheduleAutomaticLocationIfNeeded() {
    if (inspection?.currentStep != 2 ||
        inspection!.geoReference.hasValidPosition ||
        locationCaptureRunning) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && inspection?.currentStep == 2) _captureLocation();
    });
  }

  void _scheduleCellularDiagnosticsIfNeeded() {
    if (inspection?.currentStep != 7) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || inspection?.currentStep != 7) return;
      _ensureCellularController();
      if (_cellularController!.diagnostic.status ==
          CellularDiagnosticStatus.idle) {
        unawaited(_cellularController!.start());
      }
    });
  }

  void _ensureCellularController() {
    if (_cellularController != null) return;
    final stored = inspection!.energyCommunication.cellularDiagnostic;
    var restored = stored.isEmpty
        ? null
        : CellularNetworkDiagnostic.fromJson(stored);
    if (restored?.isRunning == true) {
      restored = restored!.copyWith(
        status: CellularDiagnosticStatus.cancelled,
        stage: CellularDiagnosticStage.completed,
        completedAt: DateTime.now().toUtc(),
        errorCode: 'interrupted',
        errorMessage: 'El diagnóstico anterior quedó interrumpido.',
        internetStatus: CellularInternetStatus.cancelled,
        progress: 1,
      );
    }
    _cellularController = CellularNetworkDiagnosticsController(
      inspectionId: inspection!.id,
      restored: restored,
      persist: _persistCellularDiagnostic,
    )..addListener(_onCellularChanged);
  }

  void _onCellularChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _persistCellularDiagnostic(
    CellularNetworkDiagnostic diagnostic,
  ) async {
    if (!mounted || inspection == null) return;
    _setSectionValue(
      'energyCommunication',
      'cellularDiagnostic',
      diagnostic.toJson(),
    );
    final state = context.read<AppState>();
    await state.visualInspectionRepository.save(inspection!);
    await state.trace(
      'cellular_diagnostic_${diagnostic.status.name}',
      'Diagnóstico de red GPRS: ${diagnostic.status.name}',
      hydrantId: widget.hydrantId,
      metadata: diagnostic.toJson(),
    );
  }

  Future<void> _back() async {
    if (inspection?.status == InspectionStatus.completed) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/hydrants/${widget.hydrantId}');
      }
      return;
    }
    if (dirty) {
      final leave =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Guardar cambios'),
              content: const Text(
                'Los cambios se guardarán como borrador antes de regresar.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Continuar aquí'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Guardar y regresar'),
                ),
              ],
            ),
          ) ??
          false;
      if (!leave || !mounted) return;
      await _save();
    }
    if (!mounted) return;
    if (inspection != null && inspection!.currentStep > 1) {
      await _save(nextStep: inspection!.currentStep - 1);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hydrants/${widget.hydrantId}');
    }
  }

  Future<void> _next() async {
    final state = context.read<AppState>();
    final validator = VisualInspectionStepValidator.fromHive(inspection!);
    final currentResult = validator.validateStep(
      inspection!,
      inspection!.currentStep,
    );
    if (!currentResult.isValid) {
      await _save();
      if (!mounted) return;
      setState(() => validationErrors = currentResult.errors);
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }
    if (inspection!.currentStep < 9) {
      await _save(nextStep: inspection!.currentStep + 1);
      return;
    }
    final globalResult = validator.validateAll(inspection!);
    if (!globalResult.isValid) {
      await state.trace(
        'visual_report_finish_failed',
        'Intento de finalización con datos incompletos',
        hydrantId: widget.hydrantId,
      );
      if (!mounted) return;
      setState(() => validationErrors = globalResult.errors);
      return;
    }
    setState(() => saving = true);
    final json = inspection!.toJson();
    json['status'] = InspectionStatus.completed.name;
    json['completedAt'] = DateTime.now().toUtc().toIso8601String();
    json['currentStep'] = 9;
    final completed = VisualInspection.fromJson(json);
    try {
      await state.visualInspectionRepository.finalize(completed);
      if (completed.result.requiresTechnicalInspection) {
        final now = DateTime.now().toUtc();
        await state.functionalEligibilityRepository.save(
          FunctionalReportEligibility(
            hydrantId: widget.hydrantId,
            allowed: true,
            source: FunctionalEligibilitySource.requiredByVisualResult,
            reason: completed.result.technicalInspectionReasons.join(', '),
            authorizedBy: state.user.id,
            authorizedRole: state.user.role,
            deviceId: state.user.deviceId,
            authorizedAt: now,
            pendingValidation: true,
            supervisorValidationRequired: true,
            visualReportId: completed.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await state.enqueueSync(
          entityType: 'functionalEligibility',
          entityId: widget.hydrantId,
          hydrantId: widget.hydrantId,
        );
        await state.trace(
          'functional_eligibility_created',
          'RF requerido por resultado de REPORTE VISUAL',
          hydrantId: widget.hydrantId,
          inspectionId: completed.id,
        );
      }
      await state.syncBox.put(completed.id, 'Guardado localmente');
      state.markVisualReportCompleted(widget.hydrantId);
      await state.trace(
        'visual_report_completed',
        '${ReportTypeLabels.visualFull} finalizado',
        hydrantId: widget.hydrantId,
      );
      if (!mounted) return;
      setState(() {
        inspection = completed;
        saving = false;
        dirty = false;
      });
      await _showCompletion(completed);
    } catch (failure) {
      await state.trace(
        'visual_report_persistence_failed',
        '$failure',
        hydrantId: widget.hydrantId,
      );
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'No fue posible finalizar el reporte. El borrador permanece guardado.\n$failure';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.type != 'a') return const _F02BPlaceholder();
    final value = inspection!;
    final step = value.status == InspectionStatus.completed &&
            value.visualFlowVersion < 2
        ? switch (value.currentStep) {
            6 => 7,
            7 => 8,
            8 => 9,
            _ => value.currentStep,
          }
        : value.currentStep;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppPageHeader(
          title: '${ReportTypeLabels.visualFull} · ${titles[step - 1]}',
          subtitle:
              '${context.read<AppState>().hydrant(widget.hydrantId).code} · Paso $step de 9',
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StatusBadge(
                saving
                    ? 'Guardando'
                    : dirty
                    ? 'Sin guardar'
                    : 'Guardado',
                color: saving || dirty ? AppColors.orange : AppColors.green,
              ),
            ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (details) =>
              dragStart = details.globalPosition.dx,
          onHorizontalDragEnd: (details) {
            final start = dragStart ?? 0;
            if ((details.primaryVelocity ?? 0) > 400 && start > 28) _back();
            dragStart = null;
          },
          child: Column(
            children: [
              LinearProgressIndicator(value: step / 9, color: AppColors.teal),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (validationErrors.isNotEmpty)
                      _ValidationSummary(
                        errors: validationErrors,
                        onSelected: _goToValidationError,
                      ),
                    _StepBody(
                      inspection: value,
                      step: step,
                      saveDraft: () => _save(),
                      completeCurrentStep: _next,
                      previousCurrentStep: _back,
                      setValue: _setSectionValue,
                      captureLocation: _captureLocation,
                      cellularDiagnostic: _cellularController?.diagnostic,
                      startCellularDiagnostic: () {
                        _ensureCellularController();
                        unawaited(_cellularController!.start());
                      },
                      cancelCellularDiagnostic: () =>
                          unawaited(_cellularController?.cancel()),
                      capturePhoto: _capturePhoto,
                      deletePhoto: _deletePhoto,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SectionCard(
                          child: Text(
                            error!,
                            style: const TextStyle(color: AppColors.red),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (step != 5 && step != 6)
                SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: saving ? null : _back,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Anterior'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: value.status == InspectionStatus.completed
                            ? FilledButton(
                                onPressed: () => context.pop(),
                                child: const Text('Volver al hidrante'),
                              )
                            : FilledButton(
                                onPressed: saving ? null : _next,
                                child: Text(
                                  step == 9
                                      ? 'Finalizar ${ReportTypeLabels.visualFull}'
                                      : 'Guardar y continuar',
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureLocation() async {
    if (locationCaptureRunning) return;
    final state = context.read<AppState>();
    final attempts = inspection!.geoReference.captureAttempts + 1;
    final initial = inspection!.toJson();
    initial['geoReference'] = {
      ...Map<String, dynamic>.from(initial['geoReference'] as Map),
      'captureStatus': 'searching',
      'captureAttempts': attempts,
      'technicalFailureReason': null,
      'technicalMessage': null,
    };
    setState(() {
      locationCaptureRunning = true;
      inspection = VisualInspection.fromJson(initial);
      error = null;
    });
    try {
      final position = await LocationService().capture();
      final utm = CoordinateConversionService().wgs84ToUtm(
        position.latitude,
        position.longitude,
      );
      final json = inspection!.toJson();
      json['geoReference'] = {
        ...Map<String, dynamic>.from(json['geoReference'] as Map),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'elevation': position.altitude,
        'horizontalAccuracy': position.accuracy,
        'verticalAccuracy': position.altitudeAccuracy,
        'capturedAt': position.timestamp.toUtc().toIso8601String(),
        'capturedBy': state.user.id,
        'utmEast': utm.easting,
        'utmNorth': utm.northing,
        'utmZone': utm.zone,
        'rtkStatus': RtkStatus.unavailable.name,
        'captureStatus': position.accuracy <= 50 ? 'obtained' : 'poorAccuracy',
        'captureAttempts': attempts,
        'permissionStatus': 'granted',
        'locationServiceEnabled': true,
        'provider': 'platformLocationProvider',
        'technicalFailureReason': position.accuracy <= 50
            ? null
            : LocationFailureReason.poorAccuracy.name,
        'technicalMessage': position.accuracy <= 50
            ? null
            : 'Se conservó la mejor lectura, pero su precisión es insuficiente.',
      };
      setState(() {
        inspection = VisualInspection.fromJson(json);
        dirty = true;
        locationCaptureRunning = false;
      });
      await state.trace(
        'location_captured',
        'Ubicación GPS real capturada',
        hydrantId: widget.hydrantId,
      );
    } on LocationCaptureException catch (e) {
      final json = inspection!.toJson();
      json['geoReference'] = {
        ...Map<String, dynamic>.from(json['geoReference'] as Map),
        'captureStatus': 'unavailable',
        'technicalFailureReason': e.reason.name,
        'technicalMessage': e.message,
        'captureAttempts': attempts,
        'permissionStatus': e.permissionStatus,
        'locationServiceEnabled': e.serviceEnabled,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'pendingGeoreference': true,
      };
      if (mounted) {
        setState(() {
          inspection = VisualInspection.fromJson(json);
          error = e.message;
          locationCaptureRunning = false;
          dirty = true;
        });
      }
      await state.trace(
        'location_error',
        e.message,
        hydrantId: widget.hydrantId,
        metadata: {'reason': e.reason.name, 'attempt': attempts},
      );
    } catch (e) {
      final json = inspection!.toJson();
      json['geoReference'] = {
        ...Map<String, dynamic>.from(json['geoReference'] as Map),
        'captureStatus': 'unavailable',
        'technicalFailureReason': LocationFailureReason.platformError.name,
        'technicalMessage': '$e',
        'captureAttempts': attempts,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'pendingGeoreference': true,
      };
      if (mounted) {
        setState(() {
          inspection = VisualInspection.fromJson(json);
          error = 'Ubicación no disponible por un error de plataforma.';
          locationCaptureRunning = false;
          dirty = true;
        });
      }
      await state.trace(
        'location_error',
        'Error de plataforma al capturar ubicación',
        hydrantId: widget.hydrantId,
        metadata: {'reason': LocationFailureReason.platformError.name},
      );
    }
  }

  Future<void> _capturePhoto(String category, ImageSource source) async {
    final state = context.read<AppState>();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final componentId = category.startsWith('component:')
          ? category.substring('component:'.length)
          : null;
      final photo = await ReliablePhotoService().acquire(
        pickerSource: source,
        hydrantId: widget.hydrantId,
        inspectionId: inspection!.id,
        category: category,
        componentId: componentId,
        userId: state.user.id,
        userName: state.user.fullName,
        brigadeId: state.user.brigadeId,
        deviceId: state.user.deviceId,
      );
      if (photo != null) {
        final ids = [...inspection!.photoIds, photo.id];
        setState(() {
          inspection = inspection!.copyWith(
            photoIds: ids,
            componentInspections: componentId == null
                ? inspection!.componentInspections
                : [
                    for (final component in inspection!.componentInspections)
                      if (component.id == componentId)
                        component.copyWith(
                          photoIds: [...component.photoIds, photo.id],
                        )
                      else
                        component,
                  ],
          );
          dirty = true;
        });
        await state.mediaBox.put(photo.id, photo.syncStatus.name);
        await state.trace(
          'photo_stored',
          'Fotografía $category almacenada y en cola',
          hydrantId: widget.hydrantId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
      await state.trace(
        'photo_processing_error',
        '$e',
        hydrantId: widget.hydrantId,
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> _deletePhoto(InspectionPhoto photo) async {
    if (inspection!.status == InspectionStatus.completed) return;
    final state = context.read<AppState>();
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Retirar fotografía'),
            content: const Text(
              'Se retirará del reporte y quedará en papelera lógica local.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Retirar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final box = Hive.box<String>('inspection_photos_v1');
    final raw = box.get(photo.id);
    if (raw == null) return;
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    json['deletedAt'] = DateTime.now().toUtc().toIso8601String();
    json['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await box.put(photo.id, jsonEncode(json));
    final ids = [...inspection!.photoIds]..remove(photo.id);
    setState(() {
      inspection = inspection!.copyWith(photoIds: ids);
      dirty = true;
      validationErrors = [];
    });
    await state.trace(
      'photo_deleted',
      'Fotografía retirada a papelera lógica',
      hydrantId: widget.hydrantId,
    );
  }

  Future<void> _showCompletion(VisualInspection completed) async {
    final state = context.read<AppState>();
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('${ReportTypeLabels.visualFull} finalizado'),
        content: Text(
          'Hidrante: ${state.hydrant(widget.hydrantId).code}\n'
          'Fecha: ${completed.completedAt?.toLocal()}\n'
          'Clasificación: ${ReportResultLabels.visual(completed.result.classification)}\n'
          'Fotografías: ${completed.photoIds.length}\n'
          'Estado: pendiente de sincronización\n'
          'Requiere ${ReportTypeLabels.functionalFull}: ${completed.result.requiresTechnicalInspection ? 'Sí' : 'No'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'summary'),
            child: const Text('Ver resumen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'sync'),
            child: const Text('Abrir sincronización'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'hydrant'),
            child: const Text('Volver al hidrante'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'sync') {
      context.push('/sync?return=/hydrants/${widget.hydrantId}');
    } else {
      context.go('/hydrants/${widget.hydrantId}');
    }
  }

  Future<void> _goToValidationError(InspectionValidationError issue) async {
    if (issue.stepNumber == inspection!.currentStep) return;
    await _save(nextStep: issue.stepNumber);
    if (mounted) setState(() => validationErrors = []);
  }
}

class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({required this.errors, required this.onSelected});
  final List<InspectionValidationError> errors;
  final ValueChanged<InspectionValidationError> onSelected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Completa los siguientes datos para continuar',
            style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final issue in errors)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Paso ${issue.stepNumber} · ${issue.message}',
                style: const TextStyle(color: AppColors.red),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.red),
              onTap: () => onSelected(issue),
            ),
        ],
      ),
    ),
  );
}

typedef SetValue = void Function(String section, String key, Object? value);

class _CellularDiagnosticsPanel extends StatelessWidget {
  const _CellularDiagnosticsPanel({
    required this.diagnostic,
    required this.onStart,
    required this.onCancel,
  });
  final CellularNetworkDiagnostic? diagnostic;
  final VoidCallback onStart, onCancel;

  String _stageLabel(String value) => switch (value) {
    'preparing' || 'requestingCellularNetwork' => 'Solicitando red celular',
    'checkingPermissions' => 'Revisando permisos',
    'waitingForAvailability' => 'Esperando disponibilidad',
    'verifyingCapabilities' => 'Verificando capacidades',
    'testingInternet' => 'Probando conexión a internet',
    'measuringResponse' => 'Midiendo respuesta',
    'calculatingResult' => 'Calculando resultado',
    'completed' => 'Diagnóstico completado',
    'partial' => 'Diagnóstico parcial',
    _ => 'Diagnóstico no disponible',
  };

  @override
  Widget build(BuildContext context) {
    final value = diagnostic;
    final running = value?.isRunning ?? false;
    final remaining = value?.remainingSeconds ?? 60;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    final result = switch (value?.status) {
      CellularDiagnosticStatus.available => 'Red celular disponible',
      CellularDiagnosticStatus.noCellularNetworksAvailable =>
        'No hay redes celulares disponibles',
      CellularDiagnosticStatus.indeterminate ||
      CellularDiagnosticStatus.failed =>
        'No se pudo completar el diagnóstico de red celular',
      CellularDiagnosticStatus.cancelled => 'Diagnóstico cancelado',
      _ => 'Análisis pendiente',
    };
    final probe = value?.internetProbe;
    final cellularDetected = probe == null
        ? 'No determinado'
        : probe.cellularNetworkAcquired
        ? 'Sí'
        : probe.result ==
              CellularInternetProbeOutcome.cellularNetworkUnavailable
        ? 'No'
        : 'No determinado';
    final validated = probe?.validatedCapabilityPresent == null
        ? 'No disponible'
        : probe!.validatedCapabilityPresent!
        ? 'Sí'
        : 'No';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diagnóstico de red GPRS',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (running)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Analizando disponibilidad de red celular'),
                ],
              ),
            ),
          LinearProgressIndicator(value: value?.progress ?? 0),
          const SizedBox(height: 6),
          Text(_stageLabel(value?.stage.name ?? 'preparing')),
          if (running) Text('Tiempo restante: $minutes:$seconds'),
          Text(result, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('Operador: ${value?.operatorName ?? 'No se pudo determinar'}'),
          Text(
            'Tecnología: ${value?.networkTechnology ?? 'No se pudo determinar'}',
          ),
          Text('Red celular detectada: $cellularDetected'),
          Text(
            'Internet celular confirmado: ${probe?.confirmsCellularInternet == true
                ? 'Sí'
                : running || probe == null
                ? 'Análisis pendiente'
                : 'No confirmado'}',
          ),
          Text('Android validó la conexión: $validated'),
          Text(
            'Capacidad INTERNET: ${probe?.internetCapabilityPresent == null
                ? 'No disponible'
                : probe!.internetCapabilityPresent!
                ? 'Sí'
                : 'No'}',
          ),
          Text(
            'Latencia: ${probe?.latencyMs == null ? 'No calculable' : '${probe!.latencyMs} ms'}',
          ),
          Text(
            'Calidad: ${value?.qualityScore == null ? 'No calculable' : '${value!.qualityScore}/10 · ${value.qualityLabel}'}',
          ),
          Text(
            'Efectividad de la conexión GPRS: ${value?.effectivenessPercentage == null ? 'No calculable' : '${value!.effectivenessPercentage!.toStringAsFixed(0)} %'}',
          ),
          Text('Tiempo utilizado: ${value?.elapsedSeconds ?? 0} s'),
          Text(
            'Método: ${probe?.methodVersion ?? value?.method ?? 'Pendiente'}',
          ),
          const Text(
            'Metodología DEMO. Esta prueba evalúa la red celular del teléfono y no certifica directamente el módem instalado en el hidrante.',
            style: TextStyle(fontSize: 11, color: AppColors.orange),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: running ? onCancel : onStart,
              icon: Icon(running ? Icons.stop_circle_outlined : Icons.refresh),
              label: Text(running ? 'Cancelar análisis' : 'Repetir análisis'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomaticLocationPanel extends StatelessWidget {
  const _AutomaticLocationPanel({required this.geo, required this.onRetry});
  final GeoReference geo;
  final VoidCallback onRetry;

  String get status => switch (geo.captureStatus) {
    'searching' => 'Buscando ubicación',
    'obtained' => 'Ubicación obtenida',
    'poorAccuracy' => 'Precisión insuficiente',
    'unavailable' => 'Ubicación no disponible',
    _ => 'Preparando captura automática',
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (geo.captureStatus == 'searching')
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    geo.hasValidPosition
                        ? Icons.location_on
                        : Icons.location_off_outlined,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (geo.captureStatus != 'searching')
                  IconButton(
                    tooltip: 'Reintentar captura automática',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            Text('Captura automática · Intentos: ${geo.captureAttempts}'),
            if (geo.technicalMessage != null) Text(geo.technicalMessage!),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F1F5),
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.map_outlined, size: 100, color: AppColors.muted),
            if (geo.hasValidPosition)
              const Icon(Icons.location_pin, size: 48, color: AppColors.red),
            const Positioned(
              left: 8,
              bottom: 6,
              child: Text(
                'Representación local; sin mapa SDK interactivo',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      SectionCard(
        child: Text(
          'Latitud: ${geo.latitude?.toStringAsFixed(6) ?? 'No disponible'}\n'
          'Longitud: ${geo.longitude?.toStringAsFixed(6) ?? 'No disponible'}\n'
          'UTM: ${geo.utmZone ?? 'No disponible'} ${geo.utmEast?.toStringAsFixed(2) ?? ''} ${geo.utmNorth?.toStringAsFixed(2) ?? ''}\n'
          'Elevación: ${geo.elevation?.toStringAsFixed(1) ?? 'No disponible'} m\n'
          'Precisión: ${geo.horizontalAccuracy?.toStringAsFixed(1) ?? 'No disponible'} m\n'
          'Fecha: ${geo.capturedAt?.toLocal() ?? 'No disponible'}\n'
          'Estado: $status',
        ),
      ),
    ],
  );
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.inspection,
    required this.step,
    required this.saveDraft,
    required this.completeCurrentStep,
    required this.previousCurrentStep,
    required this.setValue,
    required this.captureLocation,
    required this.cellularDiagnostic,
    required this.startCellularDiagnostic,
    required this.cancelCellularDiagnostic,
    required this.capturePhoto,
    required this.deletePhoto,
  });
  final VisualInspection inspection;
  final int step;
  final Future<void> Function() saveDraft;
  final Future<void> Function() completeCurrentStep;
  final Future<void> Function() previousCurrentStep;
  final SetValue setValue;
  final VoidCallback captureLocation;
  final CellularNetworkDiagnostic? cellularDiagnostic;
  final VoidCallback startCellularDiagnostic, cancelCellularDiagnostic;
  final void Function(String category, ImageSource source) capturePhoto;
  final Future<void> Function(InspectionPhoto photo) deletePhoto;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    switch (step) {
      case 1:
        children.addAll([
          const Text('¿El código observado corresponde con la asignación?'),
          _choices(
            ['Sí', 'No', 'No se puede confirmar'],
            inspection.identification.matchesAssignment?.name,
            (v) => setValue(
              'identification',
              'matchesAssignment',
              ['yes', 'no', 'unknown'][v],
            ),
          ),
          const Text('Estado de identificación'),
          _choices(
            const [
              'Placa legible',
              'Placa ilegible',
              'Sin placa',
              'Código diferente',
            ],
            inspection.identification.status?.name,
            (v) => setValue(
              'identification',
              'status',
              IdentificationStatus.values[v].name,
            ),
          ),
          TextFormField(
            initialValue: inspection.identification.observedCode,
            decoration: const InputDecoration(labelText: 'Código observado'),
            onChanged: (v) => setValue('identification', 'observedCode', v),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      capturePhoto('identificación', ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Foto de identificación'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Seleccionar de biblioteca',
                onPressed: () =>
                    capturePhoto('identificación', ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
              ),
            ],
          ),
          Builder(
            builder: (context) {
              final photos = _photosFor('identificación');
              return SectionPhotoCounter(
                photos: photos,
                requiredEvidence: true,
                onOpen: () =>
                    _openCategoryPhotos(context, 'identificación', photos),
              );
            },
          ),
        ]);
      case 2:
        final geo = inspection.geoReference;
        children.addAll([
          _AutomaticLocationPanel(geo: geo, onRetry: captureLocation),
        ]);
      case 3:
        children.addAll([
          const Text('Tipo de acceso'),
          _choices(
            F02aCatalogs.accessTypes,
            inspection.access.accessType?.name,
            (v) => setValue('access', 'accessType', AccessType.values[v].name),
          ),
          const Text('Condición'),
          _choices(
            F02aCatalogs.conditions,
            inspection.access.condition?.name,
            (v) => setValue(
              'access',
              'condition',
              PhysicalCondition.values[v].name,
            ),
          ),
          const Text('Tipo de camino'),
          _choices(
            const ['Pavimento', 'Terracería', 'Sendero', 'Parcela', 'Otro'],
            inspection.access.roadType?.name,
            (v) => setValue('access', 'roadType', RoadType.values[v].name),
          ),
          const Text('Riesgos'),
          Wrap(
            spacing: 6,
            children:
                [
                      'Ninguno',
                      'Lodo',
                      'Vegetación',
                      'Inundación',
                      'Acceso restringido',
                    ]
                    .map(
                      (risk) => FilterChip(
                        label: Text(risk),
                        selected: inspection.access.risks.contains(risk),
                        onSelected: (_) {
                          final values = [...inspection.access.risks];
                          if (values.contains(risk)) {
                            values.remove(risk);
                          } else {
                            if (risk == 'Ninguno') values.clear();
                            values.remove('Ninguno');
                            values.add(risk);
                          }
                          setValue('access', 'risks', values);
                        },
                      ),
                    )
                    .toList(),
          ),
        ]);
      case 4:
        children.addAll(
          _equipment(
            'flowMeter',
            inspection.flowMeter.exists,
            '¿Existe medidor de caudal?',
          ),
        );
        if (inspection.flowMeter.exists == true) {
          children.addAll([
            const Text('Condición física'),
            _choices(
              F02aCatalogs.conditions,
              inspection.flowMeter.condition?.name,
              (v) => setValue(
                'flowMeter',
                'condition',
                PhysicalCondition.values[v].name,
              ),
            ),
            const Text('Funcionamiento aparente'),
            _choices(
              const [
                'Funciona',
                'No funciona',
                'No verificado',
                'No disponible',
              ],
              inspection.flowMeter.operation?.name,
              (v) => setValue(
                'flowMeter',
                'operation',
                OperationState.values[v].name,
              ),
            ),
          ]);
        }
      case 5:
        children.add(
          VisualComponentsListStepPage(
            configuration: inspection.hydrantConfiguration!,
            components: inspection.componentInspections,
            victaulicGroup: inspection.victaulicGroupInspection,
            section: VisualComponentsSection.publicNetwork,
            flowMeterComplete:
                inspection.flowMeter.exists != null &&
                (inspection.flowMeter.exists != true ||
                    (inspection.flowMeter.condition != null &&
                        inspection.flowMeter.operation != null)),
            flowMeterConfirmed: inspection.flowMeterComponentConfirmed,
            initialIndex: inspection.publicComponentIndex,
            readOnly: inspection.status == InspectionStatus.completed,
            actorId: inspection.inspectorId,
            onChanged: (values) async {
              setValue(
                'root',
                'componentInspections',
                values.map((e) => e.toJson()).toList(),
              );
              await saveDraft();
            },
            onVictaulicChanged: (group) async {
              setValue('root', 'victaulicGroupInspection', group.toJson());
              await saveDraft();
            },
            onComponentConfirmed: (componentId) => context.read<AppState>().trace(
              'visual_component_confirmed',
              'Componente de red pública confirmado',
              hydrantId: inspection.hydrantId,
              metadata: {'reportId': inspection.id, 'componentId': componentId},
            ),
            onFlowMeterConfirmed: () async {
              final appState = context.read<AppState>();
              final now = DateTime.now().toUtc();
              setValue('root', 'flowMeterComponentConfirmed', true);
              setValue('root', 'flowMeterComponentReviewedBy', inspection.inspectorId);
              setValue('root', 'flowMeterComponentReviewedAt', now.toIso8601String());
              await saveDraft();
              await appState.trace(
                'visual_flow_meter_summary_confirmed',
                'Resumen canónico del medidor confirmado en red pública',
                hydrantId: inspection.hydrantId,
                metadata: {'reportId': inspection.id},
              );
            },
            onIndexChanged: (index) async {
              setValue('root', 'publicComponentIndex', index);
              await saveDraft();
            },
            onStepCompleted: completeCurrentStep,
            onPreviousStep: () async {
              await previousCurrentStep();
            },
            onEditFlowMeter: () => setValue('root', 'currentStep', 4),
            onCapturePhoto: capturePhoto,
          ),
        );
      case 6:
        children.add(
          VisualComponentsListStepPage(
            configuration: inspection.hydrantConfiguration!,
            components: inspection.componentInspections,
            victaulicGroup: inspection.victaulicGroupInspection,
            section: VisualComponentsSection.privateNetwork,
            flowMeterComplete:
                inspection.flowMeter.exists != null &&
                (inspection.flowMeter.exists != true ||
                    (inspection.flowMeter.condition != null &&
                        inspection.flowMeter.operation != null)),
            flowMeterConfirmed: inspection.flowMeterComponentConfirmed,
            initialIndex: inspection.privateComponentIndex,
            readOnly: inspection.status == InspectionStatus.completed,
            actorId: inspection.inspectorId,
            onChanged: (values) async {
              setValue(
                'root',
                'componentInspections',
                values.map((e) => e.toJson()).toList(),
              );
              await saveDraft();
            },
            onVictaulicChanged: (group) async {
              setValue('root', 'victaulicGroupInspection', group.toJson());
              await saveDraft();
            },
            onComponentConfirmed: (componentId) => context.read<AppState>().trace(
              'visual_component_confirmed',
              'Componente de red privada confirmado',
              hydrantId: inspection.hydrantId,
              metadata: {'reportId': inspection.id, 'componentId': componentId},
            ),
            onFlowMeterConfirmed: () async {},
            onIndexChanged: (index) async {
              setValue('root', 'privateComponentIndex', index);
              await saveDraft();
            },
            onStepCompleted: completeCurrentStep,
            onPreviousStep: () async {
              await previousCurrentStep();
            },
            onEditFlowMeter: () => setValue('root', 'currentStep', 4),
            onCapturePhoto: capturePhoto,
          ),
        );
      case 7:
        final wifiAssessment = WifiTechnicalAssessment.fromJson(
          inspection.energyCommunication.wifiAssessment,
        );
        final wifiRules = WifiAssessmentRules.evaluate(wifiAssessment);
        children.addAll([
          const Text('¿Hay energía disponible?'),
          _choices(
            const ['Sí', 'No', 'No verificado'],
            inspection.energyCommunication.energyAvailabilityAnswer?.name,
            (v) {
              final answer = MatchAnswer.values[v];
              setValue(
                'energyCommunication',
                'energyAvailabilityAnswer',
                answer.name,
              );
              setValue(
                'energyCommunication',
                'energyAvailable',
                answer == MatchAnswer.yes
                    ? true
                    : answer == MatchAnswer.no
                    ? false
                    : null,
              );
            },
          ),
        ]);
        if (inspection.energyCommunication.energyAvailable == true) {
          children.addAll([
            const Text('Fuentes de energía'),
            _multiSelect(
              F02aCatalogs.energySources,
              inspection.energyCommunication.sources,
              (v) => setValue('energyCommunication', 'sources', v),
            ),
            TextFormField(
              initialValue: inspection.energyCommunication.voltage,
              decoration: const InputDecoration(labelText: 'Voltaje observado'),
              onChanged: (v) => setValue('energyCommunication', 'voltage', v),
            ),
          ]);
        }
        children.addAll([
          _CellularDiagnosticsPanel(
            diagnostic: cellularDiagnostic,
            onStart: startCellularDiagnostic,
            onCancel: cancelCellularDiagnostic,
          ),
          const Text(
            'Evaluación manual de Wi-Fi',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const Text('¿Hay una red Wi-Fi cercana?'),
          _wifiChoices('wifiNearbyAnswer', allowNotApplicable: false),
          if (wifiRules.visibleQuestions.contains(
            WifiAssessmentQuestion.connectionPossible,
          )) ...[
            const Text('¿Es posible conectarse a la red Wi-Fi?'),
            _wifiChoices('wifiConnectionPossibleAnswer'),
          ],
          if (wifiRules.visibleQuestions.contains(
            WifiAssessmentQuestion.signal,
          )) ...[
            const Text('¿La señal Wi-Fi parece adecuada?'),
            _wifiChoices('wifiSignalAdequateAnswer'),
          ],
          if (wifiRules.visibleQuestions.contains(
            WifiAssessmentQuestion.internet,
          )) ...[
            const Text('¿Hay internet disponible mediante Wi-Fi?'),
            _wifiChoices('wifiInternetAvailableAnswer'),
          ],
          if (wifiAssessment.wifiNearbyAnswer == TechnicalAssessmentAnswer.yes)
            TextFormField(
              key: ValueKey(
                'wifi-comments-${wifiAssessment.wifiNearbyAnswer?.name}',
              ),
              initialValue: wifiAssessment.comments,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones de Wi-Fi',
              ),
              onChanged: (value) => _updateWifi('comments', value),
            ),
          const Text(
            'Wi-Fi es una evaluación del técnico. No se escanean redes, SSID ni intensidad.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ]);
      case 8:
        children.addAll([
          SwitchListTile(
            title: const Text('Sin daños visibles'),
            value: inspection.noVisibleDamageConfirmed,
            onChanged:
                inspection.damageIds.isEmpty &&
                    !inspection.damageAssessments.values.any(
                      (value) => value['status'] == 'damaged',
                    )
                ? (v) => setValue('root', 'noVisibleDamageConfirmed', v)
                : null,
          ),
          ..._damageChecklist(context),
        ]);
      case 9:
        children.add(const Text('Fotografías obligatorias'));
        for (final category in _requiredPhotoCategories()) {
          final photos = _photosFor(category);
          final count = photos.length;
          children.add(
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _categoryLabel(category),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextButton.icon(
                            onPressed: count == 0
                                ? null
                                : () => _openCategoryPhotos(
                                    context,
                                    category,
                                    photos,
                                  ),
                            icon: Icon(
                              count > 0
                                  ? Icons.check_circle
                                  : Icons.photo_outlined,
                              size: 18,
                            ),
                            label: Text(
                              '$count ${count == 1 ? 'tomada' : 'tomadas'}',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cámara',
                      onPressed: () =>
                          capturePhoto(category, ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                    IconButton(
                      tooltip: 'Biblioteca',
                      onPressed: () =>
                          capturePhoto(category, ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        children.add(const Text('Clasificación final'));
        children.add(
          _choices(
            F02aCatalogs.classifications,
            inspection.result.classification?.name,
            (v) => setValue(
              'result',
              'classification',
              FinalClassification.values[v].name,
            ),
          ),
        );
    }
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _Comments(
          initial: _comments(step),
          onChanged: (v) => setValue(
            _section(step),
            step == 9 ? 'finalComments' : 'comments',
            v,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children
          .map(
            (e) =>
                Padding(padding: const EdgeInsets.only(bottom: 12), child: e),
          )
          .toList(),
    );
  }

  Widget _multiSelect(
    List<String> options,
    List<String> selected,
    ValueChanged<List<String>> changed,
  ) => Wrap(
    spacing: 6,
    children: options
        .map(
          (option) => FilterChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (_) {
              final values = [...selected];
              values.contains(option)
                  ? values.remove(option)
                  : values.add(option);
              changed(values);
            },
          ),
        )
        .toList(),
  );

  Widget _wifiChoices(String field, {bool allowNotApplicable = true}) {
    final assessment = WifiTechnicalAssessment.fromJson(
      inspection.energyCommunication.wifiAssessment,
    );
    final selected = switch (field) {
      'wifiNearbyAnswer' => assessment.wifiNearbyAnswer,
      'wifiConnectionPossibleAnswer' => assessment.wifiConnectionPossibleAnswer,
      'wifiSignalAdequateAnswer' => assessment.wifiSignalAdequateAnswer,
      _ => assessment.wifiInternetAvailableAnswer,
    };
    final answers = [
      TechnicalAssessmentAnswer.yes,
      TechnicalAssessmentAnswer.no,
      TechnicalAssessmentAnswer.notVerified,
      if (allowNotApplicable) TechnicalAssessmentAnswer.notApplicable,
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final answer in answers)
          ChoiceChip(
            label: Text(switch (answer) {
              TechnicalAssessmentAnswer.yes => 'Sí',
              TechnicalAssessmentAnswer.no => 'No',
              TechnicalAssessmentAnswer.notVerified => 'No verificado',
              TechnicalAssessmentAnswer.notApplicable => 'No aplica',
            }),
            selected: selected == answer,
            onSelected: (_) => _updateWifi(field, answer.name),
          ),
      ],
    );
  }

  void _updateWifi(String field, Object? value) {
    final current = WifiTechnicalAssessment.fromJson(
      inspection.energyCommunication.wifiAssessment,
    );
    final answer = value is String
        ? TechnicalAssessmentAnswer.values
              .where((item) => item.name == value)
              .firstOrNull
        : null;
    final updated = switch (field) {
      'wifiNearbyAnswer' when answer != null =>
        WifiAssessmentRules.changeNearby(current, answer),
      'wifiConnectionPossibleAnswer' when answer != null =>
        WifiAssessmentRules.changeConnection(current, answer),
      'wifiSignalAdequateAnswer' when answer != null =>
        WifiAssessmentRules.changeLeaf(
          current,
          WifiAssessmentQuestion.signal,
          answer,
        ),
      'wifiInternetAvailableAnswer' when answer != null =>
        WifiAssessmentRules.changeLeaf(
          current,
          WifiAssessmentQuestion.internet,
          answer,
        ),
      'comments' => WifiAssessmentRules.changeComments(
        current,
        value as String? ?? '',
      ),
      _ => current,
    };
    setValue('energyCommunication', 'wifiAssessment', updated.toJson());
  }

  List<Widget> _damageChecklist(BuildContext context) => [
    for (final component in DamageComponentCatalog.components)
      Builder(
        builder: (context) {
          final current = Map<String, dynamic>.from(
            inspection.damageAssessments[component] ?? const {},
          );
          final status = current['status'] as String?;
          final category = 'daño:$component';
          final photos = _photosFor(category);
          void update(String key, Object? value) {
            final all = {
              for (final entry in inspection.damageAssessments.entries)
                entry.key: Map<String, dynamic>.from(entry.value),
            };
            all[component] = {...current, key: value};
            setValue('root', 'damageAssessments', all);
            if (key == 'status' && value == 'damaged') {
              setValue('root', 'noVisibleDamageConfirmed', false);
            }
          }

          return SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  component,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final entry in DamageComponentCatalog.statuses.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: status == entry.key,
                        onSelected: (_) => update('status', entry.key),
                      ),
                  ],
                ),
                if (status == 'damaged') ...[
                  TextFormField(
                    initialValue: current['comment'] as String? ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Comentario opcional del daño',
                    ),
                    onChanged: (value) => update('comment', value),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Tomar foto del daño',
                        onPressed: () =>
                            capturePhoto(category, ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                      IconButton(
                        tooltip: 'Seleccionar foto del daño',
                        onPressed: () =>
                            capturePhoto(category, ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                    ],
                  ),
                  SectionPhotoCounter(
                    photos: photos,
                    requiredEvidence: true,
                    onOpen: () =>
                        _openCategoryPhotos(context, category, photos),
                  ),
                ],
              ],
            ),
          );
        },
      ),
  ];

  List<InspectionPhoto> _photosFor(String category) {
    final box = Hive.box<String>('inspection_photos_v1');
    const accepted = {
      MediaSyncStatus.storedLocal,
      MediaSyncStatus.pendingUpload,
      MediaSyncStatus.uploading,
      MediaSyncStatus.uploadedUnverified,
      MediaSyncStatus.verified,
    };
    return [
          for (final id in inspection.photoIds)
            if (box.get(id) case final String raw)
              InspectionPhoto.fromJson(
                Map<String, dynamic>.from(jsonDecode(raw) as Map),
              ),
        ]
        .where(
          (photo) =>
              photo.inspectionId == inspection.id &&
              photo.category == category &&
              !photo.isDeleted &&
              File(photo.localPath).existsSync() &&
              photo.fileSize > 0 &&
              photo.sha256.isNotEmpty &&
              accepted.contains(photo.syncStatus),
        )
        .toList();
  }

  void _openCategoryPhotos(
    BuildContext context,
    String category,
    List<InspectionPhoto> photos,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _categoryLabel(category),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final photo in photos)
              Card(
                child: ListTile(
                  leading: Image.file(
                    File(photo.thumbnailPath),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                  title: Text('${photo.width} × ${photo.height}'),
                  subtitle: Text(
                    '${photo.capturedAt.toLocal()}\n${photo.syncStatus.name}',
                  ),
                  onTap: () => showDialog<void>(
                    context: sheetContext,
                    builder: (_) => Dialog(
                      child: InteractiveViewer(
                        child: Image.file(File(photo.localPath)),
                      ),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      Navigator.pop(sheetContext);
                      if (action == 'repeat') {
                        capturePhoto(category, ImageSource.camera);
                      } else {
                        await deletePhoto(photo);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'repeat', child: Text('Repetir')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) => switch (category) {
    'vistaGeneral' => 'Vista general',
    'válvula' => 'Válvulas',
    'solenoide' => 'Solenoides',
    _ => '${category[0].toUpperCase()}${category.substring(1)}',
  };

  List<String> _requiredPhotoCategories() => [
    'acceso',
    'panorámica',
    'vistaGeneral',
    'identificación',
    if (inspection.flowMeter.exists == true) 'medidor',
    if (inspection.pressureValve.exists == true) 'válvula',
    if (inspection.pressureValve.solenoidExists == true) 'solenoide',
    if (inspection.energyCommunication.energyAvailable == true) 'energía',
    if (inspection.energyCommunication.cellularDiagnostic.isNotEmpty)
      'comunicación',
  ];

  List<Widget> _equipment(
    String section,
    bool? exists,
    String label, {
    String key = 'exists',
  }) => [
    Text(label),
    _choices(
      ['Sí', 'No', 'No verificado'],
      exists == null
          ? null
          : exists
          ? 'Sí'
          : 'No',
      (v) => setValue(
        section,
        key,
        v == 0
            ? true
            : v == 1
            ? false
            : null,
      ),
    ),
  ];
  Widget _choices(
    List<String> values,
    String? selected,
    ValueChanged<int> onSelected,
  ) => Wrap(
    spacing: 8,
    children: [
      for (var i = 0; i < values.length; i++)
        ChoiceChip(
          label: Text(values[i]),
          selected: selected == values[i] || selected == _normalized(values[i]),
          onSelected: (_) => onSelected(i),
        ),
    ],
  );
  String _normalized(String text) =>
      const {
        'Sí': 'yes',
        'No': 'no',
        'Vehicular': 'vehicle',
        'Peatonal': 'walking',
        'Ambos': 'both',
        'Bueno': 'good',
        'Regular': 'fair',
        'Malo': 'bad',
        'Crítico': 'critical',
        'No verificado': 'unknown',
        'No se puede confirmar': 'unknown',
        'Operativo': 'operational',
        'Operativo con observaciones': 'observations',
        'No operativo': 'nonOperational',
        'Riesgo crítico': 'critical',
        'Placa legible': 'readablePlate',
        'Placa ilegible': 'unreadablePlate',
        'Sin placa': 'noPlate',
        'Código diferente': 'differentCode',
        'Pavimento': 'pavement',
        'Terracería': 'dirtRoad',
        'Sendero': 'trail',
        'Parcela': 'parcel',
        'Otro': 'other',
        'Funciona': 'works',
        'No funciona': 'doesNotWork',
        'No disponible': 'unavailable',
      }[text] ??
      text.toLowerCase().replaceAll(' ', '');
  String _section(int step) => [
    'identification',
    'geoReference',
    'access',
    'flowMeter',
    'pressureValve',
    'pressureValve',
    'energyCommunication',
    'result',
    'result',
  ][step - 1];
  String _comments(int step) => switch (step) {
    1 => inspection.identification.comments,
    2 => inspection.geoReference.comments,
    3 => inspection.access.comments,
    4 => inspection.flowMeter.comments,
    5 => inspection.pressureValve.comments,
    6 => inspection.pressureValve.comments,
    7 => inspection.energyCommunication.comments,
    8 => inspection.result.finalComments,
    _ => inspection.result.finalComments,
  };
}

class _Comments extends StatelessWidget {
  const _Comments({required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Comentarios adicionales'),
    subtitle: Text('${initial.length}/500 · opcional'),
    children: [
      TextFormField(
        initialValue: initial,
        maxLength: 500,
        maxLines: 3,
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Observaciones extraordinarias',
        ),
      ),
    ],
  );
}

class _F02BPlaceholder extends StatelessWidget {
  const _F02BPlaceholder();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageHeader(title: ReportTypeLabels.functionalFull),
    body: const Center(
      child: Text(
        '${ReportTypeLabels.functionalFull} se implementará en una etapa posterior.',
      ),
    ),
  );
}
