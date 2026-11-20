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
  A deploy without -Test removes the driver and the fixtures. -Remove deletes all of it and their mods.txt lines;
  nothing else changes (mods.txt keeps its bytes when it had none of these lines).
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
    [ValidateSet('screen', 'no-core', 'old-core', 'restart')]
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
$inst     = (Resolve-Path $Instance).Path
$win64    = Join-Path $inst 'NuclearNightmare\Binaries\Win64'
$ue4ss    = Join-Path $win64 'ue4ss'
$modsDir  = Join-Path $ue4ss 'Mods'
$modsTxt  = Join-Path $modsDir 'mods.txt'
$paksDir  = Join-Path $inst 'NuclearNightmare\Content\Paks'

function Stop-Deploy([string] $why) { Write-Host "$name not deployed: $why"; exit 1 }

if (-not (Test-Path (Join-Path $win64 'NuclearNightmare-Win64-Shipping.exe'))) { Stop-Deploy "not a game instance: $inst" }
if (-not (Test-Path (Join-Path $ue4ss 'UE4SS.dll'))) { Stop-Deploy "UE4SS is not installed in $win64" }
if (-not (Test-Path $modsTxt)) { Stop-Deploy "no mods.txt in $modsDir" }
if (-not $Staged -and (Get-Process -Name 'NuclearNightmare*' -ErrorAction SilentlyContinue)) { Stop-Deploy 'Nuclear Nightmare is running; close it first.' }

$file  = Read-ModsTxt $modsTxt
$mine  = @($name, $driver) + $fixtures
$clean = Edit-ModsTxt -Lines $file.Lines -Remove $mine

function Remove-Test {
    foreach ($d in @($driver) + $fixtures) { Remove-Item (Join-Path $modsDir $d) -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($p in $fixturePaks) { Remove-Item (Join-Path $paksDir $p) -Force -ErrorAction SilentlyContinue }
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
    foreach ($f in 'scenario.txt', 'request.txt', 'done.txt', 'restart-facts.txt') { Remove-Item (Join-Path $modsDir "$driver\Scripts\$f") -ErrorAction SilentlyContinue }
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
}
$lines = Edit-ModsTxt -Lines $clean -Add $add -Disabled $off -After $CoreName
Write-ModsTxt $modsTxt $file $lines

Write-Host "$name $($manifest.version) deployed$(if ($Test) { " with $driver (scenario $Scenario) and the fixtures" }):"
Get-ChildItem (Join-Path $modsDir $name) -Recurse -File | ForEach-Object { Write-Host "  Mods/$name/$($_.FullName.Substring((Join-Path $modsDir $name).Length + 1)) ($($_.Length) bytes)" }
if ($Test) { foreach ($p in $fixturePaks) { Write-Host "  Content/Paks/$p" } }
Write-Host "mods.txt: $(($lines | Where-Object { $_ -match '^\s*[\w-]+\s*:\s*\d' }) -join ', ')"
