param(
    [string]$Godot = 'K:\Godot\Godot_v4.6.3-stable_win64_console.exe',
    [switch]$Headless,
    [switch]$NoSteam,
    [switch]$Import,
    [string]$Script = '',
    [int]$QuitAfter = 0,
    [switch]$Capture,
    [string[]]$GameArgs = @()
)
$ErrorActionPreference = 'Stop'
$youxiaRoot = Split-Path -Parent $PSScriptRoot
# 將引擎與遊戲的測試資料留在專案目錄，方便攜帶及避免污染其他專案。
$env:APPDATA = Join-Path $youxiaRoot '.tools\appdata'
$env:LOCALAPPDATA = Join-Path $youxiaRoot '.tools\localappdata'
New-Item -ItemType Directory -Path $env:APPDATA,$env:LOCALAPPDATA -Force | Out-Null
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot not found: $Godot" }
$youxiaArgs = @('--path', $youxiaRoot)
if ($Headless) { $youxiaArgs += '--headless' }
if ($Import) { $youxiaArgs += @('--editor', '--import', '--quit') }
if ($Script) { $youxiaArgs += @('--script', $Script) }
if ($QuitAfter -gt 0) { $youxiaArgs += @('--quit-after', "$QuitAfter") }
$youxiaArgs += '--'
if ($NoSteam) { $youxiaArgs += '--no-steam' }
if ($Capture) { $youxiaArgs += '--capture' }
$youxiaArgs += $GameArgs
& $Godot @youxiaArgs
exit $LASTEXITCODE
