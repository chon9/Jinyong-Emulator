param([string]$Godot = 'K:\Godot\Godot_v4.6.3-stable_win64_console.exe', [switch]$SocialNetwork, [switch]$DungeonNetwork, [switch]$NetworkOnly, [switch]$WebSocketNetwork)
$ErrorActionPreference = 'Stop'
$youxiaRoot = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $youxiaRoot '.tools\appdata'
$env:LOCALAPPDATA = Join-Path $youxiaRoot '.tools\localappdata'
New-Item -ItemType Directory -Path (Join-Path $youxiaRoot 'test-results'),$env:APPDATA,$env:LOCALAPPDATA -Force | Out-Null
$youxiaSuites = if ($NetworkOnly) { @() } else { @('world_test.gd','martial_test.gd','restoration_test.gd','social_test.gd','bgm_test.gd','ui_test.gd','ui_flow_test.gd','quest_paths_test.gd','quest_save_test.gd','dungeon_test.gd','dungeon_ui_test.gd','life_test.gd','life_ui_test.gd','web_save_test.gd') }
foreach ($youxiaSuite in $youxiaSuites) {
    & $Godot --headless --path $youxiaRoot --script "res://tests/$youxiaSuite" -- --no-steam --test-profile=unit
    if ($LASTEXITCODE -ne 0) { throw "Failed: $youxiaSuite" }
}
$youxiaProcesses = @()
try {
    foreach ($youxiaRole in @('host','client')) {
        $youxiaNetworkScript = if ($DungeonNetwork) { 'res://tests/dungeon_net.gd' } elseif ($SocialNetwork -or $WebSocketNetwork) { 'res://tests/social_net.gd' } else { 'res://tests/net_peer.gd' }
        $youxiaProfile = if ($DungeonNetwork) { "dungeonnet_$youxiaRole" } elseif ($SocialNetwork) { "socialnet_$youxiaRole" } else { "net_$youxiaRole" }
        $youxiaArgs = @('--headless','--path',('"' + $youxiaRoot + '"'),'--script',$youxiaNetworkScript,'--','--no-steam',"--test-profile=$youxiaProfile")
        if ($youxiaRole -eq 'host') { $youxiaArgs += '--host-test' }
        if ($WebSocketNetwork) { $youxiaArgs += '--websocket-test' }
        $youxiaProcess = Start-Process -FilePath $Godot -ArgumentList $youxiaArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $youxiaRoot "test-results\net_$youxiaRole.log") -RedirectStandardError (Join-Path $youxiaRoot "test-results\net_$youxiaRole.err")
        $youxiaProcesses += $youxiaProcess
        if ($youxiaRole -eq 'host') { Start-Sleep -Milliseconds 1200 }
    }
    foreach ($youxiaProcess in $youxiaProcesses) {
        if (-not $youxiaProcess.WaitForExit(60000)) { throw 'Network test timed out' }
        $youxiaProcess.Refresh()
        if ($youxiaProcess.ExitCode -ne 0) { throw 'Network peer failed; see test-results logs' }
    }
    foreach ($youxiaRole in @('host','client')) {
        Get-Content -LiteralPath (Join-Path $youxiaRoot "test-results\net_$youxiaRole.log")
        $youxiaErrors = Get-Content -LiteralPath (Join-Path $youxiaRoot "test-results\net_$youxiaRole.err") -Raw
        if ($youxiaErrors) { throw "Unexpected engine errors: $youxiaErrors" }
    }
} finally {
    foreach ($youxiaProcess in $youxiaProcesses) {
        if (-not $youxiaProcess.HasExited) { Stop-Process -Id $youxiaProcess.Id }
    }
}
Write-Output 'All suites passed.'
