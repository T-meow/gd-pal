param(
    [string]$GodotPath = $env:GODOT_PATH,
    [switch]$Release,
    [string]$SigningConfig
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) { $GodotPath = 'D:/GameEngines/Godot_v4.8-dev7_mono_win64/Godot_v4.8-dev7_mono_win64.exe' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Pass -GodotPath with the Godot 4.8 dev7 .NET executable.' }
$enginePath = (Resolve-Path -LiteralPath $GodotPath).Path -replace '_console\.exe$', '.exe'
$signingNames = @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')
$signingValues = @{}
if ($Release) {
    foreach ($name in $signingNames) { $signingValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    $configuredCount = @($signingNames | Where-Object { $signingValues[$_] }).Count
    if ($SigningConfig -or $configuredCount -eq 0) {
        if (-not $SigningConfig) { $SigningConfig = Join-Path $projectRoot 'release-signing/android-release.json' }
        if (-not (Test-Path -LiteralPath $SigningConfig)) { throw 'Release signing is missing. Run tools/setup-android-signing.ps1 once, or set all three GODOT_ANDROID_KEYSTORE_RELEASE_* variables.' }
        $SigningConfig = (Resolve-Path -LiteralPath $SigningConfig).Path
        $signing = Get-Content -LiteralPath $SigningConfig -Raw | ConvertFrom-Json
        if (-not $signing.keystore -or -not $signing.alias -or -not $signing.password) { throw 'Signing configuration must contain keystore, alias and password.' }
        $signingValues[$signingNames[0]] = if ([IO.Path]::IsPathRooted($signing.keystore)) { $signing.keystore } else { Join-Path (Split-Path -Parent $SigningConfig) $signing.keystore }
        $signingValues[$signingNames[1]] = $signing.alias
        $signingValues[$signingNames[2]] = $signing.password
    } elseif ($configuredCount -ne 3) {
        throw 'Set all three GODOT_ANDROID_KEYSTORE_RELEASE_* variables together, or clear them to use the local signing configuration.'
    }
    if (-not (Test-Path -LiteralPath $signingValues[$signingNames[0]])) { throw 'The release keystore does not exist.' }
    $androidSdkPath = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (-not $androidSdkPath) { throw 'Set ANDROID_HOME or ANDROID_SDK_ROOT so the release APK signature can be verified.' }
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $androidSdkPath 'build-tools') -Directory | Sort-Object Name -Descending | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe'))
    } | Select-Object -First 1
    if (-not $buildTools) { throw 'Android SDK build-tools with apksigner and aapt are required to verify a release APK.' }
}
$packageRoot = Join-Path $projectRoot 'exports/android'
$logRoot = Join-Path $projectRoot '.godot/checks'
New-Item -ItemType Directory -Path $packageRoot, $logRoot -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $projectRoot 'exports/.gdignore'), '')
$apk = Join-Path $packageRoot ('GD-Pal' + $(if ($Release) { '' } else { '-debug' }) + '.apk')
$log = Join-Path $logRoot 'android-export.log'
$errors = Join-Path $logRoot 'android-export-errors.log'
$mode = if ($Release) { '--export-release' } else { '--export-debug' }
$arguments = @('--headless', '--path', ('"' + $projectRoot + '"'), $mode, 'Android', ('"' + $apk + '"'))
$savedSigning = @{}
try {
    if ($Release) {
        foreach ($name in $signingNames) {
            $savedSigning[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $signingValues[$name], 'Process')
        }
    }
    $job = Start-Process -FilePath $enginePath -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $errors
    $processHandle = $job.Handle
    $job.WaitForExit()
} finally {
    foreach ($name in $savedSigning.Keys) { [Environment]::SetEnvironmentVariable($name, $savedSigning[$name], 'Process') }
}
# Godot 4.7.2 may emit this editor-teardown message after a successful signed export.
$reportedErrors = Select-String -Path $log, $errors -Pattern 'SCRIPT ERROR:|Parse Error:|(^|\s)ERROR:' | Where-Object { $_.Line -notmatch '^ERROR: EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"\.$' }
if ($job.ExitCode -ne 0 -or $reportedErrors) {
    throw "Android export failed. Inspect $log and $errors. Install matching .NET Android export templates, .NET 10 and configure Java/Android SDK in Godot editor settings."
}
if (-not (Test-Path -LiteralPath $apk)) { throw 'Godot did not produce an APK.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($apk)
try {
    foreach ($entry in @('AndroidManifest.xml')) {
        if (-not $archive.GetEntry($entry)) { throw "APK is missing $entry" }
    }
} finally { $archive.Dispose() }
$certificateSha256 = ''
if ($Release) {
    $signatureLog = Join-Path $logRoot 'android-signature.log'
    $signature = & (Join-Path $buildTools.FullName 'apksigner.bat') verify --verbose --print-certs $apk 2>&1
    $signatureExit = $LASTEXITCODE
    $signature | Set-Content -LiteralPath $signatureLog -Encoding UTF8
    if ($signatureExit -ne 0) { throw "Android release signature verification failed. Inspect $signatureLog." }
    $certificateMatch = [regex]::Match(($signature -join "`n"), 'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})')
    if (-not $certificateMatch.Success) { throw 'The signed APK did not report a signing certificate fingerprint.' }
    $certificateSha256 = $certificateMatch.Groups[1].Value.ToLowerInvariant()
    $badging = & (Join-Path $buildTools.FullName 'aapt.exe') dump badging $apk 2>&1
    if ($LASTEXITCODE -ne 0 -or ($badging | Select-String -Pattern '^application-debuggable')) { throw 'The release APK must have a readable, non-debuggable Android manifest.' }
}
[ordered]@{ built_at = [DateTimeOffset]::Now.ToString('o'); platform = 'Android ARM64 + x86_64'; configuration = $(if ($Release) {'release'} else {'debug'}); signing_certificate_sha256 = $certificateSha256; sha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot 'build-info.json') -Encoding UTF8
Write-Output "Android APK: $apk"
