/// Fehler mit einer Meldung, die direkt angezeigt werden kann (ohne „Exception: …“).
class UserFacingException implements Exception {
  final String message;
  const UserFacingException(this.message);

  @override
  String toString() => message;
}
