<#
.SYNOPSIS
  Installs the Mod Manager into a dev copy of Nuclear Nightmare, or removes it.
.DESCRIPTION
  Refuses (exit 1, one line) unless Nucleus (core) is installed in the copy, enabled in mods.txt, and its installed
  mod.json version satisfies the Mod Manager's dependsOn (a minimum, not below the installed core's compat.floor;
  deploy-lib.ps1). Core's dependsOn entry is the one whose id names Nucleus (nuclearnightmare-community.nucleus,
  compared through the id normalizer). -Force installs anyway, for the failure scenarios (the
  mod's own runtime check then has to catch it).
  Installs ue4ss/Mods/ModManager/{mod.json, Scripts/*.lua} and writes "ModManager : 1" into mods.txt right below
  Nucleus's line and above "Keybinds : 1", moving it there if it was elsewhere. Never bundles any of core's files.
  -Test also installs the test driver (test/ModManagerDriver as Mods/ModManagerDriver, between Nucleus and the Mod
  Manager) with the scenario in its Scripts/scenario.txt, and the fixtures the screen scenario reads:
    Mods/ModManagerFixture   mod.json only, "ModManagerFixture : 0" in mods.txt
    Mods/ModManagerBare      an empty Scripts/, no mods.txt line
    Mods/ModManagerLong      mod.json with a 64-character displayName, no mods.txt line
    Mods/ModManagerBase      mod.json only (story 6: a mod others need), "ModManagerBase : 1"
    Mods/ModManagerDep       mod.json only, needing ModManagerBase, "ModManagerDep : 1"
    Content/Paks/ModManagerPak_P.pak and ModManagerPakOff_P.pak.disabled (build/fixtures/ModManagerPak_P.pak,
                             built by build.ps1 -Fixtures, which this runs when the file is missing)
    Mods/ModManagerRestart   story 8, only with -Scenario restart: mod.json and a Scripts/main.lua that logs
                             "[ModManagerRestart] loaded", "ModManagerRestart : 1"
  Mod Manager v2 story 3, only with -Scenario apply: no fixture mod of its own. test/ModManagerApplyA is staged as a
  change (plan A, written by Nucleus's native/test/New-StagedPlan.ps1 from the workspace that holds the instance) into
  ue4ss/NucleusData/staged/, for core's relaunch helper to install; a copy of its files goes to the driver's
  Scripts/apply-expect/ModManagerApplyA/ (what session 4 compares A's installed files with). It refuses when a change
  that is not the scenario's is already staged there. ModManagerApplyB and C are staged by the run ("stage B|C").
  Mod Manager v2 story 5, only with -Scenario install (VM only: -Staged): no fixture of its own; the copy must have no
  HudClock (the live catalog's HUD Clock, which the scenario installs through core): Mods/HudClock, its paks and its
  mods.txt line are taken out of the stage, so the VM run moves the VM copy's HudClock aside and its restore puts it back.
  A deploy without -Test removes the driver and the fixtures. -Remove deletes all of it and their mods.txt lines;
  nothing else changes (mods.txt keeps its bytes when it had none of these lines). Both also delete the apply
  fixtures' folders (core's helper installs them) and a staged change of only those fixtures (NucleusData/staged/).
  -Staged: $Instance is the host-side staging folder of a VM run (run.ps1 -Target vm, tools/vm/vm-sp.ps1), not a game
  copy; only the running-game check is skipped.
  Pass the main checkout's instance path when running from a worktree.
.EXAMPLE
  ./deploy.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774
  ./deploy.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774 -Test -Scenario screen
  ./deploy.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774 -Remove
#>
param(
    [Parameter(Mandatory)] [string] $Instance,
    [switch] $Test,
    [ValidateSet('screen', 'no-core', 'old-core', 'restart', 'apply', 'browse', 'install')]
    [string] $Scenario = 'screen',
    [switch] $Force,
    [switch] $Remove,
    [switch] $Staged
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-lib.ps1')

$CoreName = 'Nucleus' # core's folder and mods.txt name: the one place this script spells it
$here     = $PSScriptRoot
$manifest = Get-Content (Join-Path $here 'mod.json') -Raw | ConvertFrom-Json
$name     = $manifest.name
$driver   = "${name}Driver"
$fixtures = @("${name}Fixture", "${name}Bare", "${name}Long", "${name}Base", "${name}Dep", "${name}Restart") # Restart: story 8, restart scenario only
$fixturePaks = @("${name}Pak_P.pak", "${name}PakOff_P.pak.disabled")
$applyFixtures = @(Get-ApplyFixtures $name) # Mod Manager v2 story 3: installed only by core's helper, from staged changes
$inst     = (Resolve-Path $Instance).Path
$win64    = Join-Path $inst 'NuclearNightmare\Binaries\Win64'
$ue4ss    = Join-Path $win64 'ue4ss'
$modsDir  = Join-Path $ue4ss 'Mods'
$modsTxt  = Join-Path $modsDir 'mods.txt'
$paksDir  = Join-Path $inst 'NuclearNightmare\Content\Paks'
$coreData = Join-Path $ue4ss "${CoreName}Data"   # core's data folder (staged changes: staged\)
$installTarget = 'HudClock' # Mod Manager v2 story 5: the install scenario's mod (the live catalog's HUD Clock)

function Stop-Deploy([string] $why) { Write-Host "$name not deployed: $why"; exit 1 }

if (-not (Test-Path (Join-Path $win64 'NuclearNightmare-Win64-Shipping.exe'))) { Stop-Deploy "not a game instance: $inst" }
if (-not (Test-Path (Join-Path $ue4ss 'UE4SS.dll'))) { Stop-Deploy "UE4SS is not installed in $win64" }
if (-not (Test-Path $modsTxt)) { Stop-Deploy "no mods.txt in $modsDir" }
if (-not $Staged -and (Get-Process -Name 'NuclearNightmare*' -ErrorAction SilentlyContinue)) { Stop-Deploy 'Nuclear Nightmare is running; close it first.' }

$file  = Read-ModsTxt $modsTxt
$mine  = @($name, $driver) + $fixtures + $applyFixtures
# Story 5 (v2): the install scenario installs HudClock itself, so the copy starts without it (VM stage only).
if ($Test -and $Scenario -eq 'install') {
    if (-not $Staged) { Stop-Deploy 'the install scenario runs only in the VM (run.ps1 -Scenario install), which deploys into its stage with -Staged.' }
    $mine += $installTarget
}
$clean = Edit-ModsTxt -Lines $file.Lines -Remove $mine

# Story 3 (v2): a staged change of the apply scenario's fixtures only; any other staged change is left alone.
function Remove-ApplyStaged {
    $staged = Join-Path $coreData 'staged'
    if (Test-ApplyPlanOurs -Plan (Join-Path $staged 'plan.txt') -Name $name) { Remove-Item $staged -Recurse -Force }
}
function Remove-Test {
    foreach ($d in @($driver) + $fixtures + $applyFixtures) { Remove-Item (Join-Path $modsDir $d) -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($p in $fixturePaks) { Remove-Item (Join-Path $paksDir $p) -Force -ErrorAction SilentlyContinue }
    Remove-ApplyStaged
}

if ($Remove) {
    Remove-Item (Join-Path $modsDir $name) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Test
    if ($clean.Count -ne $file.Lines.Count) { Write-ModsTxt $modsTxt $file $clean }
    Write-Host "$name removed (and its driver and fixtures, if they were installed)."
    return
}

# Core: installed, enabled, and a version the Mod Manager's dependsOn accepts.
$dep = @($manifest.dependsOn | Where-Object { Test-CoreId $_.id })[0]
if (-not $dep) { throw "mod.json has no dependsOn entry for $CoreId" }
$coreJson = Join-Path $modsDir "$CoreName\mod.json"
$problem = $null
if (-not (Test-Path $coreJson)) {
    $problem = "$CoreName is not installed in $modsDir (no $CoreName\mod.json); install it first with its own deploy.ps1."
} else {
    $core = $null
    try { $core = Get-Content $coreJson -Raw | ConvertFrom-Json } catch { }
    $state = Get-ModsTxtState -Lines $clean -Name $CoreName
    $floor = $null
    try { $floor = $core.compat.floor } catch { }
    $fit = if ($core) { Test-VersionNeed -Version $core.version -Need $dep.version -Floor $floor }
    if (-not $core -or -not (Test-CoreId $core.id)) {
        $problem = "$coreJson is not $CoreName's manifest (id '$($core.id)', expected '$CoreId')."
    } elseif ($fit -in 'core-too-old', 'bad-have') {
        $problem = "$CoreName $($core.version) is installed, but $name needs $($dep.version); update $CoreName."
    } elseif ($fit -eq 'mod-too-old') {
        $problem = "$name was made for $CoreName $($dep.version), which this $CoreName $($core.version) no longer supports (oldest: $floor); update $name."
    } elseif ($state -ne 'enabled') {
        $problem = "$CoreName is installed but $state in mods.txt; enable it ('$CoreName : 1', its first line)."
    }
}
if ($problem) {
    if (-not $Force) { Stop-Deploy $problem }
    Write-Warning "forced: $problem"
}

# Story 3 (v2): the apply scenario stages plan A with core's plan writer, from the workspace holding the instance (the
# stage of a VM run is <workspace>\game-instances\_vmstage). Checked before anything is written.
$planWriter = Join-Path (Split-Path (Split-Path $inst)) "mods\$CoreName\native\test\New-StagedPlan.ps1"
if ($Test -and $Scenario -eq 'apply') {
    if (-not (Test-Path -LiteralPath $planWriter)) { Stop-Deploy "the apply scenario needs core's plan writer, missing at $planWriter (Nucleus 0.24.0 or newer, its native/test/New-StagedPlan.ps1)." }
    $plan = Join-Path $coreData 'staged\plan.txt'
    if ((Test-Path -LiteralPath $plan) -and -not (Test-ApplyPlanOurs -Plan $plan -Name $name)) { Stop-Deploy "a change is already staged in $(Split-Path $plan) that is not the apply scenario's; leave it to core, or remove it by hand." }
}

# The fixture pak (screen scenario): built once by build.ps1 -Fixtures.
$fixturePak = Join-Path $here "build\fixtures\${name}Pak_P.pak"
if ($Test -and -not (Test-Path $fixturePak)) {
    & pwsh -NoProfile -NonInteractive -File (Join-Path $here 'build.ps1') -Fixtures | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $fixturePak)) { throw "build.ps1 -Fixtures did not make $fixturePak" }
}

# The Mod Manager's files.
Remove-Item (Join-Path $modsDir $name) -Recurse -Force -ErrorAction SilentlyContinue
Remove-Test
$dest = Join-Path $modsDir "$name\Scripts"
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $here 'mod.json') (Join-Path $modsDir $name) -Force
foreach ($f in $ModScripts) { Copy-Item (Join-Path $here "Scripts\$f") $dest -Force }

# mods.txt: below core, above Keybinds. The driver goes between core and the Mod Manager (its old-core mode must run
# before the Mod Manager's main.lua); the fixture's line is off.
$add = @($name)
$off = @()
if ($Test) {
    Copy-Item (Join-Path $here "test\$driver") (Join-Path $modsDir $driver) -Recurse -Force
    foreach ($f in 'scenario.txt', 'request.txt', 'done.txt', 'restart-facts.txt', 'apply-session.txt', 'install-session.txt') { Remove-Item (Join-Path $modsDir "$driver\Scripts\$f") -ErrorAction SilentlyContinue }
    [IO.File]::WriteAllText((Join-Path $modsDir "$driver\Scripts\scenario.txt"), $Scenario)
    New-Item -ItemType Directory -Force (Join-Path $modsDir "${name}Fixture"), (Join-Path $modsDir "${name}Bare\Scripts"), (Join-Path $modsDir "${name}Long") | Out-Null
    Copy-Item (Join-Path $here "test\${name}Fixture\mod.json") (Join-Path $modsDir "${name}Fixture") -Force
    Copy-Item (Join-Path $here "test\${name}Long\mod.json") (Join-Path $modsDir "${name}Long") -Force
    foreach ($f in "${name}Base", "${name}Dep") {
        New-Item -ItemType Directory -Force (Join-Path $modsDir $f) | Out-Null
        Copy-Item (Join-Path $here "test\$f\mod.json") (Join-Path $modsDir $f) -Force
    }
    New-Item -ItemType Directory -Force $paksDir | Out-Null
    Copy-Item $fixturePak (Join-Path $paksDir $fixturePaks[0]) -Force
    Copy-Item $fixturePak (Join-Path $paksDir $fixturePaks[1]) -Force
    $add = @($driver, $name, "${name}Base", "${name}Dep")
    $off = @("${name}Fixture")
    if ($Scenario -eq 'restart') {
        # Story 8: the mod the scenario turns off before RESTART NOW (the relaunched game must not load it).
        Copy-Item (Join-Path $here "test\${name}Restart") (Join-Path $modsDir "${name}Restart") -Recurse -Force
        $add += "${name}Restart"
    }
    if ($Scenario -eq 'install') {
        # Story 5 (v2): no HudClock in the stage (its folder and paks; its mods.txt line went with $mine above).
        Remove-Item (Join-Path $modsDir $installTarget) -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($p in (Join-Path $paksDir "LogicMods\$installTarget.pak"), (Join-Path $paksDir "${installTarget}_P.pak")) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
        Write-Host "No $installTarget in the stage: the install scenario installs it through core."
    }
    if ($Scenario -eq 'apply') {
        # Story 3 (v2): plan A staged for core's helper (the Mod Manager starts it at launch), and the driver's copy of A's
        # files to compare the installed ones with after plan C's rollback.
        $expect = Join-Path $modsDir "$driver\Scripts\apply-expect"
        New-Item -ItemType Directory -Force $expect | Out-Null
        Copy-Item (Join-Path $here "test\$($applyFixtures[0])") (Join-Path $expect $applyFixtures[0]) -Recurse -Force
        $txn = New-ApplyPlan -Writer $planWriter -Data $coreData -Repo $here -Name $name -Plan A
        Write-Host "Staged plan A (txn $txn) in $(Join-Path $coreData 'staged')"
    }
}
$lines = Edit-ModsTxt -Lines $clean -Add $add -Disabled $off -After $CoreName
Write-ModsTxt $modsTxt $file $lines

Write-Host "$name $($manifest.version) deployed$(if ($Test) { " with $driver (scenario $Scenario) and the fixtures" }):"
Get-ChildItem (Join-Path $modsDir $name) -Recurse -File | ForEach-Object { Write-Host "  Mods/$name/$($_.FullName.Substring((Join-Path $modsDir $name).Length + 1)) ($($_.Length) bytes)" }
if ($Test) { foreach ($p in $fixturePaks) { Write-Host "  Content/Paks/$p" } }
Write-Host "mods.txt: $(($lines | Where-Object { $_ -match '^\s*[\w-]+\s*:\s*\d' }) -join ', ')"
