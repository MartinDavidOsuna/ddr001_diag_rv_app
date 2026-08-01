import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/location/location_service.dart';
import '../../../core/media/reliable_photo_service.dart';
import '../../../domain/models/app_models.dart';
import '../../checklist/data/checklist_models.dart';
import '../../catalogs/dynamic_catalog_repository.dart';
import '../data/inspection_capture_services.dart';
import '../data/inspection_sync_coordinator.dart';
import '../data/rv_draft_repository.dart';
import '../domain/rv_draft.dart';
import '../domain/parcel_valve_configuration.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_validator.dart';

class RvInspectionController extends ChangeNotifier {
  RvInspectionController({
    required this.drafts,
    required this.coordinator,
    required this.hydrant,
    required this.user,
    required this.checklist,
    this.catalogs,
    RvLocationCapture? locationCapture,
    RvSignalCapture? signalCapture,
    ReliablePhotoService? photoService,
  }) : locationCapture = locationCapture ?? DeviceRvLocationCapture(),
       signalCapture = signalCapture ?? DeviceRvSignalCapture(),
       photoService = photoService ?? ReliablePhotoService();

  final RvDraftRepository drafts;
  final InspectionSyncCoordinator coordinator;
  final Hydrant hydrant;
  final AppUser user;
  final DynamicChecklist checklist;
  final DynamicCatalogRepository? catalogs;
  final RvLocationCapture locationCapture;
  final RvSignalCapture signalCapture;
  final ReliablePhotoService photoService;
  final validator = const RvValidator();
  RvDraft? draft;
  bool busy = false;
  String? message;

  Future<void> initialize() async {
    draft = await drafts.openOrCreate(
      hydrant: hydrant,
      user: user,
      checklist: checklist,
    );
    notifyListeners();
  }

  Future<void> answer(
    ChecklistSectionDefinition section,
    ChecklistItemDefinition item, {
    Object? value,
    List<Object?> selected = const [],
    bool notApplicable = false,
    String comment = '',
  }) async {
    final current = draft;
    if (current == null || current.isReadOnly) return;
    final answers = {...current.answers};
    answers[item.id] = RvAnswer(
      questionId: item.id,
      sectionId: section.id,
      answerType: item.type,
      value: value,
      selectedOptions: selected,
      notApplicable: notApplicable,
      comment: comment,
      updatedAt: DateTime.now().toUtc(),
    );
    draft = current.copyWith(
      answers: answers,
      answersStatus: RvPartStatus.pending,
      localStatus: current.serverInspectionId == null
          ? RvLocalStatus.pendingCreate
          : RvLocalStatus.pendingAnswers,
    );
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> setActiveFormStep(int value) async {
    final current = draft;
    if (current == null) return;
    final next = value.clamp(0, current.checklist.sections.length);
    if (next == current.activeFormStep) return;
    draft = current.copyWith(activeFormStep: next);
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<bool> goToNextStep() async {
    final current = draft;
    if (current == null || busy || current.isReadOnly) return false;
    final last = current.checklist.sections.length;
    if (current.activeFormStep >= last) return true;
    await setActiveFormStep(current.activeFormStep + 1);
    return false;
  }

  Future<bool> goToPreviousStep() async {
    final current = draft;
    if (current == null || busy || current.activeFormStep <= 0) return false;
    await setActiveFormStep(current.activeFormStep - 1);
    return true;
  }

  Future<void> saveParcelValveConfiguration(
    ParcelValveConfiguration configuration,
  ) async {
    final current = draft;
    if (current == null || current.isReadOnly) return;
    draft = current.copyWith(
      parcelValveConfiguration: configuration,
      answersStatus: RvPartStatus.pending,
      localStatus: current.serverInspectionId == null
          ? RvLocalStatus.pendingCreate
          : RvLocalStatus.pendingAnswers,
    );
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> navigateToIssue({
    required int step,
    String? questionId,
    String? subItemId,
    String? fieldId,
  }) async {
    final current = draft;
    if (current == null) return;
    draft = current.copyWith(
      activeFormStep: step,
      navigationQuestionId: questionId,
      navigationSubItemId: subItemId,
      navigationFieldId: fieldId,
      returnToSummary: true,
    );
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> clearNavigationTarget() async {
    final current = draft;
    if (current == null) return;
    draft = current.copyWith(clearNavigationTarget: true);
    await drafts.save(draft!);
  }

  Future<void> clearSummaryReturn() async {
    final current = draft;
    if (current == null) return;
    draft = current.copyWith(
      clearNavigationTarget: true,
      returnToSummary: false,
    );
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> captureLocationAndSignal() => _run(() async {
    String? locationFailure;
    String? signalFailure;
    try {
      final sample = await locationCapture.capture();
      draft = draft!.copyWith(
        location: sample,
        locationStatus: RvPartStatus.pending,
        localStatus: RvLocalStatus.pendingLocation,
      );
      await drafts.save(draft!);
    } on Object catch (error) {
      locationFailure = error is LocationCaptureException
          ? error.message
          : 'Ubicación no disponible.';
    }
    try {
      final sample = await signalCapture.capture();
      draft = draft!.copyWith(
        signal: sample,
        signalStatus: RvPartStatus.pending,
        localStatus: RvLocalStatus.pendingSignal,
      );
      await drafts.save(draft!);
    } on Object {
      signalFailure = 'Conectividad no disponible.';
    }
    message = [
      if (draft!.location != null) 'Ubicación guardada.',
      if (draft!.signal != null) 'Conectividad guardada.',
      ?locationFailure,
      ?signalFailure,
    ].join(' ');
  });

  Future<void> saveManualLocation({
    required double latitude,
    required double longitude,
    double? altitude,
  }) => _run(() async {
    if (latitude < -90 || latitude > 90) {
      throw const FormatException('Latitud fuera de rango.');
    }
    if (longitude < -180 || longitude > 180) {
      throw const FormatException('Longitud fuera de rango.');
    }
    draft = draft!.copyWith(
      location: RvLocationSample(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        source: 'manual',
        capturedAt: DateTime.now().toUtc(),
      ),
      locationStatus: RvPartStatus.pending,
      localStatus: RvLocalStatus.pendingLocation,
    );
    await drafts.save(draft!);
    message = 'Ubicación manual guardada.';
  });

  Future<void> addPhoto(String slot, ImageSource source) => _run(() async {
    final stepBefore = draft!.activeFormStep;
    final photo = await photoService.acquire(
      pickerSource: source,
      hydrantId: hydrant.id,
      inspectionId: draft!.clientInspectionId,
      category: slot,
      evidenceRequirementId: slot,
      userId: user.id,
      userName: user.fullName,
      brigadeId: user.brigadeId,
      deviceId: user.deviceId,
    );
    if (photo == null) {
      _externalActionLog(stepBefore, slot);
      return;
    }
    final photos = <String, List<RvPhotoReference>>{
      ...draft!.photos,
      slot: [
        ...draft!.photosFor(slot),
        RvPhotoReference(
          photoId: photo.id,
          slotCode: slot,
          status: RvPhotoUploadStatus.pending,
        ),
      ],
    };
    draft = draft!.copyWith(
      photos: photos,
      photosStatus: RvPartStatus.pending,
      localStatus: RvLocalStatus.pendingPhotos,
    );
    await drafts.save(draft!);
    _externalActionLog(stepBefore, slot);
    message = 'Fotografía capturada y guardada localmente.';
  });

  Future<void> addGeneralPhoto(ImageSource source) async {
    final current = draft;
    if (current == null ||
        current.generalPhotos.length >= 5 ||
        !current.canAddComplements) {
      return;
    }
    final photoId = const Uuid().v4();
    await addPhoto('general:$photoId', source);
    final updated = draft;
    if (updated == null) return;
    var order = 0;
    final photos = <String, List<RvPhotoReference>>{};
    for (final entry in updated.photos.entries) {
      photos[entry.key] = entry.value.map((photo) {
        if (!photo.isGeneral) return photo;
        order++;
        return photo.copyWith(order: order);
      }).toList();
    }
    draft = updated.copyWith(photos: photos);
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> updateGeneralPhotoDescription(
    String photoId,
    String value,
  ) async {
    final current = draft;
    if (current == null || value.length > 300) {
      return;
    }
    final photos = <String, List<RvPhotoReference>>{
      for (final entry in current.photos.entries)
        entry.key: entry.value
            .map(
              (photo) => photo.photoId == photoId
                  ? photo.copyWith(
                      description: value.trim(),
                      clearDescription: value.trim().isEmpty,
                    )
                  : photo,
            )
            .toList(),
    };
    draft = current.copyWith(photos: photos, hasPendingChanges: true);
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> saveGeneralObservations(String value) async {
    final current = draft;
    if (current == null || value.length > 2000 || !current.canAddComplements) {
      return;
    }
    draft = current.copyWith(
      generalObservations: value.trim().isEmpty ? null : value,
      clearGeneralObservations: value.trim().isEmpty,
      hasPendingChanges: true,
    );
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> removeGeneralPhoto(RvPhotoReference photo) async {
    if (draft?.editingMode == RvEditingMode.validatedComplements &&
        photo.status == RvPhotoUploadStatus.verified) {
      return;
    }
    final current = draft;
    if (current == null) return;
    final photos = <String, List<RvPhotoReference>>{...current.photos}
      ..remove(photo.slotCode);
    var order = 0;
    for (final entry in photos.entries.toList()) {
      photos[entry.key] = entry.value.map((item) {
        if (!item.isGeneral) return item;
        order++;
        return item.copyWith(order: order);
      }).toList();
    }
    // A confirmed file is deliberately retained: only the next immutable
    // version drops its association, so historical versions remain viewable.
    draft = current.copyWith(
      photos: photos,
      photosStatus: RvPartStatus.pending,
      hasPendingChanges: true,
    );
    await drafts.save(draft!);
    notifyListeners();
  }

  void _externalActionLog(int stepBefore, String slot) {
    if (!kDebugMode) return;
    final rawId = draft!.clientInspectionId;
    final safeId = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    debugPrint(
      '[RV-EXTERNAL] stepBeforeExternalAction=${stepBefore + 1} '
      'stepAfterExternalAction=${draft!.activeFormStep + 1} '
      'photoSlot=$slot inspectionId=$safeId '
      'stateRestored=${stepBefore == draft!.activeFormStep}',
    );
  }

  Future<void> removePhoto(String slot, String photoId) async {
    if (draft?.isReadOnly != false) return;
    final reference = draft!
        .photosFor(slot)
        .where((photo) => photo.photoId == photoId)
        .firstOrNull;
    if (reference == null) return;
    if (reference.status == RvPhotoUploadStatus.verified) {
      final serverInspectionId = draft!.serverInspectionId;
      if (serverInspectionId == null) {
        throw StateError('La inspección remota no está disponible.');
      }
      await coordinator.remote.deletePhoto(
        serverInspectionId,
        reference.serverPhotoId ?? reference.photoId,
      );
    }
    final photos = <String, List<RvPhotoReference>>{...draft!.photos};
    final remaining = draft!
        .photosFor(slot)
        .where((photo) => photo.photoId != photoId)
        .toList();
    remaining.isEmpty ? photos.remove(slot) : photos[slot] = remaining;
    draft = draft!.copyWith(photos: photos, photosStatus: RvPartStatus.pending);
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> synchronize({bool submit = false}) => _run(() async {
    await catalogs?.synchronizePending();
    await _reconcileCatalogAnswers();
    draft = await coordinator.synchronize(draft!, submit: submit);
    message =
        draft!.lastSyncError ??
        (draft!.localStatus == RvLocalStatus.submitted
            ? 'Inspección enviada.'
            : 'Sincronización terminada.');
  });

  Future<void> _reconcileCatalogAnswers() async {
    final repository = catalogs;
    if (repository == null) return;
    var changed = false;
    final answers = <String, RvAnswer>{...draft!.answers};
    for (final entry in answers.entries) {
      final answer = entry.value;
      if (answer.value is! Map) continue;
      final value = Map<String, dynamic>.from(answer.value! as Map);
      if (value['catalogId'] != null) continue;
      final localId = value['localCatalogId']?.toString();
      if (localId == null) continue;
      final remoteId = repository.remoteIdFor(localId);
      if (remoteId == null) continue;
      changed = true;
      answers[entry.key] = RvAnswer(
        questionId: answer.questionId,
        sectionId: answer.sectionId,
        answerType: answer.answerType,
        value: {...value, 'catalogId': remoteId},
        selectedOptions: answer.selectedOptions,
        notApplicable: answer.notApplicable,
        comment: answer.comment,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    var configuration = draft!.parcelValveConfiguration;
    if (configuration != null) {
      Map<String, dynamic>? reconcile(Map<String, dynamic>? value) {
        if (value == null || value['catalogId'] != null) return value;
        final remoteId = repository.remoteIdFor(
          value['localCatalogId']?.toString() ?? '',
        );
        if (remoteId == null) return value;
        changed = true;
        return {...value, 'catalogId': remoteId, 'isPendingSync': false};
      }

      configuration = configuration.copyWith(
        valves: [
          for (final valve in configuration.valves)
            valve.copyWith(
              valveBrand: reconcile(valve.valveBrand),
              diameter: reconcile(valve.diameter),
              solenoidBrand: reconcile(valve.solenoidBrand),
              pilotBrand: reconcile(valve.pilotBrand),
              pressureGaugeBrand: reconcile(valve.pressureGaugeBrand),
            ),
        ],
      );
    }
    if (!changed) return;
    draft = draft!.copyWith(
      answers: answers,
      parcelValveConfiguration: configuration,
      answersStatus: RvPartStatus.pending,
    );
    await drafts.save(draft!);
  }

  Future<void> cancel(String reason) => _run(() async {
    draft = await coordinator.cancel(draft!, reason);
    message = 'Inspección cancelada.';
  });

  Future<void> _run(
    Future<void> Function() action, {
    bool locationError = false,
  }) async {
    if (busy || draft == null) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await action();
    } on LocationCaptureException catch (error) {
      message = error.message;
    } on Object catch (error) {
      message = locationError
          ? 'No fue posible capturar la ubicación.'
          : 'No fue posible completar la operación.';
      debugPrint('[RV] ${error.runtimeType}');
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
