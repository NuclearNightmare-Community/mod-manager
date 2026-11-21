<#
.SYNOPSIS
  Unit tests for deploy-lib.ps1 (version needs, core ids, mods.txt editing) and deploy.ps1 end to end against a fake
  game instance in a temp folder (never a real copy: no game, no UE4SS, only the files deploy.ps1 looks at), and
  build.ps1's package.
.EXAMPLE
  pwsh -NoProfile -File test/unit/deploy_test.ps1
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
. (Join-Path $repo 'deploy-lib.ps1')
$script:passed = 0; $script:failed = 0
function Ok([bool] $cond, [string] $name, $detail) {
    if ($cond) { $script:passed++ } else { $script:failed++; Write-Host "FAIL $name$(if ($null -ne $detail) { " -- $detail" })" }
}
function Eq($got, $want, [string] $name) { Ok ($got -eq $want) $name "got '$got', want '$want'" }
function Throws([scriptblock] $b, [string] $text, [string] $name) {
    try { & $b; Ok $false $name 'did not throw' } catch { Ok ($_.Exception.Message -like "*$text*") $name $_.Exception.Message }
}

# ---------------------------------------------------------------- version needs (core story 18's rule, as Clock's)
$cases = @(
    @('0.8.0', '>=0.8.0', $null, 'ok'), @('0.9.0', '>=0.8.0', $null, 'ok'), @('1.0.0', '>=0.8.0', '0.1.0', 'ok'),
    @('0.7.0', '>=0.8.0', $null, 'core-too-old'), @('0.1.0', '>=0.8.0', $null, 'core-too-old'),
    @('0.9.0', '>=0.8.0', '0.9.0', 'mod-too-old'), @('0.9.0', '>=0.8.0', 'x', 'ok'),
    @('0.8', '>=0.8.0', $null, 'bad-have'), @($null, '>=0.8.0', $null, 'bad-have')
)
foreach ($c in $cases) { Eq (Test-VersionNeed -Version $c[0] -Need $c[1] -Floor $c[2]) $c[3] "need: '$($c[0])' for '$($c[1])' (floor '$($c[2])')" }
Throws { Test-VersionNeed -Version '0.8.0' -Need '<0.9.0' } 'unsupported version need' 'need: a bad need throws'

# ---------------------------------------------------------------- core ids (the shared cases of core's nucleus.modid)
# The workspace's shared cases (tools/release/tests/modid-cases.json): ConvertTo-ModId must accept and refuse the same
# ids and return the same normalized id (it returns no message). The file is $env:NN_MODID_CASES when set (the ci
# workflow: the ci repo's synced copy), else in the workspace, the parent of mods/, found from the repo's git common
# dir so a worktree finds it too.
$common = git -C $repo rev-parse --path-format=absolute --git-common-dir 2>$null
$casesFile = if ($env:NN_MODID_CASES) { $env:NN_MODID_CASES } elseif ($common) { Join-Path (Split-Path (Split-Path (Split-Path $common))) 'tools/release/tests/modid-cases.json' }
if ($casesFile -and (Test-Path -LiteralPath $casesFile)) {
    $shared = Get-Content -LiteralPath $casesFile -Raw | ConvertFrom-Json
    $n = 0
    foreach ($c in $shared.cases) {
        $n++
        $want = if ($c.PSObject.Properties.Name -ccontains 'id') { $c.id } else { $null }
        $got = ConvertTo-ModId $c.input
        Ok ($got -ceq $want) "shared case '$($c.name)'" "got '$got', want '$want'"
    }
    Ok ($n -ge 40) 'shared cases: read' $n
} elseif ($env:NN_MODID_CASES) {
    # Set but missing: a misconfigured CI must fail, not skip.
    Ok $false 'shared cases: NN_MODID_CASES names an existing file' "missing: $env:NN_MODID_CASES"
} else {
    Write-Host "NOTE the workspace's tools/release/tests/modid-cases.json is absent: the shared id cases are skipped"
}
Ok (Test-CoreId 'nuclearnightmare-community.nucleus') 'core id: the namespaced id'
Ok (Test-CoreId 'github.com/NuclearNightmare-Community.Nucleus') 'core id: the long form'
Ok (-not (Test-CoreId 'nucleus') -and -not (Test-CoreId 'Nucleus')) 'core id: the bare nucleus is not core (the legacy alias is gone)'
Ok (-not (Test-CoreId 'other.nucleus') -and -not (Test-CoreId 'www.github.com/NuclearNightmare-Community.nucleus') -and -not (Test-CoreId $null)) 'core id: others are not core'

# ---------------------------------------------------------------- mods.txt editing
$stock = @('CheatManagerEnablerMod : 1', 'BPModLoaderMod : 1', 'Keybinds : 1', '', '; comment')
$withCore = @('Nucleus : 1') + $stock
$r = Edit-ModsTxt -Lines $withCore -Add @('ModManagerDriver', 'ModManager') -Disabled @('ModManagerFixture') -After 'Nucleus'
Eq ($r -join '|') (@('Nucleus : 1', 'ModManagerDriver : 1', 'ModManager : 1', 'ModManagerFixture : 0') + $stock -join '|') 'mods.txt: driver, mod, then the fixture off, below Nucleus'
$r = Edit-ModsTxt -Lines (@('ModManagerFixture : 1', 'ModManager : 1') + $withCore) -Add @('ModManager') -Disabled @('ModManagerFixture') -After 'Nucleus'
Eq ($r -join '|') (@('Nucleus : 1', 'ModManager : 1', 'ModManagerFixture : 0') + $stock -join '|') 'mods.txt: old lines (above Nucleus, on) replaced'
$r = Edit-ModsTxt -Lines @('Nucleus : 1', 'ModManager : 1', 'ModManagerX : 1', 'Keybinds : 1') -Remove @('ModManager')
Eq ($r -join '|') 'Nucleus : 1|ModManagerX : 1|Keybinds : 1' 'mods.txt: remove only ModManager (not ModManagerX)'
$r = Edit-ModsTxt -Lines $stock -Add @('ModManager') -After 'Nucleus'
Eq ($r[2]) 'ModManager : 1' 'mods.txt: no Nucleus line -> above Keybinds'
$r = Edit-ModsTxt -Lines @('Keybinds : 1', 'Nucleus : 1') -Add @('ModManager') -After 'Nucleus'
Eq ($r -join '|') 'ModManager : 1|Keybinds : 1|Nucleus : 1' 'mods.txt: Nucleus below Keybinds -> still above Keybinds'

# ---------------------------------------------------------------- mod.json and main.lua
$m = Get-Content (Join-Path $repo 'mod.json') -Raw | ConvertFrom-Json
Ok ($m.id -eq 'nuclearnightmare-community.mod-manager' -and $m.name -eq 'ModManager' -and $m.displayName -eq 'Mod Manager' -and $m.scope -eq 'client') 'mod.json: id, name, displayName, scope'
Ok ($m.version -match '^\d+\.\d+\.\d+$') 'mod.json: semver version'
Ok ($m.name -cmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') 'mod.json: name is a folder name (no space: UE4SS removes spaces from mods.txt lines)'
Ok ($m.dependsOn.Count -eq 1 -and $m.dependsOn[0].id -eq 'nuclearnightmare-community.nucleus' -and $m.dependsOn[0].version -eq '>=0.25.0') 'mod.json: dependsOn nuclearnightmare-community.nucleus >=0.25.0'
Ok ($m.ue4ss -eq 'v3.0.1-1181-g83330635' -and $m.game.version -eq 'V8.2.3' -and $m.game.build -eq '26601774') 'mod.json: ue4ss and game build'
Ok ($null -eq $m.settings) 'mod.json: no settings (the gear is dimmed)'
$mainLua = Get-Content (Join-Path $repo 'Scripts\main.lua') -Raw
Ok ($mainLua -match 'local CORE, NEED, ME = "Nucleus", ">=0.25.0", "ModManager"') 'main.lua: NEED = dependsOn (>=0.25.0)'
foreach ($f in $ModScripts) { Ok (Test-Path (Join-Path $repo "Scripts\$f")) "Scripts/$f exists" }
$long = Get-Content (Join-Path $repo 'test\ModManagerLong\mod.json') -Raw | ConvertFrom-Json
Ok ($long.displayName.Length -eq 64 -and $long.displayName.StartsWith('ModManagerLong') -and $long.dependsOn[0].id -eq 'nuclearnightmare-community.nucleus' -and $long.dependsOn[0].version -eq '>=0.2.0') 'fixture Long: 64-character displayName, nuclearnightmare-community.nucleus >=0.2.0'
$fx = Get-Content (Join-Path $repo 'test\ModManagerFixture\mod.json') -Raw | ConvertFrom-Json
Ok ($fx.version -eq '9.9.9' -and $fx.game.version -eq 'V0.0.0' -and $fx.game.build -eq '1' -and $fx.dependsOn[0].version -eq '>=0.1.0') 'fixture: 9.9.9, V0.0.0/1, >=0.1.0'
# Story 6: the fixture's settings (one of each kind of the Settings matrix row) and its two dependency problems.
$st = $fx.settings
Ok ($st.flag.type -eq 'bool' -and $st.example.type -eq 'int' -and $st.example.min -eq 1 -and $st.example.max -eq 9 -and $st.ratio.type -eq 'number' -and $st.ratio.step -eq 0.1 -and
    $st.mode.type -eq 'enum' -and $st.later.changeable -eq 'restart' -and $st.preset.source -eq 'presets' -and $st.free.type -eq 'int' -and $null -eq $st.free.min) 'fixture: bool, int 1-9, number 0-1 step 0.1, enum, restart, source presets, int without bounds'
Ok (@($fx.dependsOn | Where-Object { $_.id -eq 'nuclearnightmare-community.mod-manager-missing' }).Count -eq 1 -and @($fx.dependsOn | Where-Object { $_.id -eq 'nuclearnightmare-community.mod-manager-base' -and $_.version -eq '>=2.0.0' }).Count -eq 1) 'fixture: needs a missing id and base >=2.0.0'
$base = Get-Content (Join-Path $repo 'test\ModManagerBase\mod.json') -Raw | ConvertFrom-Json
$depm = Get-Content (Join-Path $repo 'test\ModManagerDep\mod.json') -Raw | ConvertFrom-Json
Ok ($base.id -eq 'nuclearnightmare-community.mod-manager-base' -and $base.version -eq '1.0.0' -and $base.displayName -eq 'Mod Manager Base' -and $base.game.version -eq 'V8.2.3') 'fixture Base: id, 1.0.0, Mod Manager Base, V8.2.3'
Ok ($depm.id -eq 'nuclearnightmare-community.mod-manager-dep' -and $depm.displayName -eq 'Mod Manager Dep' -and $depm.dependsOn[0].id -eq $base.id -and $depm.dependsOn[0].version -eq '>=1.0.0') 'fixture Dep: needs Base >=1.0.0'

# ---------------------------------------------------------------- Mod Manager v2 story 3: the apply scenario's plans
$fa = Get-ApplyFixtures 'ModManager'
Eq ($fa -join ',') 'ModManagerApplyA,ModManagerApplyB,ModManagerApplyC' 'apply: the fixtures A, B, C'
foreach ($x in $fa) {
    $mj = Get-Content (Join-Path $repo "test\$x\mod.json") -Raw | ConvertFrom-Json
    $ml = Get-Content (Join-Path $repo "test\$x\Scripts\main.lua") -Raw
    Ok ($mj.name -ceq $x -and $mj.id -ceq "nuclearnightmare-community.mod-manager-apply-$($x.Substring(15).ToLowerInvariant())" -and $mj.version -eq '1.0.0' -and $mj.scope -eq 'client' -and @($mj.dependsOn).Count -eq 0) "fixture ${x}: mod.json"
    Ok ($ml.Contains("print(`"[$x] loaded\n`")") -and $ml.Contains("ModRef:SetSharedVariable(`"$($x.ToLowerInvariant()).loaded`", true)")) "fixture ${x}: logs [$x] loaded and sets $($x.ToLowerInvariant()).loaded"
}
$lockT = Get-ApplyLockTarget 'ModManager'
Eq $lockT 'NuclearNightmare\Binaries\Win64\ue4ss\Mods\ModManagerApplyA\Scripts\main.lua' 'apply: the locked file is A''s Scripts\main.lua'
$oa = @(Get-ApplyPlanOps -Repo $repo -Name 'ModManager' -Plan A)
Eq (($oa | ForEach-Object { "$($_.Op):$($_.Owner)$($_.Name):$($_.Target)$($_.Value)" }) -join '|') ('put:ModManagerApplyA:NuclearNightmare\Binaries\Win64\ue4ss\Mods\ModManagerApplyA\mod.json|' +
    'put:ModManagerApplyA:NuclearNightmare\Binaries\Win64\ue4ss\Mods\ModManagerApplyA\Scripts\main.lua|modstxt:ModManagerApplyA:on') 'apply: plan A''s operations'
Ok ((Test-Path $oa[0].Source) -and (Test-Path $oa[1].Source)) 'apply: plan A puts the fixture''s own files'
$oc = @(Get-ApplyPlanOps -Repo $repo -Name 'ModManager' -Plan C)
Ok ($oc.Count -eq 4 -and $oc[0].Target -like '*\ModManagerApplyC\mod.json' -and $oc[1].Target -like '*\ModManagerApplyC\Scripts\main.lua' -and $oc[2].Target -ceq $lockT -and
    $oc[3].Op -eq 'modstxt' -and $oc[3].Name -ceq 'ModManagerApplyC') 'apply: plan C puts C''s files, then over A''s locked file, then turns C on'
Ok ($oc[2].Text -and $oc[2].Text -cne (Get-Content (Join-Path $repo 'test\ModManagerApplyA\Scripts\main.lua') -Raw)) 'apply: plan C''s file for A differs from A''s'
Throws { Get-ApplyPlanOps -Repo $repo -Name 'ModManager' -Plan D } 'does not belong to the set' 'apply: no plan D'
$ptmp = Join-Path ([IO.Path]::GetTempPath()) ("mod-manager-plan-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
function Ours([string] $text) { [IO.File]::WriteAllText($ptmp, $text); Test-ApplyPlanOurs -Plan $ptmp -Name 'ModManager' }
$h = "nucleus-plan`t1`ntxn`t$('0' * 32)`n"; $pre = 'NuclearNightmare\Binaries\Win64\ue4ss\Mods'
Ok (Ours ($h + "put`tModManagerApplyC`t$('a' * 64)`t5`t$pre\ModManagerApplyA\Scripts\main.lua`nmodstxt`tModManagerApplyC`ton`n")) 'apply: a plan of the fixtures is ours'
Ok (Ours ($h + "delete`tModManagerApplyB`t-`t$pre\ModManagerApplyB\x.lua`n")) 'apply: a delete in a fixture is ours'
Ok (-not (Ours ($h + "put`tOther`t$('a' * 64)`t5`t$pre\ModManagerApplyA\x.lua`n"))) 'apply: another owner is not ours'
Ok (-not (Ours ($h + "put`tModManagerApplyA`t$('a' * 64)`t5`t$pre\Other\x.lua`n"))) 'apply: a target outside the fixtures is not ours'
Ok (-not (Ours ($h + "put`tModManagerApplyA`t$('a' * 64)`t5`t$pre\ModManagerApplyAX\x.lua`n"))) 'apply: a folder that only starts like a fixture is not ours'
Ok (-not (Ours ($h + "modstxt`tOther`ton`n"))) 'apply: another mods.txt name is not ours'
Ok (-not (Ours ($h + "rename`tModManagerApplyA`n"))) 'apply: an unknown operation is not ours'
Ok (-not (Ours $h)) 'apply: a plan without operations is not ours'
Remove-Item $ptmp -ErrorAction SilentlyContinue
Ok (-not (Test-ApplyPlanOurs -Plan $ptmp -Name 'ModManager')) 'apply: no plan is not ours'
# Core's plan writer (Nucleus 0.24.0's native/test/New-StagedPlan.ps1), for the apply deploy cases: from NN_NUCLEUS (the
# ci workflow's Nucleus checkout), else the Nucleus checkout beside this repo's main checkout.
$nucleusRepo = if ($env:NN_NUCLEUS) { $env:NN_NUCLEUS } elseif ($common) { Join-Path (Split-Path (Split-Path $common)) 'Nucleus' }
$writerSrc = if ($nucleusRepo -and (Test-Path (Join-Path $nucleusRepo 'native\test\New-StagedPlan.ps1'))) { Join-Path $nucleusRepo 'native\test\New-StagedPlan.ps1' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mod-manager-deploy-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp | Out-Null
try {
    # ------------------------------------------------------------ build.ps1: the package holds mod.json and Scripts only
    $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $repo 'build.ps1') 2>&1 | Out-String
    Ok ($LASTEXITCODE -eq 0) 'build: exit 0' $out
    $pkg = Join-Path $repo 'build\package'
    $files = @(Get-ChildItem $pkg -Recurse -File | ForEach-Object { $_.FullName.Substring($pkg.Length + 1).Replace('\', '/') } | Sort-Object)
    $wantFiles = @('Mods/ModManager/mod.json') + @($ModScripts | ForEach-Object { "Mods/ModManager/Scripts/$_" }) | Sort-Object
    Eq ($files -join ',') ($wantFiles -join ',') 'build: Mods/ModManager/{mod.json, Scripts/*.lua} only'

    # ------------------------------------------------------------ deploy.ps1 end to end, fake instance
    $inst = Join-Path $tmp 'game-instances\fake'
    $win64 = Join-Path $inst 'NuclearNightmare\Binaries\Win64'
    $mods = Join-Path $win64 'ue4ss\Mods'
    $paks = Join-Path $inst 'NuclearNightmare\Content\Paks'
    New-Item -ItemType Directory -Force (Join-Path $mods 'Nucleus\Scripts'), (Join-Path $mods 'Keybinds'), (Join-Path $paks 'LogicMods') | Out-Null
    Set-Content (Join-Path $win64 'NuclearNightmare-Win64-Shipping.exe') 'fake'
    Set-Content (Join-Path $win64 'ue4ss\UE4SS.dll') 'fake'
    Set-Content (Join-Path $paks 'NuclearNightmare-Windows.pak') 'fake'
    $stockTxt = "CheatManagerEnablerMod : 1`r`nBPModLoaderMod : 1`r`nKeybinds : 1`r`n"
    $coreTxt = "Nucleus : 1`r`n" + $stockTxt
    $modsTxt = Join-Path $mods 'mods.txt'
    $coreJson = Join-Path $mods 'Nucleus\mod.json'
    function Set-Core([string] $version, [string] $floor, [string] $id = 'nuclearnightmare-community.nucleus') {
        $compat = if ($floor) { ", `"compat`": { `"floor`": `"$floor`" }" } else { '' }
        Set-Content $coreJson "{ `"id`": `"$id`", `"name`": `"Nucleus`", `"version`": `"$version`"$compat }"
    }
    function Deploy([string[]] $a) {
        $cmd = "function Get-Process { }; & '$(Join-Path $repo 'deploy.ps1')' -Instance '$inst' $($a -join ' '); exit `$LASTEXITCODE"
        $out = & pwsh -NoProfile -NonInteractive -Command $cmd 2>&1 | Out-String
        return @{ Code = $LASTEXITCODE; Out = $out }
    }
    function Txt { [IO.File]::ReadAllText($modsTxt) }
    function Names([string] $d) { (@(Get-ChildItem $d -File | ForEach-Object Name | Sort-Object)) -join ',' }

    # Core missing.
    [IO.File]::WriteAllText($modsTxt, $stockTxt)
    Remove-Item (Join-Path $mods 'Nucleus') -Recurse -Force
    $d = Deploy @()
    Ok ($d.Code -eq 1 -and $d.Out -match 'ModManager not deployed: Nucleus is not installed') 'deploy: core missing -> refused' $d.Out
    Ok (($d.Out.Trim() -split "`r?`n").Count -eq 1) 'deploy: refusal is one line' $d.Out
    Ok (-not (Test-Path (Join-Path $mods 'ModManager'))) 'deploy: refused -> nothing installed'
    Eq (Txt) $stockTxt 'deploy: refused -> mods.txt untouched'

    # Core too old, floor, not core's manifest, disabled.
    New-Item -ItemType Directory -Force (Join-Path $mods 'Nucleus\Scripts') | Out-Null
    [IO.File]::WriteAllText($modsTxt, $coreTxt)
    Set-Core '0.20.0'
    $d = Deploy @()
    Ok ($d.Code -eq 1 -and $d.Out -match 'Nucleus 0\.20\.0 is installed, but ModManager needs >=0.25.0; update Nucleus\.') 'deploy: core 0.20.0 -> refused, naming both versions' $d.Out
    Set-Core '0.26.0' '0.26.0'
    $d = Deploy @()
    Ok ($d.Code -eq 1 -and $d.Out -match 'ModManager was made for Nucleus >=0.25.0, which this Nucleus 0\.26\.0 no longer supports') 'deploy: floor above the need -> refused' $d.Out
    Set-Core '0.25.0' $null 'other.nucleus'
    $d = Deploy @()
    Ok ($d.Code -eq 1 -and $d.Out -match "is not Nucleus's manifest") 'deploy: a manifest with another id -> refused' $d.Out
    Set-Core '0.25.0' $null 'nucleus'
    $d = Deploy @()
    Ok ($d.Code -eq 1 -and $d.Out -match "is not Nucleus's manifest") 'deploy: the old bare id nucleus -> refused (no legacy alias)' $d.Out
    Set-Core '0.25.0' $null 'nuclearnightmare-community.nucleus'
    [IO.File]::WriteAllText($modsTxt, "Nucleus : 0`r`n" + $stockTxt)
    $d = Deploy @()
    Ok ($d.Code -eq 1 -and $d.Out -match 'Nucleus is installed but disabled in mods\.txt') 'deploy: core disabled -> refused' $d.Out

    # Good core: installed below Nucleus, above Keybinds.
    Set-Core '0.25.0'
    [IO.File]::WriteAllText($modsTxt, "ModManager : 1`r`n" + $coreTxt)
    $d = Deploy @()
    Ok ($d.Code -eq 0) 'deploy: core 0.25.0 -> installed' $d.Out
    Eq (Txt) ("Nucleus : 1`r`nModManager : 1`r`n" + $stockTxt) 'deploy: ModManager below Nucleus, above Keybinds'
    $files = @(Get-ChildItem (Join-Path $mods 'ModManager') -Recurse -File | ForEach-Object { $_.FullName.Substring((Join-Path $mods 'ModManager').Length + 1) } | Sort-Object)
    Eq ($files -join ',') ((@('mod.json') + @($ModScripts | ForEach-Object { "Scripts\$_" }) | Sort-Object) -join ',') 'deploy: exactly the Mod Manager files'
    Ok (-not (Test-Path (Join-Path $mods 'ModManagerDriver')) -and -not (Test-Path (Join-Path $mods 'ModManagerFixture'))) 'deploy: no driver or fixture without -Test'
    Eq (Names $paks) 'NuclearNightmare-Windows.pak' 'deploy: no fixture pak without -Test'
    Ok (-not (Test-Path (Join-Path $mods 'ModManager\state.json'))) 'deploy: no state.json shipped'

    # -Test builds the fixture paks with build.ps1 -Fixtures, which needs the workspace's repak: CI (NN_CI=1) skips it.
    if ($env:NN_CI -eq '1') { Write-Host "SKIP (CI): deploy -Test needs the workspace's tools/repak (build.ps1 -Fixtures)" } else {
        # -Test: the driver, the fixtures, the paks, mods.txt.
        $d = Deploy @('-Test', '-Scenario', 'screen')
        Ok ($d.Code -eq 0) 'deploy -Test: installed' $d.Out
        Eq (Txt) ("Nucleus : 1`r`nModManagerDriver : 1`r`nModManager : 1`r`nModManagerBase : 1`r`nModManagerDep : 1`r`nModManagerFixture : 0`r`n" + $stockTxt) 'deploy -Test: Nucleus, the driver, ModManager, Base and Dep on, the fixture off'
        Ok ((Test-Path (Join-Path $mods 'ModManagerBase\mod.json')) -and (Test-Path (Join-Path $mods 'ModManagerDep\mod.json')) -and @(Get-ChildItem (Join-Path $mods 'ModManagerDep') -Recurse).Count -eq 1) 'deploy -Test: Base and Dep hold mod.json only'
        Eq ([IO.File]::ReadAllText((Join-Path $mods 'ModManagerDriver\Scripts\scenario.txt'))) 'screen' 'deploy -Test: scenario.txt'
        Ok ((Test-Path (Join-Path $mods 'ModManagerFixture\mod.json')) -and @(Get-ChildItem (Join-Path $mods 'ModManagerFixture') -Recurse).Count -eq 1) 'deploy -Test: ModManagerFixture holds mod.json only'
        Ok ((Test-Path (Join-Path $mods 'ModManagerBare\Scripts')) -and @(Get-ChildItem (Join-Path $mods 'ModManagerBare') -Recurse -File).Count -eq 0) 'deploy -Test: ModManagerBare has an empty Scripts/'
        Ok ((Get-Content (Join-Path $mods 'ModManagerLong\mod.json') -Raw) -match 'ModManagerLong W') 'deploy -Test: ModManagerLong'
        Eq (Names $paks) 'ModManagerPak_P.pak,ModManagerPakOff_P.pak.disabled,NuclearNightmare-Windows.pak' 'deploy -Test: the fixture paks in Content/Paks'
        Eq (Names (Join-Path $paks 'LogicMods')) '' 'deploy -Test: nothing in LogicMods'
        Ok (-not (Test-Path (Join-Path $mods 'ModManagerRestart'))) 'deploy -Test -Scenario screen: no ModManagerRestart (story 8: restart only)'
        # v2 story 4: -Scenario browse: the driver and the screen fixtures, its scenario.txt
        $d = Deploy @('-Test', '-Scenario', 'browse')
        Ok ($d.Code -eq 0) 'deploy -Test -Scenario browse: installed' $d.Out
        Eq ([IO.File]::ReadAllText((Join-Path $mods 'ModManagerDriver\Scripts\scenario.txt'))) 'browse' 'deploy -Test -Scenario browse: scenario.txt'
        Ok (-not (Test-Path (Join-Path $mods 'ModManagerRestart'))) 'deploy -Test -Scenario browse: no ModManagerRestart'
        # Story 8: -Scenario restart adds ModManagerRestart (mod.json and Scripts/main.lua), on; a leftover facts file goes.
        [IO.File]::WriteAllText((Join-Path $mods 'ModManagerDriver\Scripts\restart-facts.txt'), 'mode=direct')
        $d = Deploy @('-Test', '-Scenario', 'restart')
        Ok ($d.Code -eq 0) 'deploy -Test -Scenario restart: installed' $d.Out
        Eq (Txt) ("Nucleus : 1`r`nModManagerDriver : 1`r`nModManager : 1`r`nModManagerBase : 1`r`nModManagerDep : 1`r`nModManagerRestart : 1`r`nModManagerFixture : 0`r`n" + $stockTxt) 'deploy -Test -Scenario restart: ModManagerRestart on'
        Eq ((@(Get-ChildItem (Join-Path $mods 'ModManagerRestart') -Recurse -File | ForEach-Object Name) | Sort-Object) -join ',') 'main.lua,mod.json' 'deploy -Test -Scenario restart: ModManagerRestart holds mod.json and Scripts/main.lua'
        Ok (-not (Test-Path (Join-Path $mods 'ModManagerDriver\Scripts\restart-facts.txt'))) 'deploy -Test: no leftover restart-facts.txt'
        Eq ([IO.File]::ReadAllText((Join-Path $mods 'ModManagerDriver\Scripts\scenario.txt'))) 'restart' 'deploy -Test -Scenario restart: scenario.txt'
        # Mod Manager v2 story 3: -Scenario apply stages plan A with core's plan writer (from the instance's workspace,
        # here $tmp) and installs none of the apply fixtures itself.
        $staged = Join-Path $win64 'ue4ss\NucleusData\staged'
        $d = Deploy @('-Test', '-Scenario', 'apply')
        Ok ($d.Code -eq 1 -and $d.Out -match "the apply scenario needs core's plan writer" -and -not (Test-Path $staged)) 'deploy -Scenario apply: no plan writer -> refused, nothing staged' $d.Out
        if ($writerSrc) {
            $wdir = Join-Path $tmp 'mods\Nucleus\native\test'
            New-Item -ItemType Directory -Force $wdir | Out-Null
            Copy-Item $writerSrc $wdir
            [IO.File]::WriteAllText((Join-Path $mods 'ModManagerDriver\Scripts\apply-session.txt'), '3')
            $d = Deploy @('-Test', '-Scenario', 'apply')
            Ok ($d.Code -eq 0 -and $d.Out -match 'Staged plan A \(txn [0-9a-f]{32}\)') 'deploy -Test -Scenario apply: installed, plan A staged' $d.Out
            $planTxt = Join-Path $staged 'plan.txt'
            Ok ((Test-Path $planTxt) -and -not (Test-Path "$planTxt.tmp") -and (Test-ApplyPlanOurs -Plan $planTxt -Name 'ModManager')) 'deploy -Scenario apply: staged\plan.txt is the scenario''s own'
            $pl = @([IO.File]::ReadAllLines($planTxt))
            Ok ($pl[0] -ceq "nucleus-plan`t1" -and $pl[1] -cmatch "^txn`t[0-9a-f]{32}$" -and $pl.Count -eq 5 -and $pl[2] -cmatch "^put`tModManagerApplyA`t[0-9a-f]{64}`t\d+`tNuclearNightmare\\Binaries\\Win64\\ue4ss\\Mods\\ModManagerApplyA\\mod\.json$" -and
                $pl[3] -cmatch "^put`tModManagerApplyA`t[0-9a-f]{64}`t\d+`tNuclearNightmare\\Binaries\\Win64\\ue4ss\\Mods\\ModManagerApplyA\\Scripts\\main\.lua$" -and $pl[4] -ceq "modstxt`tModManagerApplyA`ton") 'deploy -Scenario apply: plan A puts mod.json and Scripts\main.lua, then turns A on' ($pl -join ' | ')
            $srcMain = Join-Path $repo 'test\ModManagerApplyA\Scripts\main.lua'
            $sha = (Get-FileHash $srcMain -Algorithm SHA256).Hash.ToLowerInvariant()
            Ok ((Test-Path (Join-Path $staged "files\$sha")) -and ($pl[3] -split "`t")[2] -eq $sha) 'deploy -Scenario apply: A''s main.lua staged under its SHA-256'
            Ok (-not (Test-Path (Join-Path $mods 'ModManagerApplyA')) -and -not (Test-Path (Join-Path $mods 'ModManagerApplyB')) -and -not (Test-Path (Join-Path $mods 'ModManagerApplyC')) -and (Txt) -notmatch 'ModManagerApply') 'deploy -Scenario apply: no apply fixture installed or in mods.txt (core''s helper installs them)'
            $exp = Join-Path $mods 'ModManagerDriver\Scripts\apply-expect\ModManagerApplyA'
            Ok ([IO.File]::ReadAllText((Join-Path $exp 'Scripts\main.lua')) -ceq [IO.File]::ReadAllText($srcMain) -and (Test-Path (Join-Path $exp 'mod.json'))) 'deploy -Scenario apply: the driver''s expected copy of A'
            Ok (-not (Test-Path (Join-Path $mods 'ModManagerDriver\Scripts\apply-session.txt'))) 'deploy -Test: no leftover apply-session.txt'
            Ok (-not (Test-Path (Join-Path $mods 'ModManagerRestart'))) 'deploy -Scenario apply: no ModManagerRestart'
            # A leftover A installed by the helper (and its mods.txt line) goes with the next deploy, like the other fixtures.
            New-Item -ItemType Directory -Force (Join-Path $mods 'ModManagerApplyA') | Out-Null
            [IO.File]::WriteAllText($modsTxt, ((Txt) -replace 'Keybinds : 1', "ModManagerApplyA : 1`r`nKeybinds : 1"))
            # A staged change that isn't the scenario's: refused, left alone.
            $foreign = "nucleus-plan`t1`ntxn`t$('a' * 32)`nmodstxt`tSomeoneElse`ton`n"
            [IO.File]::WriteAllText($planTxt, $foreign)
            $d = Deploy @('-Test', '-Scenario', 'apply')
            Ok ($d.Code -eq 1 -and $d.Out -match 'a change is already staged' -and [IO.File]::ReadAllText($planTxt) -ceq $foreign) 'deploy -Scenario apply: another staged change -> refused, left alone' $d.Out
            $d = Deploy @('-Test', '-Scenario', 'restart')
            Ok ($d.Code -eq 0 -and [IO.File]::ReadAllText($planTxt) -ceq $foreign) 'deploy: another staged change is never removed' $d.Out
            Ok (-not (Test-Path (Join-Path $mods 'ModManagerApplyA')) -and (Txt) -notmatch 'ModManagerApplyA') 'deploy: a helper-installed apply fixture and its mods.txt line removed'
            Remove-Item $staged -Recurse -Force
            $d = Deploy @('-Test', '-Scenario', 'apply')
            Ok ($d.Code -eq 0 -and (Test-Path $planTxt)) 'deploy -Scenario apply: staged again' $d.Out
            Remove-Item $wdir -Recurse -Force
        } else { Write-Host "NOTE Nucleus's native/test/New-StagedPlan.ps1 not found (Nucleus 0.24.0; NN_NUCLEUS or the main checkout's mods/Nucleus): the apply deploy cases are skipped" }
        # Redeploy without -Test: the driver and the fixtures go.
        $d = Deploy @()
        Ok ($d.Code -eq 0 -and -not (Test-Path (Join-Path $mods 'ModManagerDriver')) -and -not (Test-Path (Join-Path $mods 'ModManagerBare')) -and -not (Test-Path (Join-Path $mods 'ModManagerBase')) -and -not (Test-Path (Join-Path $mods 'ModManagerDep')) -and -not (Test-Path (Join-Path $mods 'ModManagerRestart'))) 'deploy without -Test removes the driver and fixtures' $d.Out
        if ($writerSrc) { Ok (-not (Test-Path (Join-Path $win64 'ue4ss\NucleusData\staged'))) 'deploy without -Test removes the apply scenario''s staged change' }
        Eq (Names $paks) 'NuclearNightmare-Windows.pak' 'deploy without -Test removes the fixture paks'
        Eq (Txt) ("Nucleus : 1`r`nModManager : 1`r`n" + $stockTxt) 'deploy without -Test: mods.txt back to one line'
    }

    # -Force without core.
    Remove-Item (Join-Path $mods 'Nucleus') -Recurse -Force
    [IO.File]::WriteAllText($modsTxt, $stockTxt)
    if ($env:NN_CI -eq '1') { Write-Host "SKIP (CI): deploy -Force -Test needs the workspace's tools/repak (build.ps1 -Fixtures)" } else {
        $d = Deploy @('-Force', '-Test', '-Scenario', 'no-core')
        Ok ($d.Code -eq 0 -and $d.Out -match 'forced: Nucleus is not installed') 'deploy -Force: warns and installs' $d.Out
    }

    # -Remove: back to exactly the stock files.
    $d = Deploy @('-Remove')
    Ok ($d.Code -eq 0 -and -not (Test-Path (Join-Path $mods 'ModManager'))) 'deploy -Remove: no Mod Manager files' $d.Out
    Eq (Txt) $stockTxt 'deploy -Remove: mods.txt byte-identical to stock'
    Ok ((Get-ChildItem $mods -Directory | ForEach-Object Name | Sort-Object) -join ',' -eq 'Keybinds') 'deploy -Remove: Mods/ holds only what was there'
    Eq (Names $paks) 'NuclearNightmare-Windows.pak' 'deploy -Remove: the fixture paks gone'
    $before = Txt
    Deploy @('-Remove') | Out-Null
    Eq (Txt) $before 'deploy -Remove twice: nothing changes'

    # ------------------------------------------------------------ run.ps1's FILES check (Get-FileState, Get-FilesLine)
    $s0 = Get-FileState $inst
    Eq (Get-FilesLine $s0 (Get-FileState $inst)) '[run.ps1] FILES unchanged' 'files: nothing changed -> unchanged'
    Ok ($s0.Paks -eq 'NuclearNightmare-Windows.pak' -and $s0.LogicMods -eq '' -and $s0.ModsTxt -match '^[0-9A-F]{64}$') 'files: the state (sha256, Paks, LogicMods)' "$($s0.ModsTxt) $($s0.Paks) $($s0.LogicMods)"
    [IO.File]::WriteAllText($modsTxt, (Txt) + ' ')
    Ok ((Get-FilesLine $s0 (Get-FileState $inst)) -match '^\[run\.ps1\] FILES changed: mods\.txt sha256 [0-9A-F]{64} -> [0-9A-F]{64}$') 'files: a mods.txt byte -> changed: mods.txt'
    [IO.File]::WriteAllText($modsTxt, $before)
    Set-Content (Join-Path $paks 'New_P.pak') 'x'
    Eq (Get-FilesLine $s0 (Get-FileState $inst)) '[run.ps1] FILES changed: Paks added New_P.pak' 'files: a pak added in Paks -> changed'
    Move-Item (Join-Path $paks 'New_P.pak') (Join-Path $paks 'LogicMods\New.pak')
    Eq (Get-FilesLine $s0 (Get-FileState $inst)) '[run.ps1] FILES changed: LogicMods added New.pak' 'files: a pak added in LogicMods -> changed'
    $s1 = Get-FileState $inst
    Remove-Item (Join-Path $paks 'LogicMods\New.pak')
    Eq (Get-FilesLine $s1 (Get-FileState $inst)) '[run.ps1] FILES changed: LogicMods removed New.pak' 'files: a pak removed in LogicMods -> changed'
    Rename-Item (Join-Path $paks 'NuclearNightmare-Windows.pak') 'NuclearNightmare-Windows.pak.disabled'
    Eq (Get-FilesLine $s0 (Get-FileState $inst)) '[run.ps1] FILES changed: Paks removed NuclearNightmare-Windows.pak added NuclearNightmare-Windows.pak.disabled' 'files: a rename in Paks -> changed'
    Eq (Get-FilesLine $null $s0) '[run.ps1] FILES not recorded' 'files: no state before -> not recorded'
    Eq (Get-FilesLine $s0 $null) '[run.ps1] FILES not recorded' 'files: no state after -> not recorded'
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("deploy_test: {0} passed, {1} failed" -f $script:passed, $script:failed)
exit $(if ($script:failed) { 1 } else { 0 })
