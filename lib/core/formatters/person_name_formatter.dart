String formatPersonName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (normalized.isEmpty) return '';
  return normalized
      .split(' ')
      .map(
        (word) => word.splitMapJoin(
          RegExp("[-']"),
          onMatch: (match) => match.group(0)!,
          onNonMatch: _capitalize,
        ),
      )
      .join(' ');
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';
}
