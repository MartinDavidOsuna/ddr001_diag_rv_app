import '../enums/hydrant_list_filter.dart';

enum HydrantFilterRequestSource { home, local }

class HydrantFilterRequest {
  const HydrantFilterRequest({
    required this.id,
    required this.filter,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final HydrantListFilter filter;
  final HydrantFilterRequestSource source;
  final DateTime createdAt;
}
