# Builds the gomobile android binding (gobackend.aar) from go_backend/
# and drops it into android/app/libs/ so the Kotlin bridge can call Go.
#
# Requirements: Go >= 1.26.5 (see go_backend/go.mod), ANDROID_NDK_HOME set.
# Android-only (arm/arm64 mirror the upstream matrix; add amd64 for emulators).
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/build_go_backend.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$goDir = Join-Path $root "go_backend"
$outDir = Join-Path $root "android\app\libs"
$aarPath = Join-Path $outDir "gobackend.aar"

if (-not $env:ANDROID_NDK_HOME) {
    Write-Error "ANDROID_NDK_HOME is not set. Point it at your Android NDK (e.g. %LOCALAPPDATA%\Android\Sdk\ndk\<version>)."
}

Push-Location $goDir
try {
go mod download
    if (-not (Test-Path (Join-Path $env:GOPATH "bin\gomobile.exe")) -and
        -not (Get-Command gomobile -ErrorAction SilentlyContinue)) {
        go install golang.org/x/mobile/cmd/gomobile
    }
    gomobile init
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Push-Location $goDir
try {
    # CGO_ENABLED must be 1 for gomobile; the Go pin in go.mod is inherited.
    gomobile bind `
        -target="android/arm,android/arm64" `
        -androidapi 24 `
        -o $aarPath `
        .
} finally {
    Pop-Location
}

Write-Host "`nBuilt $aarPath`n"
Write-Host "Next: flutter pub get && flutter run (the AAR is picked up automatically)."