// Sucht in allen Dateien, die Git verfolgt (bzw. für den Commit vorgemerkt sind), nach Schlüsseln und
// privaten Daten. Teil des Release-Checks – schlägt fehl, bevor so etwas auf GitHub landet.
// Aufruf:  dart run tool/secret_scan.dart
import 'dart:io';

/// Dateien, die nie ins Repo gehören (Signatur-Schlüssel, Datenbanken, Konfigurationen mit Keys).
final _forbiddenFiles = <RegExp>[
  RegExp(r'\.(jks|keystore|p12|pem|db|sqlite|sqlite3)$', caseSensitive: false),
  RegExp(r'(^|/)key\.properties$'),
  RegExp(r'(^|/)local\.properties$'),
  RegExp(r'(^|/)\.env(\..*)?$'),
  RegExp(r'(^|/)google-services\.json$'),
  RegExp(r'(^|/)GoogleService-Info\.plist$'),
  RegExp(r'(^|/)firebase_app_id_file\.json$'),
  RegExp(r'(^|/)(receipt_images|db_backups)/'),
];

/// Inhalte, die nach echten Schlüsseln aussehen.
final _secretPatterns = <String, RegExp>{
  'Anthropic-API-Schlüssel': RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}'),
  'Google-API-Schlüssel': RegExp(r'AIza[0-9A-Za-z_-]{35}'),
  'Privater Schlüssel': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  'GitHub-Token': RegExp(r'(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})'),
  'AWS-Schlüssel': RegExp(r'AKIA[0-9A-Z]{16}'),
  'Slack-Token': RegExp(r'xox[baprs]-[A-Za-z0-9-]{10,}'),
  'Passwort im Klartext': RegExp(r'''(storePassword|keyPassword)\s*=\s*\S+'''),
};

Future<void> main() async {
  final result = await Process.run('git', ['ls-files', '--cached', '-z']);
  if (result.exitCode != 0) {
    stderr.writeln('git ls-files fehlgeschlagen: ${result.stderr}');
    exit(2);
  }
  final files = (result.stdout as String).split('\u0000').where((f) => f.isNotEmpty);
  final findings = <String>[];
  for (final path in files) {
    if (_forbiddenFiles.any((r) => r.hasMatch(path))) {
      findings.add('$path: Datei darf nicht ins Repo');
      continue;
    }
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() > 2 * 1024 * 1024) continue;
    final String text;
    try {
      text = file.readAsStringSync();
    } catch (_) {
      continue; // Binärdatei
    }
    for (final MapEntry(key: name, value: pattern) in _secretPatterns.entries) {
      for (final m in pattern.allMatches(text)) {
        final line = text.substring(0, m.start).split('\n').length;
        findings.add('$path:$line: $name (${m.group(0)!.substring(0, 8)}…)');
      }
    }
  }
  if (findings.isEmpty) {
    stdout.writeln('Keine Schlüssel oder privaten Dateien gefunden.');
    return;
  }
  stderr.writeln('Gefunden – bitte entfernen (bzw. in .gitignore), bevor committet wird:');
  findings.forEach(stderr.writeln);
  exit(1);
}
