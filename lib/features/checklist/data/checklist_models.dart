class ChecklistDependency {
  const ChecklistDependency({
    required this.parentCode,
    required this.operator,
    required this.value,
  });
  final String parentCode, operator;
  final Object? value;

  factory ChecklistDependency.fromJson(Map<String, dynamic> json) =>
      ChecklistDependency(
        parentCode: json['parentCode'] as String,
        operator: json['operator'] as String,
        value: json['value'],
      );
  Map<String, dynamic> toJson() => {
    'parentCode': parentCode,
    'operator': operator,
    'value': value,
  };
}

class ChecklistItemDefinition {
  const ChecklistItemDefinition({
    required this.id,
    required this.code,
    required this.label,
    required this.type,
    required this.required,
    required this.order,
    this.unit,
    this.options = const [],
    this.dependency,
    this.photoSlot,
    this.helpText,
  });
  final String id, code, label, type;
  final bool required;
  final int order;
  final String? unit, photoSlot, helpText;
  final List<Object?> options;
  final ChecklistDependency? dependency;

  factory ChecklistItemDefinition.fromJson(Map<String, dynamic> json) =>
      ChecklistItemDefinition(
        id: json['id'] as String,
        code: json['code'] as String,
        label: json['label'] as String,
        type: json['type'] as String,
        required: json['required'] as bool? ?? false,
        order: (json['order'] as num).toInt(),
        unit: json['unit'] as String?,
        options: List<Object?>.from(json['options'] as List? ?? const []),
        dependency: json['dependency'] is Map
            ? ChecklistDependency.fromJson(
                Map<String, dynamic>.from(json['dependency'] as Map),
              )
            : null,
        photoSlot: json['photoSlot'] as String?,
        helpText: json['helpText'] as String?,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'label': label,
    'type': type,
    'required': required,
    'order': order,
    'unit': unit,
    'options': options,
    'dependency': dependency?.toJson(),
    'photoSlot': photoSlot,
    'helpText': helpText,
  };
}

class ChecklistSectionDefinition {
  const ChecklistSectionDefinition({
    required this.id,
    required this.code,
    required this.title,
    required this.order,
    required this.items,
  });
  final String id, code, title;
  final int order;
  final List<ChecklistItemDefinition> items;
  factory ChecklistSectionDefinition.fromJson(Map<String, dynamic> json) =>
      ChecklistSectionDefinition(
        id: json['id'] as String,
        code: json['code'] as String,
        title: json['title'] as String,
        order: (json['order'] as num).toInt(),
        items: (json['items'] as List)
            .whereType<Map>()
            .map(
              (e) => ChecklistItemDefinition.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'title': title,
    'order': order,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class DynamicChecklist {
  const DynamicChecklist({
    required this.id,
    required this.code,
    required this.version,
    required this.title,
    required this.sections,
    required this.etag,
    required this.cachedAt,
    this.publishedAt,
  });
  final String id, code, title, etag;
  final int version;
  final DateTime? publishedAt;
  final DateTime cachedAt;
  final List<ChecklistSectionDefinition> sections;

  factory DynamicChecklist.fromApi(
    Map<String, dynamic> json, {
    required String etag,
    required DateTime cachedAt,
  }) => DynamicChecklist(
    id: json['id'] as String,
    code: json['code'] as String,
    version: (json['version'] as num).toInt(),
    title: json['title'] as String,
    publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
    sections: (json['sections'] as List)
        .whereType<Map>()
        .map(
          (e) =>
              ChecklistSectionDefinition.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList(),
    etag: etag,
    cachedAt: cachedAt,
  );
  factory DynamicChecklist.fromJson(Map<String, dynamic> json) =>
      DynamicChecklist.fromApi(
        json,
        etag: json['etag'] as String,
        cachedAt: DateTime.parse(json['cachedAt'] as String),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'version': version,
    'title': title,
    'publishedAt': publishedAt?.toUtc().toIso8601String(),
    'sections': sections.map((e) => e.toJson()).toList(),
    'etag': etag,
    'cachedAt': cachedAt.toUtc().toIso8601String(),
  };
}
