<#
.SYNOPSIS
  Judges one run of the Mod Manager from UE4SS.log.
.DESCRIPTION
  Prints the Mod Manager's, the driver's and UE4SS's relevant lines, then checks the patterns the scenario needs.
  A pattern must match somewhere; "!pattern" must match nowhere; "#N|pattern" must match exactly N lines;
  "?pattern" is a soft check (reported as "warn:", never failing); "?!pattern" is a soft check that it matches nowhere.
  Then the scenario's computed checks (screen):
    - the ROW lines: Nucleus, Mod Manager, ModManagerBare, ModManagerDriver, ModManagerFixture, ModManagerLong...,
      ModManagerPak and ModManagerPakOff each exactly once, in that relative order (other installed mods may sit
      between them), with the values of the story's I/O matrix; Nucleus's and the Mod Manager's expected values come
      from their deployed mod.json (-CoreManifest; this repo's mod.json). Every status slot empty (status=0). No row
      for a UE4SS built-in, shared or NuclearNightmare-Windows.
    - MEASURE: the long name's desired width over its allotted width (cut), its right edge left of the version
      column's left edge, the header's NAME within 1 unit of the row's name.
    - INERT: no [ModManager] line between the driver's INERT begin and INERT end (the toggle boxes log nothing).
    - "[run.ps1] FILES unchanged" (run.ps1 appends it: mods.txt and the pak folders as they were after the deploy).
  Exit code 1 when any check fails; otherwise prints "All checks passed."
  Scenarios: screen, no-core, old-core (run.ps1 drives them); unit needs no log: it runs test.ps1.
  -Target vm: a log from run.ps1 -Target vm. The VM's game shares the CPU with the host, so core's "hud slow tick"
  WARN under the Mod Manager's tag is soft there.
.EXAMPLE
  ./check.ps1 -Log C:\...\nuclear-nightmare\dumps\v8.2.3-build26601774\mod-manager\screen.vm.log -Scenario screen -Target vm
#>
param(
    [string] $Instance,
    [string] $Log,
    [ValidateSet('screen', 'no-core', 'old-core', 'unit')]
    [string] $Scenario = 'screen',
    [ValidateSet('host', 'vm')] [string] $Target = 'host',
    [string] $CoreManifest # Nucleus's deployed mod.json; default: -Instance's, else the workspace's mods/Nucleus/build/package
)
if ($Scenario -eq 'unit') { & pwsh -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'test.ps1'); exit $LASTEXITCODE }
. (Join-Path $PSScriptRoot 'deploy-lib.ps1')
$CoreName = 'Nucleus'
$manifest = Get-Content (Join-Path $PSScriptRoot 'mod.json') -Raw | ConvertFrom-Json
$name = $manifest.name
$M = [regex]::Escape($name); $D = [regex]::Escape("${name}Driver"); $K = [regex]::Escape($CoreName)
$needVer = (@($manifest.dependsOn | Where-Object { Test-CoreId $_.id })[0]).version
$NeedRx = [regex]::Escape($needVer)
if (-not $Log) {
    if (-not $Instance) { Write-Host 'FAIL: pass -Log <file> or -Instance <copy>'; exit 1 }
    $Log = Join-Path (Resolve-Path $Instance) 'NuclearNightmare\Binaries\Win64\ue4ss\UE4SS.log'
}
if (-not (Test-Path $Log)) { Write-Host "FAIL: no log at $Log"; exit 1 }
if (-not $CoreManifest) {
    if ($Instance) { $CoreManifest = Join-Path (Resolve-Path $Instance) "NuclearNightmare\Binaries\Win64\ue4ss\Mods\$CoreName\mod.json" }
    else {
        # (Variable names are case-insensitive in PowerShell: nothing here may be called $M, $D or $K.)
        $up = $PSScriptRoot
        while ($up -and -not (Test-Path (Join-Path $up "mods\$CoreName\build\package\Mods\$CoreName\mod.json"))) { $up = Split-Path $up }
        if ($up) { $CoreManifest = Join-Path $up "mods\$CoreName\build\package\Mods\$CoreName\mod.json" }
    }
}

$lines = @(Get-Content $Log)
Write-Host "--- $name lines ($Scenario) ---"
$lines | Where-Object {
    $_ -match "\[$M\]|\[$D\]|^\[run\.ps1\]" -or
    $_ -match 'Error executing script|threw an exception|removing hook|Unhandled Exception|stack traceback|\[script_hook\]'
} | ForEach-Object { $_ -replace '^\[[^\]]+\]\s*', '' -replace '^\[Lua\]\s*', '' }

$always = @(
    '!Unhandled Exception'
    '!Error executing script'
    '!removing hook'
    '!stack traceback'
    '!\[script_hook\]'
    '!A function requiring userdata as param #1 was called without userdata'
    "!\[$D\] FAIL "
    "!\[$D\] .*STEP '.*' threw"
    '^\[run\.ps1\] FILES unchanged$'
)
$running = @(
    "\[$M\] CONNECT ok $K \d+\.\d+\.\d+ "
    "#1|\[$M\] READY entry=manage need=$NeedRx\s*$"
    "!\[$M\] ERROR"
    # Core's UI helpers log with the Mod Manager's tag; a slow tick of core's poller is core's to judge. In the VM every
    # slow tick is soft: the VM's game shares the CPU with the host.
    $(if ($Target -eq 'vm') { "!\[$M\] WARN (?!hud slow tick )" } else { "!\[$M\] WARN (?!hud slow tick .*(HUD event|steady state, a Lua GC step ran inside it))" })
    "?!\[$M\] WARN hud slow tick "
)
$expect = @{
    'screen' = $running + @(
        "\[$D\] SCENARIO screen\s*$"
        "\[$D\] END result=PASS"
        "\[$D\] ENTRY menu1 text=MANAGE MODS above=OPTIONS below=QUIT\s*$"
        "\[$D\] OK ENTRYPOS menu1 ", "\[$D\] OK ENTRYLOOK menu1 ", "\[$D\] OK ENTRYPOS menu2 ", "\[$D\] OK ENTRYLOOK menu2 "
        "\[$D\] OK OPEN first ", "\[$D\] OK TITLE first "
        "\[$D\] OK MEASURECUT ", "\[$D\] OK MEASUREEDGE ", "\[$D\] OK MEASUREALIGN "
        "\[$D\] OK INERT the toggle boxes changed nothing"
        "\[$D\] OK CFGTOP ", "\[$D\] OK CFGFIXTURE ", "\[$D\] OK CFGCLOSE ", "\[$D\] OK CFGDIM ", "\[$D\] OK CFGDIMOPEN "
        "\[$D\] OK BLOCKED ", "\[$D\] OK CFGCLOSE2 ", "\[$D\] OK CLOSEMAIN ", "\[$D\] OK MENUBACK "
        "\[$D\] OK ENTRYUP2 ", "\[$D\] OK OPEN after the match ", "\[$D\] OK SAME ", "\[$D\] OK CLOSEEND "
        "\[$M\] CONFIGURE \d+ "
    )
    'no-core' = @(
        "#1|\[$M\] "
        "\[$M\] $K is not installed\. $M will not run\.\s*$"
        "\[$D\] OK NOENTRY "
        "\[$D\] END result=PASS"
    )
    'old-core' = @(
        "#1|\[$M\] "
        "\[$D\] OLDCORE published $($K.ToLowerInvariant())\.version=0\.1\.0 "
        "\[$M\] ERROR $K 0\.1\.0 is older than $M needs \($NeedRx\)\. Update $K\. $M will not run\.\s*$"
        "\[$D\] OK NOENTRY "
        "\[$D\] END result=PASS"
    )
}

$failed = 0
$warned = 0
function Fail([string] $label) { Write-Host "FAIL: $label"; $script:failed++ }
function Pass([string] $label) { Write-Host "ok:   $label" }
Write-Host "--- checks ($Scenario) ---"
foreach ($pattern in ($always + $expect[$Scenario])) {
    if ($pattern.StartsWith('#')) {
        $count, $p = $pattern.Substring(1) -split '\|', 2
        $hits = @($lines | Where-Object { $_ -match $p }).Count
        if ($hits -eq [int]$count) { Pass "$pattern (found $hits)" } else { Fail "$pattern (found $hits)" }
    } elseif ($pattern.StartsWith('?!')) {
        if ($lines | Where-Object { $_ -match $pattern.Substring(2) }) { Write-Host "warn: $pattern"; $warned++ } else { Pass $pattern }
    } elseif ($pattern.StartsWith('?')) {
        if ($lines | Where-Object { $_ -match $pattern.Substring(1) }) { Pass $pattern } else { Write-Host "warn: $pattern"; $warned++ }
    } elseif ($pattern.StartsWith('!')) {
        if ($lines | Where-Object { $_ -match $pattern.Substring(1) }) { Fail $pattern } else { Pass $pattern }
    } else {
        if ($lines | Where-Object { $_ -match $pattern }) { Pass $pattern } else { Fail $pattern }
    }
}

function IndexOf([string] $p) { for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $p) { return $i } } return -1 }

if ($Scenario -eq 'screen') {
    $ic, $ir = (IndexOf "\[$M\] CONNECT ok "), (IndexOf "\[$M\] READY ")
    if ($ic -ge 0 -and $ir -gt $ic) { Pass 'READY comes after CONNECT ok' } else { Fail "READY comes after CONNECT ok (CONNECT at line $ic, READY at line $ir)" }
    $opens = @($lines | Where-Object { $_ -match "\[$M\] OPEN rows=\d+ total=\d+ lang=" }).Count
    if ($opens -ge 2) { Pass "the window opened twice or more ($opens OPEN lines)" } else { Fail "the window opened twice or more ($opens OPEN lines)" }

    # ---- ROW lines against the matrix
    $rows = @($lines | Where-Object { $_ -match "\[$D\] ROW " } | ForEach-Object {
        if ($_ -match "\[$D\] ROW (.*) \| (.*) \| toggle=(\S+) \| gear=(\S+) \| status=(-?\d+) \| need=(.*) \| build=(.*?)\s*$") {
            [pscustomobject]@{ Name = $Matches[1]; Ver = $Matches[2]; Toggle = $Matches[3]; Gear = $Matches[4]; Status = [int]$Matches[5]; Need = $Matches[6]; Build = $Matches[7] }
        } else { [pscustomobject]@{ Name = "(unparsed) $_"; Status = -1 } }
    })
    function BuildOf($mj) { $parts = @($mj.game.version, $mj.game.build | Where-Object { $_ }); if ($parts) { $parts -join ' ' } else { '-' } }
    function NeedOf($mj) { $dep = @($mj.dependsOn | Where-Object { Test-CoreId $_.id })[0]; if ($dep -and $dep.version) { $dep.version } else { '-' } }
    function GearOf($mj) { if ($mj.settings -and @($mj.settings.PSObject.Properties).Count -gt 0) { 'lit' } else { 'dim' } }
    $core = $null
    try { $core = Get-Content $CoreManifest -Raw | ConvertFrom-Json } catch { Fail "Nucleus's deployed mod.json can't be read ($CoreManifest)" }
    $long = (Get-Content (Join-Path $PSScriptRoot "test\${name}Long\mod.json") -Raw | ConvertFrom-Json)
    $fixture = (Get-Content (Join-Path $PSScriptRoot "test\${name}Fixture\mod.json") -Raw | ConvertFrom-Json)
    $want = @(
        [pscustomobject]@{ Name = $CoreName; Ver = "$($core.version)"; Toggle = 'lock'; Gear = $(if ($core) { GearOf $core } else { 'dim' }); Need = $(if ($core) { NeedOf $core } else { '-' }); Build = $(if ($core) { BuildOf $core } else { '-' }) }
        [pscustomobject]@{ Name = $manifest.displayName; Ver = $manifest.version; Toggle = 'lock'; Gear = (GearOf $manifest); Need = (NeedOf $manifest); Build = (BuildOf $manifest) }
        [pscustomobject]@{ Name = "${name}Bare"; Ver = '-'; Toggle = 'off'; Gear = 'dim'; Need = '-'; Build = '-' }
        [pscustomobject]@{ Name = "${name}Driver"; Ver = '-'; Toggle = 'on'; Gear = 'dim'; Need = '-'; Build = '-' }
        [pscustomobject]@{ Name = "${name}Fixture"; Ver = $fixture.version; Toggle = 'off'; Gear = 'lit'; Need = '>=0.1.0'; Build = 'V0.0.0 1' }
        [pscustomobject]@{ Name = $long.displayName; Ver = $long.version; Toggle = 'off'; Gear = 'dim'; Need = '>=0.2.0'; Build = (BuildOf $long) }
        [pscustomobject]@{ Name = "${name}Pak"; Ver = 'UNMANAGED'; Toggle = 'on'; Gear = 'dim'; Need = '-'; Build = '-' }
        [pscustomobject]@{ Name = "${name}PakOff"; Ver = 'UNMANAGED'; Toggle = 'off'; Gear = 'dim'; Need = '-'; Build = '-' }
    )
    $last = -1
    foreach ($w in $want) {
        $hits = @(for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i].Name -ceq $w.Name) { $i } })
        $label = "ROW $($w.Name) | $($w.Ver) | toggle=$($w.Toggle) | gear=$($w.Gear) | status=0 | need=$($w.Need) | build=$($w.Build)"
        if ($hits.Count -ne 1) { Fail "$label (found $($hits.Count) rows named so)"; continue }
        $r = $rows[$hits[0]]
        $same = $r.Ver -ceq $w.Ver -and $r.Toggle -ceq $w.Toggle -and $r.Gear -ceq $w.Gear -and $r.Status -eq 0 -and $r.Need -ceq $w.Need -and $r.Build -ceq $w.Build
        if (-not $same) { Fail "$label (got $($r.Ver) | toggle=$($r.Toggle) | gear=$($r.Gear) | status=$($r.Status) | need=$($r.Need) | build=$($r.Build))" }
        elseif ($hits[0] -le $last) { Fail "$label (out of order: row $($hits[0] + 1))" }
        else { Pass $label }
        $last = [math]::Max($last, $hits[0])
    }
    $noisy = @($rows | Where-Object { $_.Status -ne 0 })
    if ($rows.Count -and -not $noisy) { Pass "every status slot is empty ($($rows.Count) rows)" } else { Fail "every status slot is empty ($($rows.Count) rows; not: $(($noisy | ForEach-Object Name) -join ', '))" }
    $absent = @('BPML_GenericFunctions', 'BPModLoaderMod', 'CheatManagerEnablerMod', 'ConsoleCommandsMod', 'ConsoleEnablerMod', 'Keybinds', 'LineTraceMod', 'SplitScreenMod', 'shared', 'NuclearNightmare-Windows')
    $present = @($rows | Where-Object { $_.Name -in $absent })
    if (-not $present) { Pass 'no row for a UE4SS built-in, shared or NuclearNightmare-Windows' } else { Fail "rows that must be absent: $(($present | ForEach-Object Name) -join ', ')" }

    # ---- MEASURE: cut, edge, header alignment (layout units)
    $measure = @($lines | Where-Object { $_ -match "\[$D\] MEASURE name width=" })[0]
    if ($measure -and $measure -match 'width=(-?[\d.]+) desired=(-?[\d.]+) right=(-?[\d.]+) verLeft=(-?[\d.]+) headerLeft=(-?[\d.]+) rowLeft=(-?[\d.]+)') {
        $width, $desired, $right, $verLeft, $hdrLeft, $rowLeft = [double]$Matches[1], [double]$Matches[2], [double]$Matches[3], [double]$Matches[4], [double]$Matches[5], [double]$Matches[6]
        if ($width -gt 0 -and $desired -gt $width) { Pass "MEASURE the long name is cut: desired $desired > allotted $width" } else { Fail "MEASURE the long name is cut: desired $desired > allotted $width" }
        if ($right -gt 0 -and $right -le $verLeft + 0.5) { Pass "MEASURE its right edge $right is left of the version column $verLeft" } else { Fail "MEASURE its right edge $right is left of the version column $verLeft" }
        if ($hdrLeft -gt 0 -and [math]::Abs($hdrLeft - $rowLeft) -le 1) { Pass "MEASURE the header's NAME starts within 1 unit of the row's name ($hdrLeft vs $rowLeft)" } else { Fail "MEASURE the header's NAME starts within 1 unit of the row's name ($hdrLeft vs $rowLeft)" }
    } else { Fail 'MEASURE line' }

    # ---- INERT: nothing from the Mod Manager while the toggle boxes are clicked
    $ib, $ie = (IndexOf "\[$D\] INERT begin"), (IndexOf "\[$D\] INERT end")
    if ($ib -ge 0 -and $ie -gt $ib) {
        $between = @($lines[($ib + 1)..($ie - 1)] | Where-Object { $_ -match "\[$M\] " -and $_ -notmatch "\[$M\] WARN hud slow tick " })
        if (-not $between) { Pass 'INERT the toggle-box clicks logged no [ModManager] line' } else { Fail "INERT the toggle-box clicks logged: $($between -join ' / ')" }
    } else { Fail 'INERT begin/end lines' }
}

if ($failed) { Write-Host "$failed check(s) failed."; exit 1 }
Write-Host ("All checks passed{0}." -f $(if ($warned) { " ($warned soft check(s) not met)" } else { '' }))
