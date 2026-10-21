#!/usr/bin/env sh
# Release-Check: muss grün sein, bevor die App gebaut oder veröffentlicht wird.
# Aufruf:  sh tool/check.sh [--coverage]
# Tests laufen mit begrenzter Parallelität: bei voller Kernzahl laufen Widget-Tests sonst in Zeitlimits.
set -e
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

step 'Abhängigkeiten'
flutter pub get

step 'Keine Schlüssel oder privaten Daten im Repo'
dart run tool/secret_scan.dart

step 'Statische Analyse (auch Hinweise sind Fehler)'
flutter analyze --fatal-infos

if [ "$1" = "--coverage" ]; then
  step 'Tests mit Coverage'
  flutter test --coverage --concurrency=4
  echo 'Coverage-Bericht: coverage/lcov.info'
else
  step 'Tests'
  flutter test --concurrency=4
fi

printf '\nAlles grün - bereit für den Release.\n'
