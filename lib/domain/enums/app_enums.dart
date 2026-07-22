enum InspectionType { f02A, f02B }

enum InspectionStatus {
  pending,
  inProgress,
  completed,
  scheduled,
  notRequired,
  returned,
  validated,
}

enum SyncStatus { local, pending, synced, returned, validated }

enum PriorityLevel { low, medium, high }

enum AccessType { vehicle, walking, both }

enum HydrantSource { assigned, unassigned, fieldCreated }

enum ConnectivityState { online, offline }

enum UpdateStatus { current, optional, required, unavailable }
