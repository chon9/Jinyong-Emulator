param([string]$Godot = 'K:\Godot\Godot_v4.6.3-stable_win64_console.exe', [switch]$SocialNetwork, [switch]$DungeonNetwork, [switch]$NetworkOnly, [switch]$WebSocketNetwork)
$ErrorActionPreference = 'Stop'
$youxiaRoot = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $youxiaRoot '.tools\appdata'
$env:LOCALAPPDATA = Join-Path $youxiaRoot '.tools\localappdata'
New-Item -ItemType Directory -Path (Join-Path $youxiaRoot 'test-results'),$env:APPDATA,$env:LOCALAPPDATA -Force | Out-Null
$youxiaSuites = if ($NetworkOnly) { @() } else { @('aftermath_test.gd','story_reset_test.gd','presentation_test.gd','jianghu_story_test.gd','visual_consistency_test.gd','open_world_test.gd','locomotion_test.gd','journey_expansion_test.gd','journey_test.gd','journey_ui_test.gd','journey_activities_test.gd','world_test.gd','martial_test.gd','restoration_test.gd','social_test.gd','bgm_test.gd','ui_test.gd','ui_flow_test.gd','quest_paths_test.gd','quest_save_test.gd','dungeon_test.gd','dungeon_ui_test.gd','life_test.gd','life_ui_test.gd','web_save_test.gd') }
foreach ($youxiaSuite in $youxiaSuites) {
    & $Godot --headless --path $youxiaRoot --script "res://tests/$youxiaSuite" -- --no-steam --test-profile=unit
    if ($LASTEXITCODE -ne 0) { throw "Failed: $youxiaSuite" }
}
$youxiaProcesses = @()
# Each run starts with fresh test characters; reconnect still uses one identity.
$youxiaNetworkRun = [guid]::NewGuid().ToString('N').Substring(0,8)
try {
    foreach ($youxiaRole in @('host','client')) {
        $youxiaNetworkScript = if ($DungeonNetwork) { 'res://tests/dungeon_net.gd' } elseif ($SocialNetwork -or $WebSocketNetwork) { 'res://tests/social_net.gd' } else { 'res://tests/net_peer.gd' }
        $youxiaProfile = if ($DungeonNetwork) { "dungeonnet_$youxiaRole" } elseif ($SocialNetwork) { "socialnet_$youxiaRole" } else { "net_$youxiaRole" }
        $youxiaArgs = @('--headless','--path',('"' + $youxiaRoot + '"'),'--script',$youxiaNetworkScript,'--','--no-steam',"--test-profile=$($youxiaProfile)_$youxiaNetworkRun")
        if ($youxiaRole -eq 'host') { $youxiaArgs += '--host-test' }
        if ($WebSocketNetwork) { $youxiaArgs += '--websocket-test' }
        $youxiaProcess = Start-Process -FilePath $Godot -ArgumentList $youxiaArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $youxiaRoot "test-results\net_$youxiaRole.log") -RedirectStandardError (Join-Path $youxiaRoot "test-results\net_$youxiaRole.err")
        # Keep the native handle open: Windows PowerShell otherwise loses ExitCode for short-lived children.
        $null = $youxiaProcess.Handle
        $youxiaProcesses += $youxiaProcess
        if ($youxiaRole -eq 'host') { Start-Sleep -Milliseconds 1200 }
    }
    foreach ($youxiaProcess in $youxiaProcesses) {
        if (-not $youxiaProcess.WaitForExit(60000)) { throw 'Network test timed out' }
        if ($youxiaProcess.ExitCode -ne 0) { throw "Network peer failed (exit $($youxiaProcess.ExitCode)); see test-results logs" }
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
