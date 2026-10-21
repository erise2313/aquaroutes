# Builds the release APKs (one per phone type) for an environment.
# Run from the project root:
#   .\build_apk.ps1                            # the environment in .env
#   .\build_apk.ps1 -EnvFile .env.handover     # another environment
#
# On a phone the app reads its Supabase settings from the .env file bundled
# into the APK (lib/main.dart), so for another environment that file is
# swapped in for the build and the original is always put back. The site
# addresses (station share links, "Go to Admin Portal") are build settings.
# Output: build\app\outputs\flutter-apk\app-<abi>-release.apk

param(
    [string]$EnvFile = ".env"
)

if (-not (Test-Path $EnvFile)) {
    Write-Error "$EnvFile not found"
    exit 1
}
$envMap = @{}
foreach ($line in (Get-Content $EnvFile | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' })) {
    $parts = $line -split '=', 2
    $envMap[$parts[0].Trim()] = $parts[1].Trim()
}
if (-not $envMap['SUPABASE_URL'] -or -not $envMap['SUPABASE_ANON_KEY']) {
    Write-Error "SUPABASE_URL or SUPABASE_ANON_KEY missing from $EnvFile"
    exit 1
}

$defines = @()
foreach ($key in @('PUBLIC_SITE_URL', 'ADMIN_PORTAL_URL', 'MAPTILER_KEY')) {
    if ($envMap[$key]) { $defines += "--dart-define=$key=$($envMap[$key])" }
}

$swapped = (Resolve-Path $EnvFile).Path -ne (Resolve-Path .env -ErrorAction SilentlyContinue).Path
$backup = ".env.build-backup"
try {
    if ($swapped) {
        if (Test-Path .env) { Copy-Item .env $backup -Force }
        Copy-Item $EnvFile .env -Force
    }
    & "C:\flutter\flutter\bin\flutter.bat" build apk --release --split-per-abi @defines
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
}
finally {
    if ($swapped) {
        if (Test-Path $backup) { Move-Item $backup .env -Force } else { Remove-Item .env -ErrorAction SilentlyContinue }
    }
}
