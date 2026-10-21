# Release-Check: muss grün sein, bevor die App gebaut oder veröffentlicht wird.
# Aufruf:  powershell -ExecutionPolicy Bypass -File tool/check.ps1 [-Coverage]
param([switch]$Coverage)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

function Step($name, [scriptblock]$cmd) {
    Write-Host "`n==> $name" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FEHLGESCHLAGEN: $name" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Step 'Abhängigkeiten' { flutter pub get }
Step 'Keine Schlüssel oder privaten Daten im Repo' { dart run tool/secret_scan.dart }
Step 'Statische Analyse (auch Hinweise sind Fehler)' { flutter analyze --fatal-infos }
# Höchstens 4 Testdateien parallel – bei voller Kernzahl laufen Widget-Tests sonst in Zeitlimits (wie check.sh)
if ($Coverage) {
    Step 'Tests mit Coverage' { flutter test --coverage --concurrency=4 }
    Write-Host 'Coverage-Bericht: coverage/lcov.info'
} else {
    Step 'Tests' { flutter test --concurrency=4 }
}

Write-Host "`nAlles grün - bereit für den Release." -ForegroundColor Green
