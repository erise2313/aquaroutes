# Rebuilds and redeploys the GenTri: WASA website (Firebase Hosting).
# Run from the project root: .\deploy_web.ps1
#
# Reads SUPABASE_URL/SUPABASE_ANON_KEY from .env and passes them as
# --dart-define values -- required for web release builds, since
# flutter_dotenv's runtime asset loading is unreliable in optimized web
# builds (see the comment in lib/main.dart for why).

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

& "C:\flutter\flutter\bin\flutter.bat" build web --source-maps `
    --dart-define=SUPABASE_URL=$supabaseUrl `
    --dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey

if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build web failed"
    exit 1
}

firebase deploy --only hosting
