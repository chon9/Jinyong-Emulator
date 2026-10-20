param([string]$Godot = 'K:\Godot\Godot_v4.6.3-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$youxiaRoot = Split-Path -Parent $PSScriptRoot
$youxiaWebProject = Join-Path $youxiaRoot '.tools\web-project'
$youxiaRaw = Join-Path $youxiaRoot 'build\web-raw'
$env:APPDATA = Join-Path $youxiaRoot '.tools\appdata'
$env:LOCALAPPDATA = Join-Path $youxiaRoot '.tools\localappdata'
$env:TEMP = Join-Path $youxiaRoot '.tools\web-temp'
$env:TMP = $env:TEMP
$youxiaTemplate = Join-Path $env:APPDATA 'Godot\export_templates\4.6.3.stable\web_nothreads_release.zip'
if (-not (Test-Path -LiteralPath $youxiaTemplate)) { throw 'Run python tools/fetch_web_templates.py first.' }
New-Item -ItemType Directory -Path $youxiaWebProject,$youxiaRaw,$env:LOCALAPPDATA,$env:TEMP -Force | Out-Null
# Isolated export source contains no native Steam extension or private runtime data.
foreach ($youxiaDirectory in @('scripts','scenes','assets','data','web')) {
    & robocopy (Join-Path $youxiaRoot $youxiaDirectory) (Join-Path $youxiaWebProject $youxiaDirectory) /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Cannot prepare $youxiaDirectory" }
}
Copy-Item -LiteralPath (Join-Path $youxiaRoot 'project.godot') -Destination $youxiaWebProject -Force
Copy-Item -LiteralPath (Join-Path $youxiaRoot 'web\export_presets.cfg') -Destination $youxiaWebProject -Force
& $Godot --headless --path $youxiaWebProject --editor --import --quit -- --no-steam
if ($LASTEXITCODE -ne 0) { throw 'Web import failed' }
& $Godot --headless --path $youxiaWebProject --export-release 'Web Release' (Join-Path $youxiaRaw 'index.html') -- --no-steam
if ($LASTEXITCODE -ne 0) { throw 'Web export failed' }
python (Join-Path $PSScriptRoot 'package_web.py') --source $youxiaRaw --output (Join-Path $youxiaRoot 'sites\youxia-web\dist')
if ($LASTEXITCODE -ne 0) { throw 'Web packaging failed' }
