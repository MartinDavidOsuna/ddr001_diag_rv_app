class FieldRegistration {
  const FieldRegistration({
    required this.name,
    required this.email,
    required this.phone,
    required this.crew,
  });

  final String name, email, phone, crew;

  static String normalizeSpaces(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  String get normalizedName => normalizeSpaces(name);
  String get normalizedEmail => email.trim().toLowerCase();
  String get normalizedCrew => normalizeSpaces(crew).toUpperCase();

  String? validate() {
    if (normalizedName.length < 3) return 'Ingresa un nombre completo válido.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      return 'Ingresa un correo electrónico válido.';
    }
    if (!RegExp(r'^\d{10}$').hasMatch(phone.trim())) {
      return 'El teléfono debe contener exactamente 10 dígitos.';
    }
    if (normalizedCrew.isEmpty) return 'Ingresa la cuadrilla.';
    return null;
  }
}

class FieldSession {
  const FieldSession({
    required this.sessionId,
    required this.accessToken,
    required this.refreshToken,
    required this.installationId,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.crew = '',
    this.startedAt,
  });

  final String sessionId, accessToken, refreshToken, installationId;
  final String name, email, phone, crew;
  final DateTime? startedAt;

  FieldSession copyWith({String? accessToken, String? refreshToken}) =>
      FieldSession(
        sessionId: sessionId,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        installationId: installationId,
        name: name,
        email: email,
        phone: phone,
        crew: crew,
        startedAt: startedAt,
      );
}
