param([string]$KeytoolPath = 'keytool')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$signingRoot = Join-Path $projectRoot 'release-signing'
$keystore = Join-Path $signingRoot 'android-release.keystore'
$config = Join-Path $signingRoot 'android-release.json'
if ((Test-Path -LiteralPath $keystore) -or (Test-Path -LiteralPath $config)) {
    throw "Signing files already exist in $signingRoot. Keep the existing certificate for future updates."
}
New-Item -ItemType Directory -Path $signingRoot -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $signingRoot '.gdignore'), '')
# Restrict the local signing folder before writing private material.
if ($env:OS -eq 'Windows_NT') {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $access = [System.Security.AccessControl.DirectorySecurity]::new()
    $access.SetOwner($identity)
    $access.SetAccessRuleProtection($true, $false)
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
    $access.AddAccessRule($rule)
    Set-Acl -LiteralPath $signingRoot -AclObject $access
}
$random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 32
$random.GetBytes($bytes)
$random.Dispose()
$password = [Convert]::ToBase64String($bytes)
$savedPassword = $env:GD_PAL_RELEASE_KEY_PASSWORD
try {
    $env:GD_PAL_RELEASE_KEY_PASSWORD = $password
    & $KeytoolPath -genkeypair -noprompt -keystore $keystore -storetype PKCS12 -alias gd-pal -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=GD Pal, OU=Release, O=GD Pal' -storepass:env GD_PAL_RELEASE_KEY_PASSWORD -keypass:env GD_PAL_RELEASE_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate the Android release certificate.' }
    $document = [ordered]@{ keystore = 'android-release.keystore'; alias = 'gd-pal'; password = $password }
    [System.IO.File]::WriteAllText($config, ($document | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $signingRoot 'README.txt'), 'Back up android-release.keystore and android-release.json together in a private location. Future Android updates must use this same certificate. Never upload this folder to Git or a Release.', [System.Text.UTF8Encoding]::new($false))
} finally {
    $env:GD_PAL_RELEASE_KEY_PASSWORD = $savedPassword
    $password = $null
}
Write-Output "Android release signing configured in $signingRoot. Back up the keystore and JSON together; do not distribute them."
