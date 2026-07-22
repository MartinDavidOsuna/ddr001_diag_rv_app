import '../enums/hydrant_list_filter.dart';

class HydrantFilterFacts {
  const HydrantFilterFacts({
    required this.visualAvailable,
    required this.functionalAvailable,
    required this.visualInProgress,
    required this.functionalInProgress,
    required this.visualCompleted,
    required this.functionalCompleted,
    required this.unsynchronized,
    required this.visualPending,
    required this.functionalPending,
    required this.functionalRequired,
    required this.functionalSuspended,
    required this.functionalFailed,
    required this.pendingValidation,
    required this.hasIncidents,
  });

  final bool visualAvailable;
  final bool functionalAvailable;
  final bool visualInProgress;
  final bool functionalInProgress;
  final bool visualCompleted;
  final bool functionalCompleted;
  final bool unsynchronized;
  final bool visualPending;
  final bool functionalPending;
  final bool functionalRequired;
  final bool functionalSuspended;
  final bool functionalFailed;
  final bool pendingValidation;
  final bool hasIncidents;
}

abstract final class HydrantQueryProjection {
  static const visibleFilters = <HydrantListFilter>[
    HydrantListFilter.all,
    HydrantListFilter.visualReport,
    HydrantListFilter.functionalReport,
    HydrantListFilter.inProgress,
    HydrantListFilter.synchronizationPending,
    HydrantListFilter.completed,
  ];

  /// Finalizado significa que existe al menos un RV o RF completado.
  static bool matches(HydrantListFilter filter, HydrantFilterFacts facts) =>
      switch (filter) {
        HydrantListFilter.all => true,
        HydrantListFilter.visualReport => facts.visualAvailable,
        HydrantListFilter.functionalReport => facts.functionalAvailable,
        HydrantListFilter.inProgress =>
          facts.visualInProgress || facts.functionalInProgress,
        HydrantListFilter.synchronizationPending => facts.unsynchronized,
        HydrantListFilter.completed =>
          facts.visualCompleted || facts.functionalCompleted,
        HydrantListFilter.visualPending => facts.visualPending,
        HydrantListFilter.visualInProgress => facts.visualInProgress,
        HydrantListFilter.visualCompleted => facts.visualCompleted,
        HydrantListFilter.functionalPending => facts.functionalPending,
        HydrantListFilter.functionalInProgress => facts.functionalInProgress,
        HydrantListFilter.functionalCompleted => facts.functionalCompleted,
        HydrantListFilter.functionalRequired => facts.functionalRequired,
        HydrantListFilter.functionalSuspended => facts.functionalSuspended,
        HydrantListFilter.functionalFailed => facts.functionalFailed,
        HydrantListFilter.pendingValidation => facts.pendingValidation,
        HydrantListFilter.incidents => facts.hasIncidents,
      };
}
