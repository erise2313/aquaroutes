# Rebuilds and redeploys the GenTri: WASA Admin portal (Firebase Hosting,
# site "gentri-wasa-admin"). Run from the project root: .\deploy_admin_web.ps1
#
# Same build as deploy_web.ps1, plus --dart-define=PORTAL=admin (see
# lib/screens/auth/auth_gate.dart's _isAdminPortalBuild) -- this build
# skips the public marketing site and only lets wasa_admin sign in.
# Builds into build/web_admin (a separate output dir from the main site's
# build/web) so both builds can coexist.

$envContent = Get-Content .env | Where-Object { $_ -match '=' }
$envMap = @{}
foreach ($line in $envContent) {
    $parts = $line -split '=', 2
    $envMap[$parts[0].Trim()] = $parts[1].Trim()
}

$supabaseUrl = $envMap['SUPABASE_URL']
$supabaseAnonKey = $envMap['SUPABASE_ANON_KEY']

if (-not $supabaseUrl -or -not $supabaseAnonKey) {
    Write-Error "SUPABASE_URL or SUPABASE_ANON_KEY missing from .env"
    exit 1
}

$outputDir = Join-Path (Get-Location).Path "build\web_admin"

& "C:\flutter\flutter\bin\flutter.bat" build web --source-maps `
    --dart-define=SUPABASE_URL=$supabaseUrl `
    --dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey `
    --dart-define=PORTAL=admin `
    -o $outputDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build web failed"
    exit 1
}

# The admin build copies web/ wholesale, including the public site's
# robots.txt ("Allow: /") and its sitemap. Both are wrong here -- the admin
# portal is meant to be undiscoverable, so overwrite one and drop the other.
# firebase.json also sets X-Robots-Tag: noindex on this target; the two work
# together (robots.txt stops the crawl, the header stops the indexing).
#
# Written without a BOM on purpose: PowerShell 5.1's `-Encoding utf8` emits
# one, and a BOM ahead of "User-agent" makes some crawlers treat the first
# line as invalid -- which would quietly undo the Disallow.
$robotsBody = "User-agent: *`nDisallow: /`n"
[System.IO.File]::WriteAllText(
    (Join-Path $outputDir "robots.txt"),
    $robotsBody,
    (New-Object System.Text.UTF8Encoding $false)
)

$adminSitemap = Join-Path $outputDir "sitemap.xml"
if (Test-Path $adminSitemap) { Remove-Item $adminSitemap }

firebase deploy --only hosting:admin
