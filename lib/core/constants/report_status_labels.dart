import '../../domain/functional/functional_models.dart';
import '../../domain/inspections/visual_inspection.dart';

abstract final class ReportStatusLabels {
  static String value(String key) =>
      const {
        'draft': 'Borrador',
        'ready': 'Listo',
        'inProgress': 'En proceso',
        'paused': 'Pausado',
        'suspended': 'Suspendido',
        'completed': 'Finalizado',
        'cancelled': 'Cancelado',
        'requiresRepeat': 'Requiere repetición',
        'pendingReview': 'Pendiente de revisión',
        'synced': 'Sincronizado',
      }[key] ??
      'Estado no disponible';
}

abstract final class ReportResultLabels {
  static String value(String key) =>
      const {
        'observations': 'Con observaciones',
        'approved': 'Aprobado',
        'approvedWithObservations': 'Aprobado con observaciones',
        'partial': 'Funcionamiento parcial',
        'requiresAdjustment': 'Requiere ajuste',
        'requiresRepair': 'Requiere reparación',
        'requiresReplacement': 'Requiere reemplazo',
        'incomplete': 'Incompleto',
        'notEvaluable': 'No evaluable',
        'suspended': 'Suspendido',
        'operational': 'Operativo',
        'nonOperational': 'No operativo',
        'critical': 'Riesgo crítico',
      }[key] ??
      'Resultado no disponible';

  static String visual(FinalClassification? result) =>
      result == null ? 'Sin clasificación' : value(result.name);

  static String functional(FunctionalOverallResult result) =>
      value(result.name);
}
