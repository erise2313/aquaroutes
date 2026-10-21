# Rebuilds and redeploys the GenTri: WASA website (Firebase Hosting).
# Run from the project root: .\deploy_web.ps1
#
# Reads SUPABASE_URL/SUPABASE_ANON_KEY from .env and passes them as
# --dart-define values -- required for web release builds, since
# flutter_dotenv's runtime asset loading is unreliable in optimized web
# builds (see the comment in lib/main.dart for why).
#
# Another environment (another Supabase project and Firebase account):
#   .\deploy_web.ps1 -EnvFile .env.handover -Project gentriwasa -Account gentriwasawebapp@gmail.com

param(
    [string]$EnvFile = ".env",
    [string]$Project = "",
    [string]$Account = ""
)

if (-not (Test-Path $EnvFile)) {
    Write-Error "$EnvFile not found"
    exit 1
}
$envContent = Get-Content $EnvFile | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' }
$envMap = @{}
foreach ($line in $envContent) {
    $parts = $line -split '=', 2
    $envMap[$parts[0].Trim()] = $parts[1].Trim()
}

$supabaseUrl = $envMap['SUPABASE_URL']
$supabaseAnonKey = $envMap['SUPABASE_ANON_KEY']

if (-not $supabaseUrl -or -not $supabaseAnonKey) {
    Write-Error "SUPABASE_URL or SUPABASE_ANON_KEY missing from $EnvFile"
    exit 1
}

# Optional: the client organisation's MapTiler key. Without it the maps use
# OpenStreetMap's tiles, which is fine for testing (lib/widgets/app_map_tiles.dart).
$mapDefine = @()
if ($envMap['MAPTILER_KEY']) { $mapDefine = @("--dart-define=MAPTILER_KEY=$($envMap['MAPTILER_KEY'])") }

# Where this site points a wasa_admin who signs in here (auth_gate.dart).
# Defaulted in code, but passed explicitly so .env is the single place an
# environment switch has to touch.
$adminUrlDefine = @()
if ($envMap['ADMIN_PORTAL_URL']) { $adminUrlDefine = @("--dart-define=ADMIN_PORTAL_URL=$($envMap['ADMIN_PORTAL_URL'])") }

# This site's own address, for station QR codes and share links
# (lib/widgets/station_share_card.dart).
$publicSiteUrl = $envMap['PUBLIC_SITE_URL']
$siteDefine = @()
if ($publicSiteUrl) { $siteDefine = @("--dart-define=PUBLIC_SITE_URL=$publicSiteUrl") }

& "C:\flutter\flutter\bin\flutter.bat" build web --source-maps `
    --dart-define=SUPABASE_URL=$supabaseUrl `
    --dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey `
    @mapDefine @adminUrlDefine @siteDefine

if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build web failed"
    exit 1
}

# The original address is written into web/ (page tags, robots.txt,
# sitemap). Point the built copies at this environment's address instead.
$outputDir = Join-Path (Get-Location).Path "build\web"
$originalSite = "https://gentri-wasa.web.app"
if ($publicSiteUrl -and $publicSiteUrl -ne $originalSite) {
    foreach ($name in @("index.html", "robots.txt", "sitemap.xml")) {
        $path = Join-Path $outputDir $name
        if (Test-Path $path) {
            $text = [System.IO.File]::ReadAllText($path)
            [System.IO.File]::WriteAllText($path, $text.Replace($originalSite, $publicSiteUrl), (New-Object System.Text.UTF8Encoding $false))
        }
    }
}

$deployArgs = @()
if ($Project) { $deployArgs += @("--project", $Project) }
if ($Account) { $deployArgs += @("--account", $Account) }
firebase deploy --only hosting:main @deployArgs
