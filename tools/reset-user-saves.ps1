# Explicit user-requested reset. No backup is created.
$ErrorActionPreference = 'Stop'
$appDataRoot = [Environment]::GetFolderPath('ApplicationData')
if ([string]::IsNullOrWhiteSpace($appDataRoot)) { throw 'The current user application-data directory is unavailable.' }
$saveRoot = [IO.Path]::GetFullPath((Join-Path $appDataRoot 'Godot\app_userdata\gd-pal'))
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectFile = Join-Path $projectRoot 'project.godot'
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf) -or -not (Test-Path -LiteralPath $saveRoot -PathType Container)) { throw 'Unexpected or missing GD Pal directory.' }
if ([IO.File]::ReadAllText($projectFile) -notmatch '(?m)^config/name="gd-pal"\s*$') { throw 'The script must be run from the GD Pal project.' }
if ((Get-Item -LiteralPath $saveRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The save root must not be a link.' }
$projectCommandPattern = '(?i)' + [regex]::Escape($projectRoot).Replace('\\', '[\\/]') + '(?:[\\/\s"]|$)'

# Stop only game instances from this project, leaving the editor open.
$processes = Get-CimInstance Win32_Process | Where-Object {
    (($_.Name -like 'Godot*' -and $_.CommandLine -match $projectCommandPattern) -or
     ($_.Name -eq 'GD-Pal.exe' -and $_.ExecutablePath -and $_.ExecutablePath.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase))) -and
    $_.CommandLine -notmatch '(?:^|\s)--editor(?:\s|$)|(?:^|\s)-e(?:\s|$)'
}
foreach ($process in $processes) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }

$pendingRoot = Join-Path $projectRoot ('_pending_delete\user-saves-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$removed = [Collections.Generic.List[string]]::new()
$pending = [Collections.Generic.List[string]]::new()
function Remove-SaveEntry {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $resolved = [IO.Path]::GetFullPath((Get-Item -LiteralPath $Path -Force).FullName)
    if (-not $resolved.StartsWith($saveRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing a target outside the confirmed save directory.' }
    $relative = [IO.Path]::GetRelativePath($saveRoot, $resolved)
    try {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        $removed.Add($relative)
    } catch {
        # Project instruction: quarantine a failed deletion for manual removal.
        $destination = [IO.Path]::GetFullPath((Join-Path $pendingRoot $relative))
        if (-not $destination.StartsWith($pendingRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected pending-delete path.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $pendingRoot) '.gdignore'), '')
        Move-Item -LiteralPath $resolved -Destination $destination -ErrorAction Stop
        $pending.Add($destination)
    }
}

foreach ($folder in @('conversations', 'memory', 'memory-host', 'objectdb_snapshots')) {
    Remove-SaveEntry (Join-Path $saveRoot $folder)
}
foreach ($entry in Get-ChildItem -LiteralPath $saveRoot -Force -File) {
    if ($entry.Name -like 'pal_session.json*' -or $entry.Name -like 'fish_master.json*' -or $entry.Name -like 'chat_settings.json*') {
        Remove-SaveEntry $entry.FullName
    }
}
$companionRoot = Join-Path $saveRoot 'companion'
$connectionFiles = @('connection.json', 'speech.json', 'credentials')
if (Test-Path -LiteralPath $companionRoot -PathType Container) {
    foreach ($entry in Get-ChildItem -LiteralPath $companionRoot -Force) {
        if ($entry.Name -notin $connectionFiles) { Remove-SaveEntry $entry.FullName }
    }
}

# Keep only global appearance preferences; remove old profile IDs, aliases and drafts.
$uiPath = Join-Path $saveRoot 'ui_state.cfg'
if (Test-Path -LiteralPath $uiPath) {
    $uiText = [IO.File]::ReadAllText($uiPath)
    $appearance = [regex]::Match($uiText, '(?ms)^\[appearance\]\s*\r?\n.*?(?=^\[|\z)')
    if ($appearance.Success) {
        [IO.File]::WriteAllText($uiPath, $appearance.Value.Trim() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    } else { Remove-SaveEntry $uiPath }
}
[PSCustomObject]@{ SaveRoot = $saveRoot; StoppedGameInstances = @($processes).Count; Removed = $removed; PendingManualDelete = $pending; Kept = 'Active model connection settings and appearance only; engine logs/cache are not save data.' } | ConvertTo-Json -Depth 4
