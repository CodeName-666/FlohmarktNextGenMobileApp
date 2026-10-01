<#!
Windows entry point. SDKs live outside this repository. Flutter's intermediate
output remains app/build; distributable artifacts are collected in build/.
#>
[CmdletBinding()]
param(
    [ValidateSet('doctor', 'get', 'check', 'test', 'run', 'android')]
    [string]$Task = 'doctor',
    [string]$FlutterSdk = $env:FLUTTER_ROOT,
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$Device
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $FlutterSdk) {
    $FlutterSdk = Join-Path $env:USERPROFILE 'Development/SDKs/flutter'
}
if (-not $AndroidSdk) {
    $AndroidSdk = Join-Path $env:USERPROFILE 'Development/SDKs/android-sdk'
}
$flutter = Join-Path $FlutterSdk 'bin/flutter.bat'
$dart = Join-Path $FlutterSdk 'bin/dart.bat'
if (-not (Test-Path -LiteralPath $flutter)) { throw "Flutter SDK fehlt: $FlutterSdk" }
if (Test-Path -LiteralPath $AndroidSdk) {
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable endete mit Code $LASTEXITCODE" }
}

Push-Location (Join-Path $repoRoot 'app')
try {
    switch ($Task) {
        'doctor' { Invoke-Checked $flutter @('doctor', '-v') }
        'get' { Invoke-Checked $flutter @('pub', 'get') }
        'check' {
            Invoke-Checked $dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test')
            Invoke-Checked $flutter @('analyze')
            Invoke-Checked $flutter @('test')
        }
        'test' { Invoke-Checked $flutter @('test') }
        'run' {
            if (-not $Device) { throw 'Gerät mit -Device angeben (IDs: flutter devices).' }
            Invoke-Checked $flutter @('run', '-d', $Device)
        }
        'android' {
            Invoke-Checked $flutter @('build', 'apk', '--debug')
            Invoke-Checked 'python' @('../scripts/collect_artifacts.py', 'android', 'debug-apk')
        }
    }
} finally {
    Pop-Location
}
