param(
    [string]$GodotPath = $env:GODOT_PATH,
    [string]$PawnIOBundlePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pawnIOFiles = @('PawnIO_setup.exe', 'COPYING', 'README.md', 'PawnIO-2.2.0-source.zip')
if ($PawnIOBundlePath) {
    $PawnIOBundlePath = (Resolve-Path -LiteralPath $PawnIOBundlePath).Path
    foreach ($name in $pawnIOFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $PawnIOBundlePath $name) -PathType Leaf)) {
            throw "The optional PawnIO bundle must include the official installer, license and complete corresponding sources. Missing: $name"
        }
    }
    $pawnIOInstaller = Join-Path $PawnIOBundlePath 'PawnIO_setup.exe'
    if ((Get-FileHash -LiteralPath $pawnIOInstaller -Algorithm SHA256).Hash -ne '1F519A22E47187F70A1379A48CA604981C4FCF694F4E65B734AAA74A9FBA3032' -or
        (Get-AuthenticodeSignature -LiteralPath $pawnIOInstaller).Status -ne 'Valid') {
        throw 'PawnIO must be the unmodified, signed official 2.2.0 installer.'
    }
}
if (-not $GodotPath) {
    $GodotPath = 'D:/GameEngines/Godot_v4.8-dev7_mono_win64/Godot_v4.8-dev7_mono_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Pass -GodotPath with the Godot 4.8 dev7 .NET console executable.' }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
# The console wrapper can wait for a key after a hidden child exits. Launch the
# engine directly while redirecting its output to the same build logs.
$enginePath = $GodotPath -replace '_console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $enginePath)) { $enginePath = $GodotPath }
$exportRoot = Join-Path $projectRoot 'exports'
$packageRoot = Join-Path $exportRoot 'windows'
$pawnIODestination = Join-Path $packageRoot 'components/PawnIO'
if (-not $PawnIOBundlePath -and (Test-Path -LiteralPath $pawnIODestination)) {
    throw 'The export folder contains a previous optional PawnIO component. Pass -PawnIOBundlePath again or remove components/PawnIO before exporting without it.'
}
$logRoot = Join-Path $projectRoot '.godot/checks'
New-Item -ItemType Directory -Path $packageRoot, $logRoot -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $exportRoot '.gdignore'), '')
$executable = Join-Path $packageRoot 'GD-Pal.exe'
$stdoutLog = Join-Path $logRoot 'windows-export.log'
$stderrLog = Join-Path $logRoot 'windows-export-errors.log'
$arguments = @('--headless', '--path', ('"' + $projectRoot + '"'), '--export-release', '"Windows Desktop"', ('"' + $executable + '"'))
$job = Start-Process -FilePath $enginePath -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
$processHandle = $job.Handle
$job.WaitForExit()
$exportErrors = Select-String -Path $stdoutLog, $stderrLog -Pattern 'SCRIPT ERROR:|Parse Error:|(^|\s)ERROR:'
if ($job.ExitCode -ne 0 -or $exportErrors) {
    throw "Windows export failed (exit $($job.ExitCode)). Inspect $stdoutLog and $stderrLog."
}
foreach ($name in @('GD-Pal.exe', 'GD-Pal.pck', 'data_gd-pal_windows_x86_64/gd-pal.dll', 'data_gd-pal_windows_x86_64/coreclr.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $name))) { throw "Missing exported dependency: $name" }
}
$sensorOutput = Join-Path $packageRoot 'monitor-helper'
dotnet publish (Join-Path $projectRoot 'tools/monitor-helper/GdPal.Sensors.csproj') -c Release -r win-x64 --self-contained true -o $sensorOutput
if ($LASTEXITCODE -ne 0) { throw 'Performance sensor helper publish failed.' }
if ($PawnIOBundlePath) {
    New-Item -ItemType Directory -Path $pawnIODestination -Force | Out-Null
    foreach ($name in $pawnIOFiles) { Copy-Item -LiteralPath (Join-Path $PawnIOBundlePath $name) -Destination $pawnIODestination -Force }
}
$motionNotices = Join-Path $packageRoot 'licenses/motions'
New-Item -ItemType Directory -Path $motionNotices -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/motions/npc/manifest.json') -Destination $motionNotices -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/motions/npc/licenses') -Destination $motionNotices -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/assets.md') -Destination (Join-Path $packageRoot 'motions.md') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE'), (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses/yumo') -Destination (Join-Path $packageRoot 'licenses') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses/monitoring') -Destination (Join-Path $packageRoot 'licenses') -Recurse -Force
foreach ($addon in @('vrm', 'Godot-MToon-Shader', 'godot_mcp')) {
    $noticeRoot = Join-Path $packageRoot "addons/$addon"
    New-Item -ItemType Directory -Path $noticeRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot "addons/$addon/LICENSE") -Destination $noticeRoot -Force
}
$instructions = @'
GD Pal - Windows x64

双击 GD-Pal.exe 启动。请保留整个文件夹，不要单独移动 EXE。
已随包附带 .NET 运行时、肥鱼立绘、角色动作与轻量聊天服务。

大厅：互动 → 动作分类。
桌面：菜单 → 播放动作。
单次动作结束后返回待机；循环和姿势可用“返回待机”结束。
默认使用肥鱼 2D 角色；切换到 DS 3D 后可使用动作库与窗口／任务栏上沿趴靠，见 motions.md。

关闭大厅会收起到系统托盘，桌宠和聊天继续。
大厅“性能”页或桌宠工具栏“性能”可查看本机占用、温度与风扇。
部分温度／主板风扇需要在传感器设置中启用高级读取，并具备 PawnIO 驱动支持。
点击“安装温度组件”可使用随包安装器，未附带时从官方获取；安装需管理员授权。
换电脑后需在新电脑安装一次驱动。选择过的旧设备不可用时会自动匹配当前设备。
极简模式右键可选择亮色／暗色玻璃，监控设置可调整背景透明度。
单击托盘图标恢复大厅，右键菜单可打开、收起或退出。
伙伴档案可手动编辑人设、记忆和世界设定。AI 整理的候选条目需确认后才会加入。
肥鱼初始包中的 persona.zip 可在伙伴档案的“导入导出”中导入。

窗口画面、透明穿透、拖动和动作观感请手动测试。
角色及聊天数据使用本机原有 GD Pal 用户目录；聊天连接需自行配置。
'@
[System.IO.File]::WriteAllText((Join-Path $packageRoot 'README.txt'), $instructions, [System.Text.UTF8Encoding]::new($true))
$buildInfo = [ordered]@{
    built_at = [DateTimeOffset]::Now.ToString('o')
    version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable).ProductVersion
    platform = 'Windows x64'
    engine = (& $enginePath --version | Out-String).Trim()
    configuration = 'ExportRelease'
    pawnio_bundled = [bool]$PawnIOBundlePath
    motion_count = (Get-Content -LiteralPath (Join-Path $projectRoot 'assets/motions/npc/manifest.json') -Raw | ConvertFrom-Json).totals.clips
    exe_sha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
    pack_sha256 = (Get-FileHash -LiteralPath (Join-Path $packageRoot 'GD-Pal.pck') -Algorithm SHA256).Hash
}
$buildInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot 'build-info.json') -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $exportRoot 'GD-Pal-Windows-x64.zip'
$temporaryArchive = Join-Path $exportRoot ('GD-Pal-' + [guid]::NewGuid().ToString('N') + '.zip')
[System.IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $temporaryArchive, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
Write-Output "Windows build: $executable"
Write-Output "ZIP package: $archive"
