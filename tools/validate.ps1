param(
    [string]$GodotPath = $env:GODOT_PATH,
    [ValidateRange(30, 1800)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) { $GodotPath = 'D:/GameEngines/Godot_v4.8-beta1_mono_win64/Godot_v4.8-beta1_mono_win64_console.exe' }
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Pass -GodotPath with the Godot 4.8 beta1 .NET executable, or set GODOT_PATH.'
}
$enginePath = (Resolve-Path -LiteralPath $GodotPath).Path -replace '_console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $enginePath)) { $enginePath = (Resolve-Path -LiteralPath $GodotPath).Path }
$logRoot = Join-Path $projectRoot ('.godot/checks/validation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Invoke-Checked {
    param([string]$File, [string[]]$ArgumentList, [string]$Name, [string]$SuccessMarker = '')
    Write-Output "Checking $Name..."
    $stdout = Join-Path $logRoot ($Name + '.log')
    $stderr = Join-Path $logRoot ($Name + '-errors.log')
    # These arguments are fixed flags or Windows paths, which cannot contain quotes.
    $quoted = @($ArgumentList | ForEach-Object { '"' + $_ + '"' })
    $job = Start-Process -FilePath $File -ArgumentList $quoted -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $processHandle = $job.Handle
    try {
        if (-not $job.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $job.Id -Force
            throw "$Name timed out. Logs: $logRoot"
        }
        $output = [System.IO.File]::ReadAllText($stdout) + [System.IO.File]::ReadAllText($stderr)
        if ($job.ExitCode -ne 0 -or $output -match '(?m)SCRIPT ERROR:|Parse Error:|(^|\s)ERROR:' -or ($SuccessMarker -and -not $output.Contains($SuccessMarker))) {
            Write-Output $output
            throw "$Name failed (exit $($job.ExitCode)). Logs: $logRoot"
        }
        if ($SuccessMarker) { Write-Output ($output -split '\r?\n' | Where-Object { $_.StartsWith('GD_PAL_CHECK:') }) }
    } finally {
        if (-not $job.HasExited) { Stop-Process -Id $job.Id -Force }
        $job.Dispose()
    }
}

# One maintained test script. Godot's temporary entry point and all data stay in .godot/.
$runtimeScript = @'
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("GD_PAL_TEST") != "1":
		push_error("Validation requires isolated test data")
		quit(1)
		return
	create_timer(90).timeout.connect(func() -> void: push_error("Runtime validation timed out"); quit(1))
	if not PalUi.is_mobile():
		for directory: String in ["res://scripts", "res://addons", "res://scenes", "res://assets", "res://platform"]:
			_load_resources(directory)
	_check_storage()
	await _check_app()
	print("GD_PAL_CHECK: %s (%s, %d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", "mobile" if PalUi.is_mobile() else "desktop", _checks, _failures])
	quit(0 if _failures == 0 else 1)

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)

func _load_resources(directory: String) -> void:
	if FileAccess.file_exists(directory.path_join(".gdignore")):
		return
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension() in ["gd", "tscn", "tres", "res"]:
			var path := directory.path_join(file)
			var resource := load(path)
			_expect(resource != null and (not resource is GDScript or resource.can_instantiate()), "Load " + path)
	for child: String in DirAccess.get_directories_at(directory):
		_load_resources(directory.path_join(child))

func _check_storage() -> void:
	var path := "user://validation-session.json"
	var profile := PalProfile.new()
	profile.profile_id = "validation"
	profile.display_name = "Saved companion"
	profile.outfit = "nightdress"
	profile.outfit_override = true
	profile.desktop_mode = "call"
	var profiles: Array[PalProfile] = [profile]
	_expect(PalSessionStore.save_profiles(profiles, path) == OK, "Save v1 appearance")
	var restored := PalSessionStore.load_profiles(path)
	_expect(restored.size() == 1, "Reload the saved companion")
	if restored.size() == 1:
		_expect(restored[0].profile_id == profile.profile_id and restored[0].outfit == "nightdress" and restored[0].outfit_override and restored[0].desktop_mode == "call", "Appearance and identity survive reload")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(stored.get("schema_version") == 1, "Storage stays at v1")
	profile.display_name = "Changed companion"
	_expect(PalSessionStore.save_profiles(profiles, path) == OK, "Save creates a backup")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(false, "Create damaged-storage fixture")
		return
	file.store_string("invalid json")
	file.close()
	var recovered := PalSessionStore.load_session(path)
	_expect(recovered.status == "recovered" and recovered.profiles.size() == 1 and recovered.profiles[0].display_name == "Saved companion", "Recover the valid backup")
	_expect(FileAccess.get_file_as_string(path) == "invalid json", "Recovery preserves the damaged original")
	_expect(PalSessionStore.save_profiles(profiles, path) == OK, "Save after recovery")
	var empty: Array[PalProfile] = []
	_expect(PalSessionStore.save_profiles(empty, path) == OK, "Save an empty roster")
	var cleared := PalSessionStore.load_session(path)
	_expect(cleared.valid and cleared.profiles.is_empty(), "An empty roster stays empty")

func _check_app() -> void:
	var app: PalUiCoordinator = load("res://scenes/app/app.tscn").instantiate()
	root.add_child(app)
	await _frames()
	_expect(app._manager.instances.size() == 1, "Startup creates one companion")
	if app._manager.instances.is_empty():
		app.free()
		return
	var pet: PalPetInstance = app._manager.instances.values()[0]
	var profile_id := pet.profile.profile_id
	_expect(pet.profile.visual_id == "sprite2d" and pet.presenter != null, "Startup uses the 2D presenter")
	_expect(str(app._chat_service.call("GetStartupError")).is_empty(), "Chat service starts")
	_check_context(app._chat_service, profile_id)
	var pages := ["appearance", "settings", "profile", "memory", "world", "sessions", "new", "summary", "packages", "add"]
	if not PalUi.is_mobile() and OS.get_name() == "Windows":
		pages.append("agent")
	for page: String in pages:
		app._open_panel_now(page, profile_id, {})
		await _frames()
		_expect(app._panels.is_open() and app._panels.page_id == page, "Open " + page)
		app._panels.hide_panel()
	await _check_confirmation(app._panels)
	_check_portraits(pet)
	if PalUi.is_mobile():
		_expect(not pet.switch_visual("vrm3d"), "Mobile keeps the 2D presenter")
		app._put_on_desktop(pet.instance_id)
		_expect(app._desktop_windows.is_empty(), "Mobile creates no desktop windows")
	else:
		_expect(pet.switch_visual("vrm3d"), "Switch to the built-in VRM")
		await _frames()
		_expect(pet.presenter.get_capabilities().get("dimension") == "3d", "VRM is active")
		_expect(pet.switch_visual("sprite2d") and pet.profile.profile_id == profile_id, "Return to 2D without replacing identity")
		app._put_on_desktop(pet.instance_id)
		await _frames()
		_expect(app._desktop_windows.has(pet.instance_id), "Create the desktop host")
		if app._desktop_windows.has(pet.instance_id):
			var desktop: PalDesktopWindow = app._desktop_windows[pet.instance_id]
			_expect(pet.get_parent() == desktop.surface, "Desktop hosts the same companion")
		app._return_pet(pet.instance_id)
		await _frames()
		_expect(not app._desktop_windows.has(pet.instance_id) and pet.get_parent() == app._hall.surface, "Recall the companion into the hall")
	app.free()
	await process_frame

func _check_context(service: Node, profile_id: String) -> void:
	_expect(str(service.call("SaveManualContext", profile_id, "memory", "Validation memory")).is_empty(), "Save manual memory")
	_expect(str(service.call("SaveManualContext", profile_id, "world", "Validation world")).is_empty(), "Save world settings")
	_expect(str(service.call("NewConversation", profile_id)).is_empty(), "Create a new conversation")
	var context: Dictionary = JSON.parse_string(service.call("GetManualContext", profile_id))
	_expect(context.get("memory") == "Validation memory" and context.get("world") == "Validation world", "New conversations retain manual context")
	_expect(str(context.get("file_error", "")).is_empty(), "Context files reload cleanly")
	var snapshot: Dictionary = JSON.parse_string(service.call("GetSnapshot", profile_id))
	_expect(snapshot.get("messages", []).is_empty() and not snapshot.get("busy", true) and str(snapshot.get("storage_error", "")).is_empty(), "New conversations are empty and saved")

func _check_confirmation(panels: PalPanelHost) -> void:
	var accepted: Array[int] = [0]
	panels.confirm("Confirmation", "Check actions with different text lengths.", "Continue", func() -> void: accepted[0] += 1)
	await _frames()
	_expect(absf(panels._confirm_no.size.x - panels._confirm_yes.size.x) <= 1, "Confirmation buttons share the available width")
	panels._confirm_no.pressed.emit()
	_expect(not panels.is_confirming() and accepted[0] == 0, "Cancel preserves the action")
	panels.confirm("Confirmation", "Accept the action.", "Continue", func() -> void: accepted[0] += 1)
	await _frames()
	panels._confirm_yes.pressed.emit()
	_expect(not panels.is_confirming() and accepted[0] == 1, "Confirm invokes the action once")

func _check_portraits(pet: PalPetInstance) -> void:
	var pack := PalPortraitPack.new()
	if not pack.open(PalPortraitPack.DEFAULT_MANIFEST):
		_expect(false, "Open the built-in portrait manifest: " + pack.error)
		return
	for id: String in pack.visual.poses:
		var texture := pack.texture(id)
		var canvas: Array = pack.visual.poses[id].canvas_size
		_expect(texture != null and texture.get_size() == Vector2(float(canvas[0]), float(canvas[1])), "Load portrait " + id)
	pet.set_presentation_mode("full_body")
	_expect(pet.behavior.request_action("walk"), "The desktop portrait can walk")
	pet.presenter.set_walk_direction(-1)
	var left := str(pet.presenter.get("_pose_id"))
	pet.presenter.set_walk_direction(1)
	_expect(str(pet.presenter.get("_pose_id")) != left, "Walking direction changes the portrait")
	_expect(pet.set_outfit("nightdress", "model"), "An allowed model request changes clothes")
	_expect(pet.set_outfit("maid"), "Manual clothing selection succeeds")
	_expect(not pet.set_outfit("nightdress", "model") and pet.profile.outfit == "maid", "Manual clothing selection blocks a late model request")
	pet.behavior.request_action("idle")
	pet.set_presentation_mode(pet.profile.portrait_framing)

func _frames() -> void:
	for index: int in 5:
		await process_frame
'@

$runtimePath = Join-Path $logRoot 'runtime.gd'
[System.IO.File]::WriteAllText($runtimePath, $runtimeScript, [System.Text.UTF8Encoding]::new($false))
$saved = @{}
foreach ($key in @('APPDATA', 'GD_PAL_TEST', 'GD_PAL_MOBILE_PREVIEW', 'GODOT_MCP_ENABLED')) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key)
}
try {
    $env:APPDATA = Join-Path $logRoot 'userdata'
    $env:GD_PAL_TEST = '1'
    $env:GD_PAL_MOBILE_PREVIEW = ''
    $env:GODOT_MCP_ENABLED = '0'
    New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    Invoke-Checked (Get-Command dotnet).Source @('build', (Join-Path $projectRoot 'gd-pal.csproj'), '--nologo') 'build'
    Invoke-Checked $enginePath @('--headless', '--path', $projectRoot, '--import') 'import'
    Invoke-Checked $enginePath @('--headless', '--path', $projectRoot, '--script', $runtimePath) 'desktop' 'GD_PAL_CHECK: PASS'
    $env:GD_PAL_MOBILE_PREVIEW = '1'
    $env:APPDATA = Join-Path $logRoot 'userdata-mobile'
    New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    Invoke-Checked $enginePath @('--headless', '--path', $projectRoot, '--script', $runtimePath) 'mobile' 'GD_PAL_CHECK: PASS'
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
}
Write-Output "GD Pal validation passed. Logs: $logRoot"
