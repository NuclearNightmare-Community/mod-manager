<#
.SYNOPSIS
  Runs one Mod Manager scenario end to end: deploy (with the driver and the fixtures), launch, serve the driver's
  requests, wait, close, record whether files changed, check.
.DESCRIPTION
  -Target vm (the default) runs the scenario in the Hyper-V VM NNB (the workspace's tools/vm/vm-sp.ps1, README "Tests
  in the VM"): Nucleus from the host's mods/Nucleus/build/package (its own deploy.ps1 -Staged), the Mod Manager, the
  driver and the fixtures (deploy.ps1 -Test -Staged, with the same refusal checks for no-core and old-core) go into
  the VM's copy of the same build, the VM's game is launched, the driver's requests are served there (keys, clicks,
  moves, wheel, screenshots), and the VM copy is put back as it was afterwards. It never builds and never touches the
  host's game copy or a host game, so it can run while someone plays on the host.
  -Target host launches the dev copy itself, only through the workspace's tools/launch.ps1 (which passes -userdir),
  and serves the driver's requests from mods/Nucleus/run.ps1: "key ENTER|UP|DOWN" posted to the game window,
  "click|move <x> <y>" and "wheel <x> <y> <n>" as real mouse input on the game window only (it is brought to the front
  first, so it takes the mouse for a moment), "shot <label>" skipped (VM only).
  Either way it stops when the driver logs its END line, the game exits (crash), or -TimeoutSec runs out (hang); then
  closes the game. The screen scenario (story 6) ends differently: after "END result=PASS" the driver clicks QUIT GAME,
  so the run waits for the game to close itself (only "END result=FAIL" stops it early); check.ps1 accepts that exit
  only with "[ModManager] QUIT pending=" after "END result=PASS" and no crash line. run.ps1 appends
  "[run.ps1] RUN <how the run ended>" to the kept log.
  Files: it records the SHA-256 of mods.txt and the file names under Content/Paks and Content/Paks/LogicMods after the
  deploy and again after the game closed, and appends "[run.ps1] FILES unchanged" or "[run.ps1] FILES changed: <what>"
  to the kept log, which check.ps1 judges (the Mod Manager writes mods.txt in story 6, never a pak).
  Scenarios that break core on purpose (no-core: Mods/Nucleus moved aside; old-core: its mod.json version set to
  0.1.0, which the driver publishes as core's runtime version) first check that deploy.ps1 refuses without -Force,
  then deploy with -Force, and put core back afterwards (in the VM they act on the stage only).
  The restart scenario (story 8; VM only: the host runner can't follow a relaunch) turns ModManagerRestart off, starts
  core's relaunch helper and clicks RESTART NOW; the game closes and starts itself again. The VM runner is called with
  -AllowRelaunch (one exit followed by a new game process within 60 s; the kept log holds both sessions and a
  "[run.ps1] RELAUNCH old=<pid> new=<pid> cmdline=same|differs userdir=yes|no" line), -MarkOfTheWeb on the deployed
  Mods/Nucleus/bin/NucleusRestart.exe (tagged as downloaded before the launch) and -DefenderReport ("[run.ps1] DEFENDER
  ..." lines). run.ps1 then appends "[run.ps1] BUILDSCAN <file> <result> package=same|differs" for each line of
  Nucleus's build/logs/defender.txt (build.ps1's Windows Defender scans), comparing the scanned SHA-256 with the
  file in Nucleus's build/package.
  The apply scenario (Mod Manager v2 story 3; VM only, title screen only, four game sessions in one run) checks that a
  staged change reaches the disk however the game exits. deploy.ps1 -Test -Scenario apply stages plan A
  (test/ModManagerApplyA) in the stage's ue4ss/NucleusData/staged/. The VM runner is called with -RepeatUntilEnd (after
  an exit that isn't the game's own relaunch it waits for core's helpers to exit, then launches the game itself; each
  session follows a "[run.ps1] SESSION <n> (<how>)" line), -DataDirs NucleusData (core's data folder moved aside for the
  run and put back after; the helper's installs of ModManagerApplyA/B/C are removed with the run's -Mods), and
  -StageFixtures B and C (plan B: test/ModManagerApplyB; plan C: test/ModManagerApplyC's files, then a different file
  over A's Scripts/main.lua, then C on; each written on the host by Nucleus's native/test/New-StagedPlan.ps1). The
  driver's requests "stage B|C", "lock <A's main.lua>", "kill" and "close" are served by tools/vm/vm-sp.ps1. Session
  1 ends with RESTART NOW (the game relaunches itself after A is applied), session 2 with "kill" (B applied), session 3
  with "close" (WM_CLOSE, as Alt+F4) while A's main.lua is locked (C fails and is rolled back), session 4 checks the
  failure and ends at the driver's END line; the runner then stops the waiting helper and releases the lock. Like
  restart: -MarkOfTheWeb on the helper, -DefenderReport (with Controlled Folder Access) and the BUILDSCAN lines.
  The install scenario (Mod Manager v2 story 5; VM only, the live catalog, two game sessions in one run) installs HUD
  Clock from Browse: deploy.ps1 -Test -Scenario install leaves HudClock out of the stage (the VM copy's HudClock, its
  paks and mods.txt are saved and put back by the VM restore). The VM runner is called with -RepeatUntilEnd and -DataDirs
  NucleusData (core's data folder with its downloads, staged change, installed.txt and result, moved aside for the run
  and put back after). Session 1 ends with RESTART NOW (core's helper applies the staged HUD Clock, then relaunches the
  game); session 2 checks it runs and ends at the driver's END line.
  The update scenario (Mod Manager v2 story 6; VM only, a fixture catalog, two game sessions in one run): deploy.ps1
  -Test -Scenario update installs core's test main.dll, HUD Clock 0.3.0 and WhistleMute, and the fixture catalog in the
  driver's folder (HUD Clock 0.3.0 revoked, 0.3.1 and core one patch newer offered). The VM runner is called with
  -RepeatUntilEnd, -DataDirs NucleusData and -FixtureServer (tools/release/tests/https-fixture-server.ps1 serves the
  fixture map inside the VM; the run writes NucleusData/catalog-test.json with its port and certificate, for the test
  main.dll). Session 1: the title-screen notice, UPDATE TO 0.3.1 from REVIEW, the Nucleus update, WhistleMute's
  UNINSTALL, RESTART NOW; session 2 checks what core's helper applied, uninstalls HUD Clock 0.3.1 (so a helper starts
  and deletes the self-update's bin\<Core>Restart.<txn>.old; the run stops it before the game closes, so that removal
  is never applied) and ends at the driver's END line. The VM
  restore puts HudClock, WhistleMute, core and NucleusData back as they were.
  The browse scenario (Mod Manager v2 story 4; VM only) runs against the live catalog: the Mod Manager's startup refresh
  and one REFRESH reach the catalog's endpoints through core's native part; it ends at the driver's END line.
  Keeps the log as <workspace>/dumps/<copy>/mod-manager/<scenario>[.vm].log (ignored by git) and runs check.ps1 on it.
  Refuses to start while another runner's test or driver mod is enabled in the copy (the workspace's tools/run-guard:
  the refusal names each and the command that clears it); -AllowOtherDrivers runs anyway.
.EXAMPLE
  ./run.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774 -Scenario screen
  ./run.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774 -Scenario screen -Target host
  ./run.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774 -Scenario apply
#>
param(
    [Parameter(Mandatory)] [string] $Instance,
    [ValidateSet('screen', 'no-core', 'old-core', 'restart', 'apply', 'browse', 'install', 'update')]
    [string] $Scenario = 'screen',
    [int] $TimeoutSec = 0, # 0: screen 1200 s (about 90 requests and two map loads), restart 600 s (two launches), apply 1200 s (four launches and three helper runs), browse 600 s (two live refreshes), install 900 s (two launches, a download and an apply), update 900 s (two launches, three stages and an apply), others 420 s; x1.5 in the VM
    [ValidateSet('host', 'vm')] [string] $Target = 'vm',
    [switch] $AllowOtherDrivers # run even when another runner's test mod is enabled in the copy (tools/run-guard)
)
$ErrorActionPreference = 'Stop'
$hostTimeout = switch ($Scenario) { 'screen' { 1200 } 'restart' { 600 } 'apply' { 1200 } 'browse' { 600 } 'install' { 900 } 'update' { 900 } default { 420 } }
if ($Scenario -in 'restart', 'apply', 'install', 'update' -and $Target -ne 'vm') { throw "The $Scenario scenario runs only in the VM (-Target vm): the host runner does not follow a game that starts itself again." }
if ($Scenario -eq 'browse' -and $Target -ne 'vm') { throw "The browse scenario runs only in the VM (-Target vm): its driver asks for 'key RIGHT', 'type <text>' and screenshots, which only the VM runner serves (the host runner serves key ENTER, UP and DOWN, clicks, moves and wheels)." }
if ($TimeoutSec -le 0 -and $Target -eq 'host') { $TimeoutSec = $hostTimeout }
$CoreName = 'Nucleus'
$here     = $PSScriptRoot
$name     = (Get-Content (Join-Path $here 'mod.json') -Raw | ConvertFrom-Json).name
$driver   = "${name}Driver"
# The line that ends a run early: screen and restart end with QUIT GAME after END result=PASS, so only a FAIL stops it
# here. apply ends at its END line: the runner then stops the helper that waits to apply plan C again.
$endRx = if ($Scenario -in 'screen', 'restart') { "\[$driver\] END result=FAIL" } else { "\[$driver\] END result=" }
$fixtures = @("${name}Fixture", "${name}Bare", "${name}Long", "${name}Base", "${name}Dep", "${name}Restart")
$fixturePaks = @("${name}Pak_P.pak", "${name}PakOff_P.pak.disabled")
$inst     = (Resolve-Path $Instance).Path
$root     = Split-Path (Split-Path $inst)
. (Join-Path $root 'tools\run-guard\run-guard.ps1')
. (Join-Path $here 'deploy-lib.ps1')
# Story 3 (v2): the apply scenario's fixtures (installed only by core's helper from staged changes; listed in the VM
# run's -Mods so the restore removes them) and core's plan writer (Nucleus's native/test/New-StagedPlan.ps1).
$applyFixtures = @(Get-ApplyFixtures $name)
$planWriter = Join-Path $root "mods\$CoreName\native\test\New-StagedPlan.ps1"
$outDir   = Join-Path $root "dumps\$(Split-Path $inst -Leaf)\mod-manager"
function Set-DeployTarget([string] $instance) {
    $script:deployInst = $instance
    $script:ue4ss    = Join-Path $instance 'NuclearNightmare\Binaries\Win64\ue4ss'
    $script:modsDir  = Join-Path $script:ue4ss 'Mods'
    $script:modsTxt  = Join-Path $script:modsDir 'mods.txt'
    $script:paksDir  = Join-Path $instance 'NuclearNightmare\Content\Paks'
    $script:log      = Join-Path $script:ue4ss 'UE4SS.log'
    $script:scripts  = Join-Path $script:modsDir "$driver\Scripts"
    $script:backup   = Join-Path $script:ue4ss '_mod-manager-test-backup'
}
Set-DeployTarget $inst
$exeName  = 'NuclearNightmare-Win64-Shipping'
New-Item -ItemType Directory -Force $outDir | Out-Null

# deploy.ps1 ends with exit 1 when it refuses, so it always runs in its own pwsh.
function Invoke-Deploy([string[]] $a) {
    if ($Target -eq 'vm') { $a += '-Staged' }
    $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $here 'deploy.ps1') -Instance $script:deployInst @a 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $out.Trim() }
}

# ---------------------------------------------------------------- breaking and restoring core
function Restore-Core {
    if (-not (Test-Path $backup)) { return }
    $saved = Join-Path $backup $CoreName
    if (Test-Path $saved) {
        if (Test-Path (Join-Path $modsDir $CoreName)) { throw "Both $saved and Mods/$CoreName exist; sort them out by hand." }
        Move-Item $saved (Join-Path $modsDir $CoreName)
    }
    $json = Join-Path $backup 'mod.json'
    if (Test-Path $json) { Copy-Item $json (Join-Path $modsDir "$CoreName\mod.json") -Force }
    $txt = Join-Path $backup 'mods.txt'
    if (Test-Path $txt) { Copy-Item $txt $modsTxt -Force }
    Remove-Item $backup -Recurse -Force
    Write-Host "Restored $CoreName (and mods.txt) from $backup."
}
function Break-Core {
    New-Item -ItemType Directory -Force $backup | Out-Null
    Copy-Item $modsTxt (Join-Path $backup 'mods.txt') -Force
    switch ($Scenario) {
        'no-core' {
            Move-Item (Join-Path $modsDir $CoreName) (Join-Path $backup $CoreName)
            $lines = @(Get-Content $modsTxt | Where-Object { $_ -notmatch ('^\s*' + [regex]::Escape($CoreName) + '\s*:') })
            Set-Content $modsTxt $lines
            Write-Host "Moved Mods/$CoreName to $backup and took it out of mods.txt."
        }
        'old-core' {
            $json = Join-Path $modsDir "$CoreName\mod.json"
            Copy-Item $json (Join-Path $backup 'mod.json') -Force
            $text = Get-Content $json -Raw
            $new = [regex]::Replace($text, '("version"\s*:\s*")[^"]*(")', '${1}0.1.0${2}', 1)
            if ($new -eq $text) { throw "could not set the version in $json" }
            [IO.File]::WriteAllText($json, $new)
            Write-Host "Set the installed $CoreName mod.json version to 0.1.0 (original kept in $backup)."
        }
    }
}

$script:runFailures = @()
function Deploy-Scenario {
    if ($Scenario -in 'no-core', 'old-core') {
        Break-Core
        $r = Invoke-Deploy @()
        $why = if ($Scenario -eq 'no-core') { "$CoreName is not installed" } else { "$CoreName 0\.1\.0 is installed, but $name needs >=" }
        if ($r.Code -eq 1 -and $r.Out -match "^$name not deployed: $why" -and ($r.Out -split "`r?`n").Count -eq 1) {
            Write-Host "ok:   deploy.ps1 refused without -Force: $($r.Out)"
        } else {
            Write-Host "FAIL: deploy.ps1 should refuse with one line (exit $($r.Code)): $($r.Out)"
            $script:runFailures += 'deploy refusal'
        }
        $r = Invoke-Deploy @('-Test', '-Scenario', $Scenario, '-Force')
    } else {
        $r = Invoke-Deploy @('-Test', '-Scenario', $Scenario)
    }
    Write-Host $r.Out
    if ($r.Code -ne 0) { throw "deploy.ps1 failed (exit $($r.Code))" }
}

# ---------------------------------------------------------------- files: the mod writes nothing
# Get-FileState and Get-FilesLine live in deploy-lib.ps1 (dot-sourced above; tested in test/unit/deploy_test.ps1).
function Add-FilesLine([string] $kept, [string] $line) {
    Write-Host $line
    if (Test-Path $kept) { Add-Content -LiteralPath $kept -Value $line }
}

if ($Target -eq 'vm') {
    . (Join-Path $root 'tools\vm\vm-sp.ps1')
    Assert-NNBSpScenario -Scenario $Scenario -HostOnly @()
    $coreDeploy = Join-Path $root "mods\$CoreName\deploy.ps1"
    if (-not (Test-Path $coreDeploy)) { throw "$CoreName's deploy.ps1 not found at $coreDeploy (the VM run installs core from its build/package)." }
    $kept = Join-Path $outDir "$Scenario.vm.log"
    Remove-Item $kept -ErrorAction SilentlyContinue
    # Story 8: the restart scenario lets the game relaunch itself once, tags the deployed helper with Mark of the Web and
    # reports Windows Defender afterwards.
    $relaunch = @{}
    if ($Scenario -eq 'restart') {
        $relaunch = @{ AllowRelaunch = $true; DefenderReport = $true
            MarkOfTheWeb = "NuclearNightmare\Binaries\Win64\ue4ss\Mods\$CoreName\bin\${CoreName}Restart.exe" }
    }
    $runMods = @($CoreName, $driver, $name) + $fixtures
    $runPaks = @("$CoreName.pak")
    $runBasePaks = $fixturePaks
    if ($Scenario -eq 'install') {
        # Story 5 (v2): HudClock is installed by core's helper during the run; listing it makes the VM restore remove it
        # (and put back whatever the copy had). Two sessions; core's data folder saved and put back.
        $runMods += 'HudClock'
        $runPaks += 'HudClock.pak'
        $runBasePaks += 'HudClock_P.pak'
        $relaunch = @{ RepeatUntilEnd = $true; DataDirs = "${CoreName}Data" }
    }
    if ($Scenario -eq 'update') {
        # Story 6 (v2): HudClock and WhistleMute are the deploy's fixtures (their VM copies saved and put back by the
        # restore); two sessions; core's data folder saved and put back; the fixture catalog served inside the VM.
        $runMods += 'HudClock', 'WhistleMute'
        $runPaks += 'HudClock.pak', 'WhistleMute.pak'
        $runBasePaks += 'HudClock_P.pak', 'WhistleMute_P.pak'
        $ueRel = 'NuclearNightmare\Binaries\Win64\ue4ss'
        $relaunch = @{ RepeatUntilEnd = $true; DataDirs = "${CoreName}Data"; FixtureServer = @{
                Map = "$ueRel\Mods\$driver\fixture\map.json"; Template = "$ueRel\Mods\$driver\fixture\catalog-test.template.json"
                Config = "$ueRel\${CoreName}Data\catalog-test.json" } }
    }
    if ($Scenario -eq 'apply') {
        # Story 3 (v2): four sessions; core's data folder saved and put back; plans B and C staged on request. The blocks
        # run inside vm-sp.ps1's functions (dot-sourced here), which see this script's functions; its variables are
        # named with $script: because a function's own variables (Send-NNBSpStageFixture's $Name) would hide them.
        if (-not (Test-Path -LiteralPath $planWriter)) { throw "The apply scenario needs core's plan writer: $planWriter (Nucleus 0.24.0 or newer)." }
        $dataRel = "NuclearNightmare\Binaries\Win64\ue4ss\${CoreName}Data"
        $runMods += $applyFixtures
        $relaunch = @{ RepeatUntilEnd = $true; DefenderReport = $true; DataDirs = "${CoreName}Data"
            MarkOfTheWeb = "NuclearNightmare\Binaries\Win64\ue4ss\Mods\$CoreName\bin\${CoreName}Restart.exe"
            StageFixtures = @{
                B = { param($dir) $null = New-ApplyPlan -Writer $script:planWriter -Data (Join-Path $dir $script:dataRel) -Repo $script:here -Name $script:name -Plan B }
                C = { param($dir) $null = New-ApplyPlan -Writer $script:planWriter -Data (Join-Path $dir $script:dataRel) -Repo $script:here -Name $script:name -Plan C }
            } }
    }
    try {
        $run = Invoke-NNBSpRun -Instance $inst -TestMod $driver -Mods $runMods -Paks $runPaks -BasePaks $runBasePaks -FileState `
            -EndPattern $endRx -TimeoutSec (Get-NNBSpTimeout $hostTimeout $TimeoutSec) -LogOut $kept @relaunch -Prepare {
                param($stage)
                $refusal = Get-RunGuardRefusal -Workspace $root -Instance $stage -Owner 'mod-manager' -Bypass:$AllowOtherDrivers -Vm
                if ($refusal) { throw $refusal }
                & pwsh -NoProfile -NonInteractive -File $coreDeploy -Instance $stage -Staged
                if ($LASTEXITCODE -ne 0) { throw "$CoreName's deploy.ps1 failed in the stage (exit $LASTEXITCODE)" }
                Set-DeployTarget $stage
                Deploy-Scenario
            }
    } catch { if ("$($_.Exception.Message)".StartsWith('refused: ')) { Write-Host $_.Exception.Message; exit 1 }; throw }
    $code = 0
    if ($run.Log) {
        Add-FilesLine $kept "[run.ps1] RUN $($run.Result)"
        Add-FilesLine $kept (Get-FilesLine $run.FilesBefore $run.FilesAfter)
        if ($Scenario -in 'restart', 'apply') {
            # Story 8: build.ps1's Windows Defender scans of what was installed (Nucleus's build/logs/defender.txt).
            $coreBuild = Join-Path $root "mods\$CoreName\build"
            $scanLog = Join-Path $coreBuild 'logs\defender.txt'
            $scans = if (Test-Path $scanLog) { @(Get-Content $scanLog | Where-Object { $_ -match '^SCAN ' }) } else { @() }
            if (-not $scans) { Add-FilesLine $kept "[run.ps1] BUILDSCAN missing ($scanLog)" }
            foreach ($l in $scans) {
                if ($l -match '^SCAN (\S+) sha256=([0-9A-F]{64}) result=(.*)$') {
                    $rel, $sha, $res = $Matches[1], $Matches[2], $Matches[3]
                    $pkgRel = if ($rel -eq 'main.dll') { 'dlls/main.dll' } else { $rel }
                    $pkgFile = Join-Path $coreBuild "package\Mods\$CoreName\$($pkgRel -replace '/', '\')"
                    $same = (Test-Path -LiteralPath $pkgFile) -and (Get-FileHash -LiteralPath $pkgFile -Algorithm SHA256).Hash -eq $sha
                    Add-FilesLine $kept "[run.ps1] BUILDSCAN $rel $res package=$(if ($same) { 'same' } else { 'differs' })"
                } else { Add-FilesLine $kept "[run.ps1] BUILDSCAN unreadable: $l" }
            }
        }
        & pwsh -NoProfile -NonInteractive -File (Join-Path $here 'check.ps1') -Log $kept -Scenario $Scenario -Target vm `
            -CoreManifest (Join-Path $root "mods\$CoreName\build\package\Mods\$CoreName\mod.json")
        $code = $LASTEXITCODE
    } else { Write-Host 'No UE4SS.log from the VM.'; $code = 1 }
    if ($script:runFailures) { Write-Host "run.ps1 check(s) failed: $($script:runFailures -join ', ')"; $code = 1 }
    exit $code
}

# ---------------------------------------------------------------- host: input to the game window only
Add-Type -Namespace ModManagerRun -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, System.UIntPtr extra);
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);
'@
# Slate's absolute coordinates (the driver's click points) are physical desktop pixels: see the same pixels.
[void][ModManagerRun.Win]::SetProcessDpiAwarenessContext([IntPtr](-4))

function Get-OurGame { Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($inst, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1 }
function Stop-Game {
    $p = Get-OurGame
    if ($p) { [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(15000)) { Stop-Process -Id $p.Id -Force } }
    Get-Process -Name 'CrashReportClient*' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($inst, [StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-OurGame) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
}
function Get-FrontGameWindow([string] $what) {
    $p = Get-OurGame
    $h = if ($p) { $p.MainWindowHandle } else { [IntPtr]::Zero }
    if ($h -eq [IntPtr]::Zero) { Write-Host "  $what skipped: no game window"; return [IntPtr]::Zero }
    if ([ModManagerRun.Win]::GetForegroundWindow() -ne $h) {
        [ModManagerRun.Win]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [ModManagerRun.Win]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero) # an Alt tap lifts the foreground lock
        [void][ModManagerRun.Win]::SetForegroundWindow($h)
        Start-Sleep -Milliseconds 300
    }
    if ([ModManagerRun.Win]::GetForegroundWindow() -ne $h) { Write-Host "  $what skipped: the game window is not in front"; return [IntPtr]::Zero }
    return $h
}
function Invoke-Move([int] $x, [int] $y) {
    $h = Get-FrontGameWindow 'move'
    if ($h -eq [IntPtr]::Zero) { return }
    [void][ModManagerRun.Win]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 100
    [ModManagerRun.Win]::mouse_event(0x0001, 1, 0, 0, [UIntPtr]::Zero); [ModManagerRun.Win]::mouse_event(0x0001, -1, 0, 0, [UIntPtr]::Zero)
    Write-Host "  moved the cursor to ($x, $y)"
}
function Invoke-Wheel([int] $x, [int] $y, [int] $notches) {
    $h = Get-FrontGameWindow 'wheel'
    if ($h -eq [IntPtr]::Zero) { return }
    [void][ModManagerRun.Win]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 150
    [ModManagerRun.Win]::mouse_event(0x0001, 1, 0, 0, [UIntPtr]::Zero); [ModManagerRun.Win]::mouse_event(0x0001, -1, 0, 0, [UIntPtr]::Zero)
    $step = if ($notches -lt 0) { -120 } else { 120 }
    for ($i = 0; $i -lt [Math]::Abs($notches); $i++) {
        if ([ModManagerRun.Win]::GetForegroundWindow() -ne $h) { Write-Host '  wheel stopped: the game window lost the front'; return }
        [ModManagerRun.Win]::mouse_event(0x0800, 0, 0, [uint32][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$step), 0), [UIntPtr]::Zero) # MOUSEEVENTF_WHEEL
        Start-Sleep -Milliseconds 80
    }
    Write-Host "  wheel $notches notch(es) at ($x, $y)"
}
function Invoke-Click([int] $x, [int] $y) {
    $h = Get-FrontGameWindow 'click'
    if ($h -eq [IntPtr]::Zero) { return }
    [void][ModManagerRun.Win]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 150
    [ModManagerRun.Win]::mouse_event(0x0001, 1, 0, 0, [UIntPtr]::Zero); [ModManagerRun.Win]::mouse_event(0x0001, -1, 0, 0, [UIntPtr]::Zero) # hover
    Start-Sleep -Milliseconds 150
    if ([ModManagerRun.Win]::GetForegroundWindow() -ne $h) { Write-Host '  click skipped: the game window lost the front'; return }
    [ModManagerRun.Win]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
    [ModManagerRun.Win]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Write-Host "  clicked at ($x, $y)"
}
function Invoke-Request([string] $cmd) {
    if ($cmd -cmatch '^click (\d{1,5}) (\d{1,5})$') {
        $x = [int]$Matches[1]; $y = [int]$Matches[2]
        if ($x -le 16383 -and $y -le 16383) { Invoke-Click $x $y } else { Write-Host "  click skipped: ($x, $y) out of range" }
        return
    }
    if ($cmd -cmatch '^move (\d{1,5}) (\d{1,5})$') {
        $x = [int]$Matches[1]; $y = [int]$Matches[2]
        if ($x -le 16383 -and $y -le 16383) { Invoke-Move $x $y } else { Write-Host "  move skipped: ($x, $y) out of range" }
        return
    }
    if ($cmd -cmatch '^wheel (\d{1,5}) (\d{1,5}) (-?\d{1,2})$') {
        $x = [int]$Matches[1]; $y = [int]$Matches[2]; $n = [int]$Matches[3]
        if ($x -le 16383 -and $y -le 16383 -and $n -ne 0 -and [Math]::Abs($n) -le 20) { Invoke-Wheel $x $y $n } else { Write-Host "  wheel skipped: ($x, $y) or $n notches out of range" }
        return
    }
    if ($cmd -cmatch '^shot [A-Za-z0-9._-]{1,40}$') { Write-Host "  $cmd skipped (screenshots only in the VM)"; return }
    $vk, $scan, $label, $ext = $null, $null, $null, 0
    if ($cmd -ceq 'key ENTER') { $vk, $scan, $label = 0x0D, 0x1C, 'ENTER' }
    elseif ($cmd -ceq 'key UP') { $vk, $scan, $label, $ext = 0x26, 0x48, 'UP', 1 }
    elseif ($cmd -ceq 'key DOWN') { $vk, $scan, $label, $ext = 0x28, 0x50, 'DOWN', 1 }
    if ($null -eq $vk) { Write-Host "  unknown request: $cmd"; return }
    $p = Get-OurGame
    $h = if ($p) { $p.MainWindowHandle } else { [IntPtr]::Zero }
    if ($h -eq [IntPtr]::Zero) { Write-Host '  key skipped: no game window'; return }
    $e = [int64]$ext -shl 24
    $down = [ModManagerRun.Win]::PostMessage($h, 0x0100, [IntPtr]$vk, [IntPtr](1 -bor ($scan -shl 16) -bor $e))
    Start-Sleep -Milliseconds 80
    $up = [ModManagerRun.Win]::PostMessage($h, 0x0101, [IntPtr]$vk, [IntPtr]([int64]0xC0000001 -bor ([int64]$scan -shl 16) -bor $e))
    Write-Host ("  posted {0} to the game window (down={1} up={2})" -f $label, $down, $up)
}

$refusal = Get-RunGuardRefusal -Workspace $root -Instance $inst -Owner 'mod-manager' -Bypass:$AllowOtherDrivers
if ($refusal) { Write-Host $refusal; exit 1 }
if (Get-Process -Name 'NuclearNightmare*' -ErrorAction SilentlyContinue) { throw 'Nuclear Nightmare is already running (a dev copy or the real game); not launching.' }
Restore-Core # a run that was killed may have left core broken
if (-not (Test-Path (Join-Path $modsDir "$CoreName\mod.json"))) { throw "$CoreName is not installed in $modsDir; install it with its own deploy.ps1 first." }

$sw = [Diagnostics.Stopwatch]::StartNew()
$result = 'not started'
$before = $null; $after = $null
try {
    Deploy-Scenario
    $before = Get-FileState $inst
    Remove-Item $log -ErrorAction SilentlyContinue
    & (Join-Path $root 'tools\launch.ps1') -Instance $inst
    $req = Join-Path $scripts 'request.txt'
    $done = Join-Path $scripts 'done.txt'
    $lastSeq = 0
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $result = 'timeout (hang?)'
    Start-Sleep -Seconds 5
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-OurGame)) { $result = 'game exited (crash?)'; break }
        if (Test-Path $req) {
            $text = Get-Content $req -Raw -ErrorAction SilentlyContinue
            if ($text -match '^(\d+) (.+)$' -and [int]$Matches[1] -gt $lastSeq) {
                $lastSeq = [int]$Matches[1]
                Write-Host ("[{0,5:N1}s] request {1}: {2}" -f $sw.Elapsed.TotalSeconds, $lastSeq, $Matches[2])
                Invoke-Request $Matches[2].Trim()
                Set-Content $done $lastSeq -NoNewline
            }
        }
        if ((Test-Path $log) -and (Select-String -Path $log -Pattern $endRx -Quiet)) { $result = 'finished'; break }
        Start-Sleep -Milliseconds 250
    }
} finally {
    Write-Host ("Run {0} after {1:N0} s." -f $result, $sw.Elapsed.TotalSeconds)
    Start-Sleep -Seconds 2
    Stop-Game
    if ($before) { $after = Get-FileState $inst }
    Restore-Core
}

$kept = Join-Path $outDir "$Scenario.log"
if (Test-Path $log) { Copy-Item $log $kept -Force } else { Write-Host "No UE4SS.log at $log" }
Add-FilesLine $kept "[run.ps1] RUN $result"
Add-FilesLine $kept (Get-FilesLine $before $after)
& pwsh -NoProfile -NonInteractive -File (Join-Path $here 'check.ps1') -Log $kept -Scenario $Scenario -CoreManifest (Join-Path $modsDir "$CoreName\mod.json")
$code = $LASTEXITCODE
if ($script:runFailures) { Write-Host "run.ps1 check(s) failed: $($script:runFailures -join ', ')"; $code = 1 }
exit $code
