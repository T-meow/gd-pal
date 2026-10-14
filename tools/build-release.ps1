param(
    [string]$GodotPath = $env:GODOT_PATH,
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$')]
    [string]$Version = '0.1.0'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = Join-Path $projectRoot "exports/releases/v$Version"
$stageRoot = Join-Path $projectRoot ('exports/release-staging/' + [guid]::NewGuid().ToString('N'))
$prefix = "GD-Pal-v$Version"
if (Test-Path -LiteralPath $releaseRoot) {
    throw "Release directory already exists: $releaseRoot. Move it aside or choose a new version."
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'release-signing/android-release.json')) -and
    (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH -or -not $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER -or -not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD)) {
    throw 'Release requires a persistent signing certificate. Run tools/setup-android-signing.ps1 once, or set all three GODOT_ANDROID_KEYSTORE_RELEASE_* variables.'
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $projectRoot 'exports/.gdignore'), '')
& node (Join-Path $PSScriptRoot 'prepare-release.mjs') $stageRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the starter pack. Restore portraits from the matching Release first.' }

& (Join-Path $PSScriptRoot 'export-windows.ps1') -GodotPath $GodotPath
& (Join-Path $PSScriptRoot 'export-android.ps1') -GodotPath $GodotPath -Release

Add-Type -AssemblyName System.IO.Compression.FileSystem
$starterRoot = Join-Path $stageRoot 'starter'
[System.IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $stageRoot 'persona'), (Join-Path $starterRoot 'persona.zip'))
New-Item -ItemType Directory -Path $releaseRoot | Out-Null
[System.IO.Compression.ZipFile]::CreateFromDirectory($starterRoot, (Join-Path $releaseRoot "$prefix-Blue-Whale-Starter.zip"))
Copy-Item -LiteralPath (Join-Path $projectRoot 'exports/GD-Pal-Windows-x64.zip') -Destination (Join-Path $releaseRoot "$prefix-Windows-x64.zip")
Copy-Item -LiteralPath (Join-Path $projectRoot 'exports/android/GD-Pal.apk') -Destination (Join-Path $releaseRoot "$prefix-Android.apk")
$checksums = Get-ChildItem -LiteralPath $releaseRoot -File | Sort-Object Name | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.Name
}
[System.IO.File]::WriteAllLines((Join-Path $releaseRoot 'SHA256SUMS.txt'), $checksums, [System.Text.UTF8Encoding]::new($false))
$androidBuild = Get-Content -LiteralPath (Join-Path $projectRoot 'exports/android/build-info.json') -Raw | ConvertFrom-Json
$certificateFingerprint = $androidBuild.signing_certificate_sha256
$notes = @"
# GD Pal v$Version

Windows 透明桌宠与 Android 2D 伙伴。支持流式聊天、图片消息、手动人设与记忆、AI 整理、v1 数据包，以及 Windows ACP Agent。

- Windows：下载 $prefix-Windows-x64.zip，完整解压后启动 GD-Pal.exe，已带 .NET 运行时。
- Android：安装 $prefix-Android.apk，使用固定的项目发布证书正式签名。旧测试签名版需先导出个人数据、卸载后再安装。
- 肥鱼初始包：下载 $prefix-Blue-Whale-Starter.zip，解压后在应用中导入 persona.zip。源码构建者将其中的 assets/ 合并到项目根目录。
- 图片不纳入源码，两个程序均已包含立绘；初始包不含个人聊天、记忆或凭据。
- 自有代码以 MIT 开源，第三方组件和素材的来源及声明随包保留。

模型 API 与 Key 由使用者自行配置。程序画面、桌面窗口交互和 Android 真机效果待人工确认。
使用 SHA256SUMS.txt 核对下载文件。将本目录文件附到同一个 Release，版本标签建议使用 v$Version。

Android 发布证书 SHA-256：$certificateFingerprint
"@
[System.IO.File]::WriteAllText((Join-Path $releaseRoot 'RELEASE_NOTES.md'), $notes, [System.Text.UTF8Encoding]::new($false))
Write-Output "Release files: $releaseRoot"
