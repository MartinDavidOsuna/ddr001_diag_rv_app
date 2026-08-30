enum FilterElementState { present, absent, undetermined }

class FilterElementSelection {
  const FilterElementSelection(this.state, {this.undefinedReason});
  final FilterElementState state;
  final String? undefinedReason;
  String get wireState =>
      state == FilterElementState.undetermined ? 'undefined' : state.name;
  String get displayValue => switch (state) {
    FilterElementState.present => 'Sí',
    FilterElementState.absent => 'No',
    FilterElementState.undetermined => 'Indefinido',
  };
  bool get isComplete =>
      state != FilterElementState.undetermined ||
      (undefinedReason?.trim().length ?? 0) >= 10;
  Map<String, dynamic> toJson() => {
    'state': wireState,
    'displayValue': displayValue,
    'reason': state == FilterElementState.undetermined
        ? undefinedReason?.trim()
        : null,
  };
  factory FilterElementSelection.fromValue(Object? value) {
    if (value == true) {
      return const FilterElementSelection(FilterElementState.present);
    }
    if (value == false) {
      return const FilterElementSelection(FilterElementState.absent);
    }
    final map = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return FilterElementSelection(
      map['state'] == 'present'
          ? FilterElementState.present
          : map['state'] == 'absent'
          ? FilterElementState.absent
          : FilterElementState.undetermined,
      undefinedReason: map['reason']?.toString(),
    );
  }
}
