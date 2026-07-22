import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/location/location_service.dart';
import '../../../core/media/reliable_photo_service.dart';
import '../../../domain/models/app_models.dart';
import '../../checklist/data/checklist_models.dart';
import '../data/inspection_capture_services.dart';
import '../data/inspection_sync_coordinator.dart';
import '../data/rv_draft_repository.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_validator.dart';

class RvInspectionController extends ChangeNotifier {
  RvInspectionController({
    required this.drafts,
    required this.coordinator,
    required this.hydrant,
    required this.user,
    required this.checklist,
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

  Future<void> captureLocation() => _run(() async {
    final sample = await locationCapture.capture();
    draft = draft!.copyWith(
      location: sample,
      locationStatus: RvPartStatus.pending,
      localStatus: RvLocalStatus.pendingLocation,
    );
    await drafts.save(draft!);
    message = 'Ubicación capturada.';
  }, locationError: true);

  Future<void> captureSignal() => _run(() async {
    final sample = await signalCapture.capture();
    draft = draft!.copyWith(
      signal: sample,
      signalStatus: RvPartStatus.pending,
      localStatus: RvLocalStatus.pendingSignal,
    );
    await drafts.save(draft!);
    message = sample.connected
        ? 'Conectividad capturada.'
        : 'Sin conexión disponible; muestra guardada.';
  });

  Future<void> capturePhoto(String slot) => _run(() async {
    final photo = await photoService.acquire(
      pickerSource: ImageSource.camera,
      hydrantId: hydrant.id,
      inspectionId: draft!.clientInspectionId,
      category: slot,
      evidenceRequirementId: slot,
      userId: user.id,
      userName: user.fullName,
      brigadeId: user.brigadeId,
      deviceId: user.deviceId,
    );
    if (photo == null) return;
    final photos = {
      ...draft!.photos,
      slot: RvPhotoReference(
        photoId: photo.id,
        slotCode: slot,
        status: RvPhotoUploadStatus.pending,
      ),
    };
    draft = draft!.copyWith(
      photos: photos,
      photosStatus: RvPartStatus.pending,
      localStatus: RvLocalStatus.pendingPhotos,
    );
    await drafts.save(draft!);
    message = 'Fotografía capturada y guardada localmente.';
  });

  Future<void> removePhoto(String slot) async {
    if (draft?.isReadOnly != false) return;
    final photos = {...draft!.photos}..remove(slot);
    draft = draft!.copyWith(photos: photos, photosStatus: RvPartStatus.pending);
    await drafts.save(draft!);
    notifyListeners();
  }

  Future<void> synchronize({bool submit = false}) => _run(() async {
    draft = await coordinator.synchronize(draft!, submit: submit);
    message =
        draft!.lastSyncError ??
        (draft!.localStatus == RvLocalStatus.submitted
            ? 'Inspección enviada.'
            : 'Sincronización terminada.');
  });

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
