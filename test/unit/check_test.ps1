<#
.SYNOPSIS
  Unit tests for check.ps1: synthetic UE4SS.log files, in the format the pinned UE4SS writes, for every scenario, each
  passing as written and failing after one targeted change. Proves the patterns, not the game.
.EXAMPLE
  pwsh -NoProfile -File test/unit/check_test.ps1
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
$check = Join-Path $repo 'check.ps1'
$script:passed = 0; $script:failed = 0
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mod-manager-check-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp | Out-Null
$coreManifest = Join-Path $tmp 'nucleus-mod.json'
Set-Content $coreManifest '{ "id": "nuclearnightmare-community.nucleus", "name": "Nucleus", "version": "0.8.0", "game": { "version": "V8.2.3", "build": "26601774" }, "dependsOn": [] }'

$script:t = 0
function L([string] $tag, [string] $msg) { $script:t++; "[2026-11-14 01:00:{0:D2}.{1:D7}] [Lua] [$tag] $msg" -f [int]($script:t / 1000 % 60), $script:t }
function U([string] $msg) { $script:t++; "[2026-11-14 01:00:00.{0:D7}] $msg" -f $script:t }

function Run([string[]] $log, [string] $scenario, [string] $target = 'host') {
    $p = Join-Path $tmp "$scenario-$([guid]::NewGuid().ToString('N').Substring(0, 6)).log"
    Set-Content $p $log
    $out = & pwsh -NoProfile -NonInteractive -File $check -Log $p -Scenario $scenario -Target $target -CoreManifest $coreManifest 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $out }
}
function Expect([string[]] $log, [string] $scenario, [int] $code, [string] $name, [string] $mustSay, [string] $target = 'host') {
    $r = Run $log $scenario $target
    $ok = $r.Code -eq $code -and (-not $mustSay -or $r.Out -match $mustSay)
    if ($ok) { $script:passed++ } else { $script:failed++; Write-Host "FAIL $name (exit $($r.Code), want $code)"; Write-Host ($r.Out -split "`n" | Where-Object { $_ -match 'FAIL|warn' } | Out-String) }
}

$D = 'ModManagerDriver'; $M = 'ModManager'
$LONG = 'ModManagerLong ' + ('W' * 49)
function Start-Log { @(
    (U "Starting Lua mod 'Nucleus'"), (L 'Nucleus' 'READY version=0.8.0 native=0.8.0 ue4ss=v3.0.1-1181-g83330635 boot=1'),
    (U "Starting Lua mod '$D'"), (U "Starting Lua mod '$M'")) }
$rowLines = @(
    "ROW Nucleus | 0.8.0 | toggle=lock | gear=dim | status=0 | need=- | build=V8.2.3 26601774"
    "ROW Mod Manager | 0.1.0 | toggle=lock | gear=dim | status=0 | need=>=0.12.0 | build=V8.2.3 26601774"
    "ROW ModManagerBare | - | toggle=off | gear=dim | status=0 | need=- | build=-"
    "ROW ModManagerDriver | - | toggle=on | gear=dim | status=0 | need=- | build=-"
    "ROW ModManagerFixture | 9.9.9 | toggle=off | gear=lit | status=0 | need=>=0.1.0 | build=V0.0.0 1"
    "ROW $LONG | 1.0.0 | toggle=off | gear=dim | status=0 | need=>=0.2.0 | build=V8.2.3 26601774"
    "ROW ModManagerPak | UNMANAGED | toggle=on | gear=dim | status=0 | need=- | build=-"
    "ROW ModManagerPakOff | UNMANAGED | toggle=off | gear=dim | status=0 | need=- | build=-"
)
function Screen-Log([string[]] $rows = $rowLines, [string] $measure = 'MEASURE name width=680.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=405.0 rowLeft=405.0', [string[]] $inert = @(), [string] $files = '[run.ps1] FILES unchanged') {
    $l = (Start-Log) + @(
        (L $D 'SCENARIO screen'), (L $D 'LOADED 7 steps'),
        (L $M 'CONNECT ok Nucleus 0.8.0 (pong 0.8.0 boot=1)'), (L $M 'READY entry=manage need=>=0.12.0'),
        (L $D 'ENTRY menu1 text=MANAGE MODS above=OPTIONS below=QUIT'),
        (L $D 'OK ENTRYPOS menu1 between OPTIONS (UI_Button_Master_2) and QUIT (UI_Button_Master_3)'), (L $D 'OK ENTRYLOOK menu1 style x / x font y / y (the options style)'),
        (L $M 'MOD 1 Nucleus | Nucleus | 0.8.0 | locked | settings=no | need=- | build=V8.2.3 26601774'),
        (L $M 'OPEN rows=8 total=8 lang=en us=4000'),
        (L $D 'OK OPEN first the MOD MANAGER window opened from the entry'), (L $D 'OK TITLE first the window''s title reads MOD MANAGER (MOD MANAGER)'),
        (L $M 'CONFIGURE 1 Nucleus'))
    foreach ($r in $rows) { $l += L $D $r }
    $l += L $D $measure
    $l += L $D 'OK MEASURECUT the long name''s desired width 820.5 is over its column''s 680.0'
    $l += L $D 'OK MEASUREEDGE x'
    $l += L $D 'OK MEASUREALIGN x'
    $l += L $D 'INERT begin'
    foreach ($i in $inert) { $l += $i }
    $l += L $D 'INERT end'
    foreach ($ok in 'INERT the toggle boxes changed nothing on screen (rows the same: true, no Configure, main window on top)', 'CFGTOP x', 'CFGFIXTURE x', 'CFGCLOSE x', 'CFGDIM x', 'CFGDIMOPEN x',
            'BLOCKEDGEAR x', 'BLOCKED x', 'CFGCLOSE2 x', 'CLOSEMAIN x', 'MENUBACK x', 'ENTRYUP2 x', 'ENTRYPOS menu2 x', 'ENTRYLOOK menu2 x', 'OPEN after the match x', 'SAME x', 'CLOSEEND x') {
        $l += L $D "OK $ok"
    }
    $l += L $M 'OPEN rows=8 total=8 lang=en us=3000'
    $l += L $D 'END result=PASS checks=60 failures=0'
    if ($files) { $l += $files }
    return $l
}

# ---------------------------------------------------------------- screen
$good = Screen-Log
Expect $good 'screen' 0 'screen: passes' 'All checks passed'
Expect $good 'screen' 0 'vm screen: passes' 'All checks passed' 'vm'
# Other installed mods may sit between the expected rows.
Expect (Screen-Log -rows (@($rowLines[0], $rowLines[1], 'ROW Clock | 0.1.0 | toggle=on | gear=lit | status=0 | need=>=0.2.0 | build=V8.2.3 26601774') + $rowLines[2..7])) 'screen' 0 'screen: another mod between them is fine' 'All checks passed'
Expect (Screen-Log -rows $rowLines[0..6]) 'screen' 1 'screen: a missing row (PakOff) fails' 'ModManagerPakOff .*found 0'
Expect (Screen-Log -rows ($rowLines + $rowLines[4])) 'screen' 1 'screen: a row twice fails' 'found 2'
Expect (Screen-Log -rows (@($rowLines[1], $rowLines[0]) + $rowLines[2..7])) 'screen' 1 'screen: Nucleus after Mod Manager fails' 'out of order'
Expect (Screen-Log -rows (@($rowLines[0..3]) + ($rowLines[4] -replace 'toggle=off', 'toggle=on') + $rowLines[5..7])) 'screen' 1 'screen: the fixture on fails' 'got 9.9.9 \| toggle=on'
Expect (Screen-Log -rows (@($rowLines[0..3]) + ($rowLines[4] -replace 'gear=lit', 'gear=dim') + $rowLines[5..7])) 'screen' 1 'screen: the fixture gear dimmed fails'
Expect (Screen-Log -rows (@($rowLines[0..4]) + ($rowLines[5] -replace 'need=>=0\.2\.0', 'need=-') + $rowLines[6..7])) 'screen' 1 'screen: the Long need missing fails'
Expect (Screen-Log -rows (@($rowLines[0..5]) + ($rowLines[6] -replace 'status=0', 'status=1') + $rowLines[7])) 'screen' 1 'screen: a status icon fails' 'status slot'
Expect (Screen-Log -rows ($rowLines + 'ROW Keybinds | - | toggle=on | gear=dim | status=0 | need=- | build=-')) 'screen' 1 'screen: a built-in row fails' 'must be absent: Keybinds'
Expect (Screen-Log -rows ($rowLines + 'ROW NuclearNightmare-Windows | UNMANAGED | toggle=on | gear=dim | status=0 | need=- | build=-')) 'screen' 1 'screen: the base pak row fails' 'must be absent'
Expect (Screen-Log -rows (@($rowLines[0]) + ($rowLines[1] -replace '0\.1\.0', '0.2.0') + $rowLines[2..7])) 'screen' 1 "screen: Mod Manager's version from its mod.json"
Expect (Screen-Log -measure 'MEASURE name width=900.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=405.0 rowLeft=405.0') 'screen' 1 'screen: a long name not cut fails' 'is cut'
Expect (Screen-Log -measure 'MEASURE name width=680.0 desired=820.5 right=1240.0 verLeft=1233.0 headerLeft=405.0 rowLeft=405.0') 'screen' 1 'screen: an overlap fails' 'right edge'
Expect (Screen-Log -measure 'MEASURE name width=680.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=407.5 rowLeft=405.0') 'screen' 1 'screen: a misaligned header fails' 'within 1 unit'
Expect (Screen-Log -measure 'MEASURE name width=680.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=405.8 rowLeft=405.0') 'screen' 0 'screen: within 1 unit passes'
Expect (Screen-Log -inert @((L $M 'CONFIGURE 3 ModManagerFixture'))) 'screen' 1 'screen: a [ModManager] line during the toggle clicks fails' 'INERT the toggle-box clicks logged'
Expect (Screen-Log -inert @((L $M 'WARN hud slow tick 1.4 ms (steady state)'))) 'screen' 0 'vm screen: a slow tick during the toggle clicks is soft' 'soft check' 'vm'
Expect (Screen-Log -files '[run.ps1] FILES changed: mods.txt sha256 A -> B') 'screen' 1 'screen: a changed file fails' 'FILES unchanged'
Expect (Screen-Log -files '') 'screen' 1 'screen: no FILES line fails' 'FILES unchanged'
Expect ($good + (L $M 'WARN ModManagerX/mod.json is not valid JSON')) 'screen' 1 'screen: a Mod Manager WARN fails'
Expect ($good + (L $M 'WARN hud slow tick 1.4 ms (steady state)')) 'screen' 0 'vm screen: a slow tick is soft' 'warn: ' 'vm'
Expect ($good + (L $M 'ERROR boom')) 'screen' 1 'screen: an ERROR fails'
Expect ($good + (U 'stack traceback:')) 'screen' 1 'screen: a traceback fails'
Expect ($good + (L $D "FAIL SAME x")) 'screen' 1 'screen: a driver FAIL fails'
Expect ($good | Where-Object { $_ -notmatch 'OK BLOCKED ' }) 'screen' 1 'screen: no BLOCKED fails'
Expect ($good | Where-Object { $_ -notmatch 'OK BLOCKEDGEAR' }) 'screen' 1 'screen: no BLOCKEDGEAR fails'
Expect ($good | Where-Object { $_ -notmatch 'OK CFGDIMOPEN' }) 'screen' 1 'screen: no dimmed-gear Configure fails'
Expect ($good | Where-Object { $_ -notmatch 'OK SAME' }) 'screen' 1 'screen: no SAME (DW-59) fails'
Expect ($good | Where-Object { $_ -notmatch 'ENTRY menu1 text=' }) 'screen' 1 'screen: no entry text fails'
Expect ($good + (L $M 'READY entry=manage need=>=0.12.0')) 'screen' 1 'screen: two READY lines fail'
Expect (($good | Where-Object { $_ -notmatch "\[$M\] OPEN rows" }) + (L $M 'OPEN rows=8 total=8 lang=en')) 'screen' 1 'screen: one OPEN fails' 'opened twice'
$swapped = [Collections.Generic.List[string]]::new([string[]]$good)
$ic = $swapped.FindIndex({ param($l) $l -match '\[ModManager\] CONNECT ok' }); $ir = $swapped.FindIndex({ param($l) $l -match '\[ModManager\] READY ' })
$tmpL = $swapped[$ic]; $swapped[$ic] = $swapped[$ir]; $swapped[$ir] = $tmpL
Expect $swapped.ToArray() 'screen' 1 'screen: READY before CONNECT ok fails' 'READY comes after CONNECT ok'

# ---------------------------------------------------------------- no-core and old-core
$noCore = @((U "Starting Lua mod '$D'"), (L $D 'SCENARIO no-core'), (U "Starting Lua mod '$M'"),
    (L $M 'Nucleus is not installed. ModManager will not run.'), (L $D 'OK NOENTRY no MANAGE MODS entry in the menu for 15 s'),
    (L $D 'END result=PASS checks=2 failures=0'), '[run.ps1] FILES unchanged')
Expect $noCore 'no-core' 0 'no-core: passes' 'All checks passed'
Expect ($noCore + (L $M 'READY entry=manage need=>=0.12.0')) 'no-core' 1 'no-core: a second [ModManager] line fails'
Expect ($noCore | Where-Object { $_ -notmatch 'NOENTRY' }) 'no-core' 1 'no-core: no NOENTRY fails'
$oldCore = (Start-Log) + @((L $D "OLDCORE published nucleus.version=0.1.0 (from Nucleus's installed mod.json)"),
    (L $M 'ERROR Nucleus 0.1.0 is older than ModManager needs (>=0.12.0). Update Nucleus. ModManager will not run.'),
    (L $D 'OK NOENTRY no MANAGE MODS entry in the menu for 15 s'), (L $D 'END result=PASS checks=2 failures=0'), '[run.ps1] FILES unchanged')
Expect $oldCore 'old-core' 0 'old-core: passes' 'All checks passed'
Expect ($oldCore + (L $M 'ERROR start failed: x')) 'old-core' 1 'old-core: a second [ModManager] line fails'
Expect ($oldCore -replace 'needs \(>=0\.12\.0\)', 'needs (>=0.7.0)') 'old-core' 1 'old-core: the wrong need fails'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("check_test: {0} passed, {1} failed" -f $script:passed, $script:failed)
exit $(if ($script:failed) { 1 } else { 0 })
