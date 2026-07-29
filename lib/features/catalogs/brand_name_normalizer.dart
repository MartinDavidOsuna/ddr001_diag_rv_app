/// Produces the canonical value used for brand persistence, display and
/// duplicate resolution.
///
/// Internal punctuation such as the hyphen in `CLA-VAL` is intentionally
/// preserved. Only surrounding whitespace, repeated whitespace and casing are
/// normalized.
String normalizeBrandName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  if (normalized.isEmpty) {
    throw const FormatException('Nombre de marca requerido.');
  }
  return normalized;
}
