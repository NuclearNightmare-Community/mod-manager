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
Set-Content $coreManifest '{ "id": "nuclearnightmare-community.nucleus", "name": "Nucleus", "version": "0.8.0", "scope": "client", "game": { "version": "V8.2.3", "build": "26601774" }, "dependsOn": [] }'

# v2 story 4: a made-up catalog index naming the browse scenario's packages (check.ps1 -CatalogIndex)
$catalogIndex = Join-Path $tmp 'index.json'
Set-Content $catalogIndex ('{ "packages": [ ' + ((@('nucleus|Nucleus (Mod Core)|Nucleus', 'mod-manager|Mod Manager|ModManager', 'hud-clock|HUD Clock|HudClock', 'waypoints|Map Waypoints+|Waypoints', 'whistle-mute|Whistle Emote Mute|WhistleMute') |
    ForEach-Object { $i, $n, $f = $_ -split '\|'; '{ "id": "nuclearnightmare-community.' + $i + '", "name": "' + $f + '", "displayName": "' + $n + '" }' }) -join ', ') + ' ] }')

$script:t = 0
function L([string] $tag, [string] $msg) { $script:t++; "[2026-11-14 01:00:{0:D2}.{1:D7}] [Lua] [$tag] $msg" -f [int]($script:t / 1000 % 60), $script:t }
function U([string] $msg) { $script:t++; "[2026-11-14 01:00:00.{0:D7}] $msg" -f $script:t }

function Run([string[]] $log, [string] $scenario, [string] $target = 'host') {
    $p = Join-Path $tmp "$scenario-$([guid]::NewGuid().ToString('N').Substring(0, 6)).log"
    Set-Content $p $log
    $out = & pwsh -NoProfile -NonInteractive -File $check -Log $p -Scenario $scenario -Target $target -CoreManifest $coreManifest -CatalogIndex $catalogIndex 2>&1 | Out-String
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
$MV = (Get-Content (Join-Path $repo 'mod.json') -Raw | ConvertFrom-Json).version # check.ps1 expects the Mod Manager's own version
# Story 12: each ROW ends with the scope (from the icon's texture), its tooltip and Configure's RUNS ON line.
$SW = @{
    'host'      = "HOST ONLY - ONLY THE HOST NEEDS IT; PLAYERS WHO JOIN DON'T"
    'client'    = 'JUST YOU - WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN'
    'host-plus' = 'HOST, PLAYERS OPTIONAL - THE HOST NEEDS IT; PLAYERS WHO HAVE IT GET MORE'
    'both'      = 'HOST AND PLAYERS - THE HOST AND EVERY PLAYER NEED IT'
    'unknown'   = "UNKNOWN - THIS MOD DOESN'T SAY WHERE IT RUNS"
}
function Sc([string] $s) { " | scope=$s | stip=$($SW[$s]) | runs=RUNS ON: $($SW[$s])" }
$rowLines = @(
    ("ROW Nucleus | 0.8.0 | toggle=lock | box=none | gear=dim | status=0 | icons=- | need=- | build=V8.2.3 26601774" + (Sc 'client'))
    ("ROW Mod Manager | $MV | toggle=lock | box=none | gear=dim | status=0 | icons=- | need=>=0.25.0 | build=V8.2.3 26601774" + (Sc 'client'))
    ("ROW Mod Manager Base | 1.0.0 | toggle=on | box=live | gear=dim | status=0 | icons=- | need=>=0.12.0 | build=V8.2.3 26601774" + (Sc 'host'))
    ("ROW Mod Manager Dep | 1.0.0 | toggle=on | box=live | gear=dim | status=0 | icons=- | need=- | build=V8.2.3 26601774" + (Sc 'both'))
    ("ROW ModManagerBare | - | toggle=off | box=live | gear=dim | status=0 | icons=- | need=- | build=-" + (Sc 'unknown'))
    ("ROW ModManagerDriver | - | toggle=on | box=live | gear=dim | status=0 | icons=- | need=- | build=-" + (Sc 'unknown'))
    ("ROW ModManagerFixture | 9.9.9 | toggle=off | box=live | gear=lit | status=2 | icons=warning,warning | need=>=0.1.0 | build=V0.0.0 1" + (Sc 'unknown'))
    ("ROW $LONG | 1.0.0 | toggle=off | box=live | gear=dim | status=0 | icons=- | need=>=0.2.0 | build=V8.2.3 26601774" + (Sc 'host-plus'))
    ("ROW ModManagerPak | UNMANAGED | toggle=on | box=fixed | gear=dim | status=0 | icons=- | need=- | build=-" + (Sc 'unknown'))
    ("ROW ModManagerPakOff | UNMANAGED | toggle=off | box=fixed | gear=dim | status=0 | icons=- | need=- | build=-" + (Sc 'unknown'))
)
$statusLines = @(
    'STATUS Nucleus none | ', 'STATUS ModManager none | ', 'STATUS ModManagerBase none | ', 'STATUS ModManagerDep none | ', 'STATUS ModManagerBare none | ',
    'STATUS ModManagerFixture build,dep | MADE FOR GAME V0.0.0 (BUILD 1). THIS GAME: V8.2.3 (BUILD -). / NEEDS nuclearnightmare-community.mod-manager-missing (NOT INSTALLED) / NEEDS Mod Manager Base >=2.0.0 (INSTALLED: 1.0.0)'
)
$toggleOks = @('TGROWS x', 'TXT0 x', 'TGLIVE x', 'TGSTART x', 'TGDEPOFF x', 'TGNOCONFIRM x', 'TGDEPICON x', 'PENDINGUI x', 'STATEOFF x', 'CARDFIT2 x', 'TGDEPON x',
    'TGDEPON2 x', 'PENDINGOFF x', 'STATEON x', 'CONFIRMTEXT x', 'CONFIRMWAIT x', 'CONFIRMBACK x', 'CONFIRMCLOSED x', 'CONFIRMOFF x', 'TGBASEICON x', 'DEPICON x',
    'PENDINGUI2 x', 'STATEBASE x', 'PAKFIXED x')
$settingOks = @('CFGPROBLEMS x', 'SETKINDS x', 'SETBY x', 'SETRO x', 'SETMARK x', 'SETFILE x', 'RESTARTICON x', 'CFGRESTART x', 'SETNOMSG x')
function Screen-Log([string[]] $rows = $rowLines, [string] $measure = 'MEASURE name width=680.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=405.0 rowLeft=405.0',
    [string[]] $fixed = @(), [string] $files = '[run.ps1] FILES changed: mods.txt sha256 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA -> BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', [string] $cardfit = 'OK CARDFIT the title, header and list are inside the card (true) and the list ends 72.0 units above BACK''s top',
    [string] $run = '[run.ps1] RUN game exited (crash?)', [switch] $quitBeforeEnd,
    [string] $gearlook = 'OK GEARLOOK 1 Nucleus looks dim (offers dim)', [int[]] $popin = @(1, 2, 3, 4), [int[]] $hiddenFirst = @(2, 3, 4)) {
    $l = (Start-Log) + @(
        (L $D 'SCENARIO screen'), (L $D 'LOADED 7 steps'),
        (L $M 'CONNECT ok Nucleus 0.8.0 (pong 0.8.0 boot=1)'), (L $M 'READY entry=manage need=>=0.25.0'),
        (L $D 'ENTRY menu1 text=MANAGE MODS above=OPTIONS below=QUIT'),
        (L $D 'OK ENTRYPOS menu1 between OPTIONS (UI_Button_Master_2) and QUIT (UI_Button_Master_3)'), (L $D 'OK ENTRYLOOK menu1 style x / x font y / y (the options style)'),
        (L $M 'MOD 1 Nucleus | Nucleus | 0.8.0 | locked | settings=no | need=- | build=V8.2.3 26601774'))
    foreach ($s in $statusLines) { $l += L $M $s }
    $l += @((L $M 'OPEN rows=10 total=10 lang=en game=V8.2.3 build=- us=4000'),
        (L $D 'OK OPEN first the MOD MANAGER window opened from the entry'), (L $D 'OK TITLE first the window''s title reads MOD MANAGER (MOD MANAGER)'))
    # core story 39: no focus chip after the mouse open, then the chip on Base's checkbox, then its gear
    $l += L $D 'OK CHIP open after a mouse click on the entry: focus on r1.cfg, no focus chip (nil)'
    $l += L $D 'OK CHIP tg Base''s row 3: the focused tg shows the focus chip (MaterialInstanceDynamic parent M_NN_CinematicSelection base 0.1529,0.6654,0.8469 scale 1.29 content 0.78), the cfg doesn''t (? parent ? base nil,nil,nil scale 1.0 content 1.0)'
    $l += L $D 'OK CHIP cfg Base''s row 3: the focused cfg shows the focus chip (MaterialInstanceDynamic parent M_NN_CinematicSelection base 0.1529,0.6654,0.8469 scale 1.29 content 0.78), the tg doesn''t (? parent ? base nil,nil,nil scale 1.0 content 1.0)'
    # story 11: the first toggle, before any Configure
    $l += L $D 'OK TGFIRSTCOLD x'
    $l += L $D 'OK TGFIRSTFOCUS Dep''s checkbox (row 4) holds the keyboard focus (focus on row 4)'
    $l += L $M 'TOGGLE ModManagerDep off'
    $l += L $M 'STATUS ModManagerDep restart | TURNS OFF AFTER A RESTART'
    $l += L $D 'OK TGFIRST ENTER on Dep''s checkbox: '': 0'', box off, icons restart, banner and QUIT GAME true, 1.2 s after the key (at most 10)'
    # core story 42: the chip stays on Dep's checkbox after ENTER (box off), a second ENTER (box on), a third (off again)
    $l += L $D 'OK CIPROBE class true subsystem true type 0 (number) simulated false'
    $l += L $D 'OK CHIP enter1 Dep''s checkbox (row 4): focus true, the focus chip (MaterialInstanceDynamic parent M_NN_CinematicSelection base 0.1529,0.6654,0.8469 scale 1.29 content 0.78), dark inside (IconBack true visibility 3 colour 0.0052,0.007,0.0091,1.0; icon 0.96,0.97,0.94,1.0), box off (want off)'
    $l += L $M 'TOGGLE ModManagerDep on'
    $l += L $M 'STATUS ModManagerDep none | '
    $l += L $D 'OK CHIP enter2 Dep''s checkbox (row 4): focus true, the focus chip (MaterialInstanceDynamic parent M_NN_CinematicSelection base 0.1529,0.6654,0.8469 scale 1.29 content 0.78), dark inside (IconBack true visibility 3 colour 0.0052,0.007,0.0091,1.0; icon 0.96,0.97,0.94,1.0), box on (want on)'
    $l += L $M 'TOGGLE ModManagerDep off'
    $l += L $M 'STATUS ModManagerDep restart | TURNS OFF AFTER A RESTART'
    $l += L $M 'TOGGLE ModManagerDep on'
    $l += L $M 'STATUS ModManagerDep none | '
    $l += L $D 'OK TGFIRSTCLICK a mouse click turns Dep back on: mods.txt as at the start, box on, icons -, banner hidden true, 2.0 s after the click (at most 10)'
    $l += L $D 'OK CHIP backoff Dep''s checkbox after the mouse click: IconBack true visibility 1 (want 1, Collapsed)'
    $l += L $M 'CONFIGURE 1 Nucleus'
    foreach ($r in $rows) { $l += L $D $r }
    $l += L $D 'GEARLOOK 2 skipped (focused)'
    $l += L $D 'OK GEARLOOK 7 ModManagerFixture looks lit (offers lit)'
    if ($gearlook) { $l += L $D $gearlook }
    $l += L $D $measure
    $l += L $D 'OK MEASURECUT the long name''s desired width 820.5 is over its column''s 680.0'
    $l += L $D 'OK MEASUREEDGE x'
    $l += L $D 'OK MEASUREALIGN x'
    if ($cardfit) { $l += L $D $cardfit }
    $l += L $D 'TOGGLE begin'
    $l += L $M 'TOGGLE ModManagerDep off'
    $l += L $M 'STATUS ModManagerDep restart | TURNS OFF AFTER A RESTART'
    $l += L $M 'TOGGLE ModManagerDep on'
    $l += L $M 'STATUS ModManagerDep none | '
    $l += L $M 'CONFIRM ModManagerBase needed by 1'
    $l += L $M 'CONFIRM ModManagerBase cancelled (close)'
    $l += L $M 'CONFIRM ModManagerBase needed by 1'
    $l += L $M 'TOGGLE ModManagerBase off'
    $l += L $M 'STATUS ModManagerBase restart | TURNS OFF AFTER A RESTART'
    $l += L $M 'STATUS ModManagerDep dep | NEEDS Mod Manager Base (TURNED OFF)'
    foreach ($ok in $toggleOks) { $l += L $D "OK $ok" }
    $l += L $D 'FIXED begin'
    foreach ($i in $fixed) { $l += $i }
    $l += L $D 'FIXED end'
    $l += L $D 'OK FIXEDINERT the lock and the pak''s box changed nothing (rows the same: true, mods.txt the same, main window on top)'
    $l += L $M 'CONFIGURE 7 ModManagerFixture'
    foreach ($ok in 'CFGTOP x', 'CFGFIXTURE x') { $l += L $D "OK $ok" }
    foreach ($s in 'flag=true', 'mode=two', 'example=7', 'later=true') { $l += L $M "SET ModManagerFixture $s" }
    foreach ($ok in $settingOks) { $l += L $D "OK $ok" }
    # core story 35: the pop-in sampler's checks and the two extra round trips
    foreach ($k in $popin) { $l += L $D "OK NOPOPIN menu$k no frame drew the column without the MANAGE MODS entry (0 of 40 visible frames did, 0 unreadable; entry in a drawn column: true)" }
    foreach ($k in $hiddenFirst) { $l += L $D "OK HIDDENFIRST menu$k the column was hidden (frame 2) on or before Overlay_0 was first drawn (frame 15)" }
    foreach ($ok in 'ENTRYUP3 x', 'ENTRYPOS menu3 x', 'ENTRYLOOK menu3 x', 'ENTRYUP4 x', 'ENTRYPOS menu4 x', 'ENTRYLOOK menu4 x') { $l += L $D "OK $ok" }
    foreach ($ok in 'CFGCLOSE x', 'CFGDIM x', 'CFGDIMOPEN x', 'BLOCKEDGEAR x', 'BLOCKED x', 'CFGCLOSE2 x', 'CLOSEMAIN x', 'MENUBACK x', 'ENTRYUP2 x', 'ENTRYPOS menu2 x',
            'ENTRYLOOK menu2 x', 'OPEN after the match x', 'SAME x', 'QUITUI x', 'BANNER x', 'QUITPOINT x') {
        $l += L $D "OK $ok"
    }
    $l += L $M 'OPEN rows=10 total=10 lang=en game=V8.2.3 build=- us=3000'
    if ($quitBeforeEnd) { $l += L $M 'QUIT pending=2' }
    $l += L $D 'END result=PASS checks=120 failures=0'
    $l += L $D 'CLICK QUIT GAME at (1000,600)'
    if (-not $quitBeforeEnd) { $l += L $M 'QUIT pending=2' }
    if ($run) { $l += $run }
    if ($files) { $l += $files }
    return $l
}

# ---------------------------------------------------------------- screen
$good = Screen-Log
Expect $good 'screen' 0 'screen: passes' 'All checks passed'
Expect $good 'screen' 0 'vm screen: passes' 'All checks passed' 'vm'
Expect (Screen-Log -files '[run.ps1] FILES unchanged') 'screen' 0 'screen: mods.txt unchanged passes too'
# 0.1.1: core's card WARN fails by name; CARDFIT is required.
$cardWarn = L $M "WARN window 'main': its content (2219 x 1031) is larger than the viewport allows; the card is clamped to 2267 x 1016"
Expect ($good + $cardWarn) 'screen' 1 'screen: the card clamp WARN fails' 'FAIL: .*the card is clamped'
Expect ($good + $cardWarn) 'screen' 1 'vm screen: the card clamp WARN fails' 'FAIL: .*the card is clamped' 'vm'
Expect ($good + (L $M "WARN window 'configure': its content (900 x 1100) is larger than the viewport allows; the card is clamped to 948 x 1016")) 'screen' 1 'screen: the Configure card WARN fails' 'FAIL: .*the card is clamped'
Expect (Screen-Log -cardfit '') 'screen' 1 'screen: no CARDFIT fails' 'FAIL: .*OK CARDFIT'
# core story 35: every menu judged for pop-in; a pop-in or core's column cap WARN fails.
Expect (Screen-Log -popin 1, 2, 4) 'screen' 1 'screen: no NOPOPIN menu3 fails' 'FAIL: .*OK NOPOPIN menu3'
Expect (Screen-Log -hiddenFirst 2, 4) 'screen' 1 'screen: no HIDDENFIRST menu3 fails' 'FAIL: .*OK HIDDENFIRST menu3'
Expect ($good + (L $D 'FAIL NOPOPIN menu2 no frame drew the column without the MANAGE MODS entry (12 of 40 visible frames did)')) 'screen' 1 'screen: a pop-in fails' 'FAIL: !.*FAIL '
$capWarn = L $M 'WARN ui menu entry: the menu column of MainMenu_C_2147466039 was still hidden 2.0 s after the menu appeared, waiting for Other; shown anyway'
Expect ($good + $capWarn) 'screen' 1 'screen: the column cap WARN fails by name' 'FAIL: .*column.*still hidden'
Expect ($good + $capWarn) 'screen' 1 'vm screen: the column cap WARN fails by name' 'FAIL: .*column.*still hidden' 'vm'
# story 10: at least one gear's look judged; a failed look fails.
Expect (Screen-Log -gearlook '') 'screen' 1 'screen: no OK GEARLOOK fails' 'FAIL: .*OK GEARLOOK'
Expect (Screen-Log -gearlook 'OK GEARLOOK 7 ModManagerFixture looks lit (offers lit)') 'screen' 1 'screen: only lit OK GEARLOOKs fail' 'FAIL: .*OK GEARLOOK'
Expect ($good + (L $D 'FAIL GEARLOOK 1 Nucleus looks lit (offers dim)')) 'screen' 1 'screen: a failed GEARLOOK fails' 'FAIL: !.*FAIL '
Expect (Screen-Log -cardfit 'FAIL CARDFIT the title, header and list are inside the card (false) and the list ends -20.0 units above BACK''s top') 'screen' 1 'screen: a failed CARDFIT fails' 'FAIL: .*OK CARDFIT'
# Other installed mods may sit between the expected rows.
Expect (Screen-Log -rows (@($rowLines[0], $rowLines[1], ('ROW Clock | 0.1.0 | toggle=on | box=live | gear=lit | status=0 | icons=- | need=>=0.2.0 | build=V8.2.3 26601774' + (Sc 'client'))) + $rowLines[2..9])) 'screen' 0 'screen: another mod between them is fine' 'All checks passed'
Expect (Screen-Log -rows $rowLines[0..8]) 'screen' 1 'screen: a missing row (PakOff) fails' 'ModManagerPakOff .*found 0'
Expect (Screen-Log -rows ($rowLines + $rowLines[4])) 'screen' 1 'screen: a row twice fails' 'found 2'
Expect (Screen-Log -rows (@($rowLines[1], $rowLines[0]) + $rowLines[2..9])) 'screen' 1 'screen: Nucleus after Mod Manager fails' 'out of order'
function Swap([int] $i, [string] $from, [string] $to) { $r = @($rowLines); $r[$i] = $r[$i] -replace $from, $to; return , $r }
Expect (Screen-Log -rows (Swap 6 'toggle=off' 'toggle=on')) 'screen' 1 'screen: the fixture on fails' 'got 9.9.9 \| toggle=on'
Expect (Screen-Log -rows (Swap 6 'gear=lit' 'gear=dim')) 'screen' 1 'screen: the fixture gear dimmed fails'
Expect (Screen-Log -rows (Swap 1 'gear=dim' 'gear=?')) 'screen' 1 'screen: an unknown gear (Configure showed neither line) fails' 'FAIL: ROW Mod Manager \| .*got .*gear=\?'
Expect (Screen-Log -rows (Swap 7 'need=>=0\.2\.0' 'need=-')) 'screen' 1 'screen: the Long need missing fails'
Expect (Screen-Log -rows (Swap 8 'status=0 \| icons=-' 'status=1 | icons=warning')) 'screen' 1 'screen: a status icon on the pak fails' 'ModManagerPak \|'
Expect (Screen-Log -rows (Swap 6 'status=2 \| icons=warning,warning' 'status=0 | icons=-')) 'screen' 1 'screen: the fixture without its icons fails' 'ModManagerFixture'
Expect (Screen-Log -rows (Swap 2 'status=0 \| icons=-' 'status=1 | icons=warning')) 'screen' 1 'screen: an icon on Base fails' 'Mod Manager Base'
Expect (Screen-Log -rows (Swap 3 'box=live' 'box=fixed')) 'screen' 1 'screen: Dep with a fixed box fails' 'Mod Manager Dep'
Expect (Screen-Log -rows (Swap 8 'box=fixed' 'box=live')) 'screen' 1 'screen: a pak with a live box fails' 'ModManagerPak \|'
Expect (Screen-Log -rows (Swap 0 'toggle=lock \| box=none' 'toggle=on | box=live')) 'screen' 1 'screen: Nucleus without the lock fails' 'ROW Nucleus'
# Story 12: the scope, its tooltip and the RUNS ON line per row.
Expect (Screen-Log -rows (Swap 2 'scope=host \|' 'scope=client |')) 'screen' 1 'screen: Base with the client icon fails' 'Mod Manager Base .*got .*scope=client'
Expect (Screen-Log -rows (Swap 6 'scope=unknown' 'scope=client')) 'screen' 1 "screen: the fixture's retired all read as a real scope fails" 'ModManagerFixture'
# Nucleus's expected scope comes from its deployed mod.json: host there expects host, and a manifest without one expects unknown.
$keepCore = $coreManifest
$coreManifest = Join-Path $tmp 'nucleus-host.json'
Set-Content $coreManifest ((Get-Content $keepCore -Raw) -replace '"scope": "client"', '"scope": "host"')
Expect (Screen-Log) 'screen' 1 "screen: Nucleus's row client while its mod.json says host fails" 'ROW Nucleus .*scope=host .*got .*scope=client'
Expect (Screen-Log -rows (Swap 0 ([regex]::Escape((Sc 'client'))) (Sc 'host'))) 'screen' 0 "screen: Nucleus's row host as its mod.json says passes" 'All checks passed'
$coreManifest = Join-Path $tmp 'nucleus-noscope.json'
Set-Content $coreManifest ((Get-Content $keepCore -Raw) -replace '"scope": "client", ', '')
Expect (Screen-Log -rows (Swap 0 ([regex]::Escape((Sc 'client'))) (Sc 'unknown'))) 'screen' 0 "screen: no scope in Nucleus's mod.json expects unknown" 'All checks passed'
$coreManifest = $keepCore
Expect (Screen-Log -rows (Swap 7 'scope=host-plus' 'scope=host')) 'screen' 1 'screen: Long as host fails' 'ModManagerLong'
Expect (Screen-Log -rows (Swap 3 'stip=HOST AND PLAYERS' 'stip=HOST ONLY')) 'screen' 1 "screen: Dep's tooltip wrong fails" 'Mod Manager Dep'
Expect (Screen-Log -rows (Swap 4 'runs=RUNS ON: UNKNOWN - .*$' 'runs=?')) 'screen' 1 "screen: Bare's Configure without RUNS ON fails" 'ModManagerBare'
Expect (Screen-Log -rows (Swap 0 ' \| scope=.*$' '')) 'screen' 1 'screen: a ROW without the scope fields fails' 'ROW Nucleus .*found 0'
Expect (Screen-Log -rows ($rowLines + ('ROW Keybinds | - | toggle=on | box=live | gear=dim | status=0 | icons=- | need=- | build=-' + (Sc 'unknown')))) 'screen' 1 'screen: a built-in row fails' 'must be absent: Keybinds'
Expect (Screen-Log -rows ($rowLines + ('ROW NuclearNightmare-Windows | UNMANAGED | toggle=on | box=fixed | gear=dim | status=0 | icons=- | need=- | build=-' + (Sc 'unknown')))) 'screen' 1 'screen: the base pak row fails' 'must be absent'
Expect (Screen-Log -rows (Swap 1 ([regex]::Escape("| $MV |")) '| 9.8.7 |')) 'screen' 1 "screen: Mod Manager's version from its mod.json"
Expect (Screen-Log -measure 'MEASURE name width=900.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=405.0 rowLeft=405.0') 'screen' 1 'screen: a long name not cut fails' 'is cut'
Expect (Screen-Log -measure 'MEASURE name width=680.0 desired=820.5 right=1240.0 verLeft=1233.0 headerLeft=405.0 rowLeft=405.0') 'screen' 1 'screen: an overlap fails' 'right edge'
Expect (Screen-Log -measure 'MEASURE name width=680.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=407.5 rowLeft=405.0') 'screen' 1 'screen: a misaligned header fails' 'within 1 unit'
Expect (Screen-Log -measure 'MEASURE name width=680.0 desired=820.5 right=1225.0 verLeft=1233.0 headerLeft=405.8 rowLeft=405.0') 'screen' 0 'screen: within 1 unit passes'
# Story 6: the fixed rows log nothing; the status lines; the toggle, set and quit lines.
Expect (Screen-Log -fixed @((L $M 'TOGGLE ModManagerPak on'))) 'screen' 1 'screen: a [ModManager] line during the fixed clicks fails' 'FIXED the lock and the pak box logged'
Expect (Screen-Log -fixed @((L $M 'WARN hud slow tick 1.4 ms (steady state)'))) 'screen' 0 'vm screen: a slow tick during the fixed clicks is soft' 'soft check' 'vm'
Expect ($good -replace 'STATUS ModManagerBase none \| ', 'STATUS ModManagerBase dep | NEEDS x') 'screen' 1 'screen: Base not none at first fails' 'STATUS ModManagerBase none'
Expect ($good | Where-Object { $_ -notmatch 'STATUS ModManagerFixture build,dep' }) 'screen' 1 'screen: no fixture STATUS fails' 'STATUS ModManagerFixture'
Expect ($good -replace 'INSTALLED: 1\.0\.0', 'INSTALLED: 2.0.0') 'screen' 1 'screen: the wrong fixture tooltip fails' 'STATUS ModManagerFixture'
Expect ($good | Where-Object { $_ -notmatch 'STATUS ModManagerDep dep \|' }) 'screen' 1 'screen: no Dep dependency icon after Base off fails' 'STATUS ModManagerDep dep'
Expect ($good | Where-Object { $_ -notmatch 'TOGGLE ModManagerDep on' }) 'screen' 1 'screen: no TOGGLE Dep on fails' 'TOGGLE ModManagerDep on'
Expect ($good + (L $M 'TOGGLE ModManagerFixture on')) 'screen' 1 'screen: an extra TOGGLE fails' '#7'
# story 11: the first toggle's checks are required; without its two toggles the counts fail.
foreach ($k in 'TGFIRSTCOLD', 'TGFIRSTFOCUS', 'TGFIRST ', 'TGFIRSTCLICK') {
    Expect ($good | Where-Object { $_ -notmatch "OK $k" }) 'screen' 1 "screen: no $($k.Trim()) fails" "OK $($k.Trim())"
}
# core story 39: the three chip checks are required, and a focus chip or list row WARN fails.
foreach ($k in 'CHIP open', 'CHIP tg', 'CHIP cfg', 'CHIP enter1', 'CHIP enter2', 'CIPROBE', 'CHIP backoff') {
    Expect ($good | Where-Object { $_ -notmatch "OK $k " }) 'screen' 1 "screen: no $k fails" "OK $k"
}
Expect ($good + (L $M 'WARN ''r3.tg'': the focus chip failed (is Nucleus''s pak current?): boom')) 'screen' 1 'screen: a focus chip WARN fails' 'focus chip'
Expect ($good + (L $M 'WARN row ''r3'': the list row''s padding was not applied (is Nucleus''s pak current?): boom')) 'screen' 1 'screen: a list row WARN fails' 'list row'
# story 11: a CONFIGURE above the first toggle (it may warm the restart texture) fails.
$cfgFirst = @($good | Where-Object { $_ -notmatch '\] CONFIGURE 1 Nucleus' })
$iCold = [array]::IndexOf($cfgFirst, ($cfgFirst | Where-Object { $_ -match 'OK TGFIRSTCOLD' } | Select-Object -First 1))
Expect ($cfgFirst[0..($iCold - 1)] + (L $M 'CONFIGURE 1 Nucleus') + $cfgFirst[$iCold..($cfgFirst.Count - 1)]) 'screen' 1 'screen: a Configure before the first toggle fails' 'FAIL: TGFIRST came before the first CONFIGURE'
$noFirst = @($good | Where-Object { $_ -notmatch 'TGFIRST|CHIP enter|CIPROBE' })
$i1 = [array]::IndexOf($noFirst, ($noFirst | Where-Object { $_ -match '\] TOGGLE ModManagerDep off' } | Select-Object -First 1))
Expect ($noFirst[0..($i1 - 1)] + $noFirst[($i1 + 8)..($noFirst.Count - 1)]) 'screen' 1 'screen: only one Dep off/on (no first toggle) fails' '#3'
Expect ($good | Where-Object { $_ -notmatch 'cancelled \(close\)' }) 'screen' 1 'screen: no BACK cancel fails' 'cancelled'
Expect ($good | Where-Object { $_ -notmatch 'SET ModManagerFixture later=true' }) 'screen' 1 'screen: no restart setting SET fails' 'later=true'
foreach ($k in 'TGDEPOFF', 'TGDEPON ', 'CONFIRMBACK', 'CONFIRMOFF', 'DEPICON', 'STATEBASE', 'FIXEDINERT', 'SETKINDS', 'SETFILE', 'RESTARTICON', 'QUITPOINT') {
    Expect ($good | Where-Object { $_ -notmatch "OK $k" }) 'screen' 1 "screen: no $k fails"
}
Expect ($good + (L $M 'ALERT nucleus-build')) 'screen' 1 'screen: an ALERT fails' 'ALERT'
# Story 6: the run ends with QUIT GAME after END: the game exited by itself, QUIT after END result=PASS.
Expect (Screen-Log -run '[run.ps1] RUN finished') 'screen' 1 'screen: a run that did not end with the game closing fails' 'RUN game exited'
Expect (Screen-Log -run '[run.ps1] RUN timeout (hang?)') 'screen' 1 'screen: a timeout fails' 'RUN game exited'
Expect (Screen-Log -quitBeforeEnd) 'screen' 1 'screen: QUIT before END fails' 'after END result=PASS'
Expect ($good | Where-Object { $_ -notmatch 'QUIT pending=' }) 'screen' 1 'screen: no QUIT line fails' 'QUIT pending'
Expect ($good + (U 'Unhandled Exception: EXCEPTION_ACCESS_VIOLATION')) 'screen' 1 'screen: a crash at the exit fails' 'Unhandled Exception'
# FILES: mods.txt may change, a pak may not.
Expect (Screen-Log -files '[run.ps1] FILES changed: Paks removed ModManagerPak_P.pak added ModManagerPak_P.pak.disabled') 'screen' 1 'screen: a renamed pak fails' 'Paks\|LogicMods'
Expect (Screen-Log -files '[run.ps1] FILES changed: mods.txt sha256 AB -> CD; LogicMods added X.pak') 'screen' 1 'screen: a pak added with mods.txt fails' 'Paks\|LogicMods'
Expect (Screen-Log -files '') 'screen' 1 'screen: no FILES line fails' 'FILES'
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
Expect ($good + (L $M 'READY entry=manage need=>=0.25.0')) 'screen' 1 'screen: two READY lines fail'
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
Expect ($noCore + (L $M 'READY entry=manage need=>=0.25.0')) 'no-core' 1 'no-core: a second [ModManager] line fails'
Expect ($noCore | Where-Object { $_ -notmatch 'NOENTRY' }) 'no-core' 1 'no-core: no NOENTRY fails'
$oldCore = (Start-Log) + @((L $D "OLDCORE published nucleus.version=0.1.0 (from Nucleus's installed mod.json)"),
    (L $M 'ERROR Nucleus 0.1.0 is older than ModManager needs (>=0.25.0). Update Nucleus. ModManager will not run.'),
    (L $D 'OK NOENTRY no MANAGE MODS entry in the menu for 15 s'), (L $D 'END result=PASS checks=2 failures=0'), '[run.ps1] FILES unchanged')
Expect $oldCore 'old-core' 0 'old-core: passes' 'All checks passed'
Expect ($oldCore + (L $M 'ERROR start failed: x')) 'old-core' 1 'old-core: a second [ModManager] line fails'
Expect ($oldCore -replace 'needs \(>=0.25.0\)', 'needs (>=0.7.0)') 'old-core' 1 'old-core: the wrong need fails'

# ---------------------------------------------------------------- restart (story 8): two sessions in one log
$R = 'ModManagerRestart'
function Session([int] $n) {
    (Start-Log) + @((L $R 'loaded') | Where-Object { $n -eq 1 }) + @(
        (L $D 'SCENARIO restart'), (L $D "RESTART session $n"), (L $D 'LOADED 20 steps'),
        (L $M 'CONNECT ok Nucleus 0.21.0 (pong 0.21.0 boot=1)'), (L $M 'READY entry=manage need=>=0.25.0'),
        (L $M 'OPEN rows=10 total=10 lang=en game=V8.2.3 build=- us=4000'), (L $M 'RESTARTMODE direct'))
}
$s1 = (Session 1) + @(
    (L $D 'OK RSLOADED1 x'), (L $D 'OK RSROW1 x'), (L $D 'OK RSHIDDEN x'), (L $D 'OK RSTXT0 x'), (L $M "TOGGLE $R off"), (L $M "STATUS $R restart | TURNS OFF AFTER A RESTART"),
    (L $D 'OK RSOFF x'), (L $D 'OK RSSHOWN x'), (L $D 'OK RSPLACE x'), (L 'Nucleus' 'native: restart: helper started (mode=direct, pid=4242)'),
    (L $D 'OK RSMODULE x'), (L $D 'OK RSMODE x'), (L $D 'OK RSSTART1 x'), (L $D 'OK RSSTART2 x'), (L $D 'OK RSFACTS x'), (L $D 'CLICK RESTART NOW at (900,700)'),
    (L $M 'RESTART mode=direct pending=1'))
$s2 = (Session 2) + @(
    (L $D 'FACTS mode=direct start1=true start2=nil already started checks=14 failures=0'), (L $D 'OK RSFACTS2 x'), (L $D 'OK RSNOTLOADED x'),
    (L $D 'OK RSROW2 x'), (L $D 'OK RSNOPENDING x'), (L $D 'OK RSTXT2 x'), (L $M "TOGGLE $R on"), (L $D 'OK RSSHOWN2 x'), (L $D 'OK QUITPOINT x'),
    (L $D 'END result=PASS checks=9 failures=0'), (L $D 'CLICK QUIT GAME at (900,740)'), (L $M 'QUIT pending=1'))
$tail = @('[run.ps1] RELAUNCH old=100 new=200 cmdline=same userdir=yes',
    '[run.ps1] MOTW NuclearNightmare/Binaries/Win64/ue4ss/Mods/Nucleus/bin/NucleusRestart.exe ZoneId=3',
    '[run.ps1] DEFENDER status realtime=True behavior=True smartappcontrol=Off signatures=1.463.380.0 since=2026-11-20T01:00:00',
    '[run.ps1] DEFENDER detections=0', '[run.ps1] DEFENDER events=0', '[run.ps1] DEFENDER codeintegrity-blocks=0',
    '[run.ps1] RUN game exited (crash?)', '[run.ps1] FILES unchanged',
    "[run.ps1] BUILDSCAN main.dll no threats found signatures=1.463.380.0 package=same",
    "[run.ps1] BUILDSCAN bin/NucleusRestart.exe no threats found signatures=1.463.380.0 package=same")
$rgood = $s1 + @('[run.ps1] SESSION 2 (relaunched by the game)') + $s2 + $tail
Expect $rgood 'restart' 0 'restart: passes' 'All checks passed'
Expect ($rgood -replace 'cmdline=same', 'cmdline=differs') 'restart' 1 'restart: a different command line fails'
Expect ($rgood -replace 'userdir=yes', 'userdir=no') 'restart' 1 'restart: no -userdir fails'
Expect ($rgood | Where-Object { $_ -notmatch 'SESSION 2' }) 'restart' 1 'restart: no second session fails'
Expect ($rgood -replace 'DEFENDER detections=0', 'DEFENDER detections=1') 'restart' 1 'restart: a Defender detection fails'
Expect ($rgood + '[run.ps1] DEFENDER event id=1116 at=x Microsoft Defender Antivirus has detected malware') 'restart' 1 'restart: a Defender event line fails'
Expect ($rgood -replace 'realtime=True', 'realtime=False') 'restart' 1 'restart: real-time protection off fails'
Expect ($rgood -replace 'codeintegrity-blocks=0', 'codeintegrity-blocks=1') 'restart' 1 'restart: a Code Integrity block fails'
Expect ($rgood -replace 'ZoneId=3', 'not set (read back: )') 'restart' 1 'restart: no Mark of the Web fails'
Expect ($rgood -replace 'NucleusRestart\.exe no threats found(.*)package=same', 'NucleusRestart.exe no threats found$1package=differs') 'restart' 1 'restart: a scan of another helper fails'
Expect ($s1 + @('[run.ps1] SESSION 2 (relaunched by the game)') + $s2 + (L $R 'loaded') + $tail) 'restart' 1 'restart: the fixture loading in session 2 fails' 'session 2: '
Expect ($s1 + @('[run.ps1] SESSION 2 (relaunched by the game)') + (($s2 | Where-Object { $_ -notmatch 'QUIT pending' })) + $tail) 'restart' 1 'restart: no QUIT in session 2 fails'
Expect (($s1 | Where-Object { $_ -notmatch 'RESTART mode=' }) + @('[run.ps1] SESSION 2 (relaunched by the game)') + $s2 + $tail) 'restart' 1 'restart: no RESTART line in session 1 fails' 'session 1: '
Expect ($s1 + (L $D 'END result=FAIL checks=3 failures=1') + @('[run.ps1] SESSION 2 (relaunched by the game)') + $s2 + $tail) 'restart' 1 'restart: an END line in session 1 fails'
Expect ($s1 + @('[run.ps1] SESSION 2 (relaunched by the game)') + $s2 + (L 'Nucleus' 'native: restart: helper started (mode=direct, pid=5)') + $tail) 'restart' 1 'restart: a helper started in session 2 fails'

# ---------------------------------------------------------------- apply (Mod Manager v2 story 3): four sessions in one log
$AA = 'ModManagerApplyA'; $AB = 'ModManagerApplyB'; $AC = 'ModManagerApplyC'
$lockRel = "NuclearNightmare\Binaries\Win64\ue4ss\Mods\$AA\Scripts\main.lua"
function ApplySession([int] $n, [string] $status, [string[]] $loaded) {
    (Start-Log) + @($loaded | ForEach-Object { L $_ 'loaded' }) + @(
        (L $D 'SCENARIO apply'), (L $D "APPLY session $n"), (L $D 'LOADED 20 steps'),
        (L $M 'CONNECT ok Nucleus 0.24.0 (pong 0.24.0 boot=1)'), (L $M 'READY entry=manage need=>=0.25.0'), (L $M "APPLY status $status"))
}
$a1 = (ApplySession 1 'staged=pending result=none changes=3 attempts=0' @()) + @(
    (L $M 'APPLY start ok'), (L $D 'OK APWAIT1 x'), (L $D 'OK APRESULT1 x'), (L $D 'OK APNOTLOADED1 x'),
    (L $M 'OPEN rows=10 total=10 lang=en game=V8.2.3 build=- us=4000'), (L $M 'RESTARTMODE direct'), (L $D 'OK APSHOWN1 x'),
    (L $D 'CLICK RESTART NOW at (900,700)'), (L $M 'RESTART mode=direct pending=1'))
$a2 = (ApplySession 2 'staged=none result=applied changes=0 attempts=0' @($AA)) + @(
    (L $D 'OK APLOADED2 x'), (L $D 'OK APRESULT2 x'), (L $M 'OPEN rows=11 total=11 lang=en game=V8.2.3 build=- us=4000'),
    (L $M 'APPLY result applied reason=- path=- attempts=0'), (L $M 'APPLY ack ok'), (L $D 'OK APACKED2 x'),
    (L $D 'OK APSTAGED2 x'), (L $D 'OK APSTART2 x'), (L $D 'OK APWAIT2 x'), (L $D 'KILL requested'))
$a3 = (ApplySession 3 'staged=none result=applied changes=0 attempts=0' @($AA, $AB)) + @(
    (L $D 'OK APLOADED3 x'), (L $D 'OK APRESULT3 x'), (L $D 'OK APSTAGED3 x'), (L $D 'OK APLOCK3 x'), (L $D 'OK APSTART3 x'), (L $D 'OK APWAIT3 x'),
    (L $D 'CLOSE requested'))
$a4 = (ApplySession 4 'staged=pending result=failed changes=4 attempts=1' @($AA, $AB)) + @(
    (L $M 'APPLY start ok'), (L $D 'OK APRESULT4 x'), (L $D 'OK APPENDING4 x'), (L $D 'OK APSAME4 x'), (L $D 'OK APNOC4 x'), (L $D 'OK APNOTLOADED4 x'),
    (L $M 'OPEN rows=12 total=12 lang=en game=V8.2.3 build=- us=4000'), (L $M "APPLY result failed reason=locked path=$lockRel attempts=1"),
    (L $M 'APPLY ack ok'), (L $D 'OK APSHOWN4 x'), (L $D 'END result=PASS checks=30 failures=0'))
$atail = @('[run.ps1] RELAUNCH old=100 new=200 cmdline=same userdir=yes',
    '[run.ps1] MOTW NuclearNightmare/Binaries/Win64/ue4ss/Mods/Nucleus/bin/NucleusRestart.exe ZoneId=3',
    '[run.ps1] DEFENDER status realtime=True behavior=True smartappcontrol=Off signatures=1.463.380.0 since=2026-11-20T01:00:00',
    '[run.ps1] DEFENDER detections=0', '[run.ps1] DEFENDER events=0', '[run.ps1] DEFENDER cfa=off', '[run.ps1] DEFENDER cfa-events=0',
    '[run.ps1] DEFENDER codeintegrity-blocks=0', '[run.ps1] DEFENDER samples-submitted=0',
    '[run.ps1] RUN finished', '[run.ps1] FILES changed: mods.txt sha256 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA -> BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    "[run.ps1] BUILDSCAN main.dll no threats found signatures=1.463.380.0 package=same",
    "[run.ps1] BUILDSCAN bin/NucleusRestart.exe no threats found signatures=1.463.380.0 package=same")
$S2 = '[run.ps1] SESSION 2 (relaunched by the game)'; $S3 = '[run.ps1] SESSION 3 (relaunched by the runner after kill)'; $S4 = '[run.ps1] SESSION 4 (relaunched by the runner after close)'
function ApplyLog($p1 = $a1, $p2 = $a2, $p3 = $a3, $p4 = $a4, $tl = $atail) { @($p1) + $S2 + @($p2) + $S3 + @($p3) + $S4 + @($p4) + @($tl) }
$agood = ApplyLog
Expect $agood 'apply' 0 'apply: passes' 'All checks passed'
Expect ($agood | Where-Object { $_ -ne $S3 }) 'apply' 1 'apply: a missing session fails'
Expect ($agood -replace 'SESSION 2 \(relaunched by the game\)', 'SESSION 2 (relaunched by the runner after exit)') 'apply' 1 'apply: RESTART NOW not relaunched by the game fails'
Expect ($agood -replace 'after kill\)', 'after exit)') 'apply' 1 'apply: session 3 not after a kill fails'
Expect ($agood -replace 'after close\)', 'after exit)') 'apply' 1 'apply: session 4 not after a close fails'
Expect (ApplyLog -p1 ($a1 | Where-Object { $_ -notmatch 'APPLY start ok' })) 'apply' 1 'apply: no helper started at launch in session 1 fails' 'session 1: '
Expect (ApplyLog -p1 ($a1 | Where-Object { $_ -notmatch 'OK APWAIT1' })) 'apply' 1 'apply: the helper not waiting in session 1 fails' 'session 1: '
Expect (ApplyLog -p1 ($a1 | Where-Object { $_ -notmatch 'RESTART mode=' })) 'apply' 1 'apply: no RESTART NOW in session 1 fails' 'session 1: '
Expect (ApplyLog -p2 ($a2 | Where-Object { $_ -notmatch "\[$AA\] loaded" })) 'apply' 1 'apply: A not loaded after the restart fails' 'session 2: '
Expect (ApplyLog -p2 ($a2 | Where-Object { $_ -notmatch 'APPLY result applied' })) 'apply' 1 'apply: no applied result in session 2 fails' 'session 2: '
Expect (ApplyLog -p2 ($a2 | Where-Object { $_ -notmatch 'APPLY ack ok' })) 'apply' 1 'apply: no ack in session 2 fails' 'session 2: '
Expect (ApplyLog -p2 ($a2 -replace 'OK APWAIT2', 'FAIL APWAIT2')) 'apply' 1 'apply: a driver FAIL fails'
Expect (ApplyLog -p3 ($a3 | Where-Object { $_ -notmatch "\[$AB\] loaded" })) 'apply' 1 'apply: B not loaded after the kill fails' 'session 3: '
Expect (ApplyLog -p3 ($a3 | Where-Object { $_ -notmatch 'OK APLOCK3' })) 'apply' 1 'apply: no lock check in session 3 fails' 'session 3: '
Expect (ApplyLog -p4 ($a4 -replace 'reason=locked', 'reason=io-error')) 'apply' 1 'apply: another failure reason fails' 'session 4: '
Expect (ApplyLog -p4 ($a4 -replace 'attempts=1$', 'attempts=2')) 'apply' 1 'apply: a second attempt fails' 'session 4: '
Expect (ApplyLog -p4 ($a4 -replace [regex]::Escape("$AA\Scripts\main.lua"), "$AA\mod.json")) 'apply' 1 'apply: another path fails' 'session 4: '
Expect (ApplyLog -p4 ($a4 | Where-Object { $_ -notmatch 'OK APSAME4' })) 'apply' 1 'apply: A not checked byte-identical fails' 'session 4: '
Expect (ApplyLog -p4 ($a4 + (L $AC 'loaded'))) 'apply' 1 'apply: C loading fails'
Expect (ApplyLog -p4 ($a4 -replace 'END result=PASS', 'END result=FAIL')) 'apply' 1 'apply: END result=FAIL fails'
Expect (ApplyLog -p4 ($a4 + (L $M 'QUIT pending=1'))) 'apply' 1 'apply: a QUIT GAME in session 4 fails' 'session 4: '
Expect ($agood -replace 'RUN finished', 'RUN timeout (hang?)') 'apply' 1 'apply: a run that did not reach END fails'
Expect ($agood -replace 'cmdline=same', 'cmdline=differs') 'apply' 1 'apply: a different command line fails'
Expect ($agood -replace 'ZoneId=3', 'not set (read back: )') 'apply' 1 'apply: no Mark of the Web fails'
Expect ($agood -replace 'DEFENDER detections=0', 'DEFENDER detections=1') 'apply' 1 'apply: a Defender detection fails, saying blocked' 'stop the story as blocked'
Expect ($agood + '[run.ps1] DEFENDER event id=1116 at=x Microsoft Defender Antivirus has detected malware') 'apply' 1 'apply: a Defender event fails, saying blocked' 'stop the story as blocked'
Expect ($agood -replace 'cfa-events=0', 'cfa-events=1') 'apply' 1 'apply: a Controlled Folder Access event fails, saying blocked' 'stop the story as blocked'
Expect ($agood + '[run.ps1] DEFENDER cfa-event id=1123 at=x Controlled Folder Access blocked NucleusRestart.exe') 'apply' 1 'apply: a CFA event line fails' 'stop the story as blocked'
Expect ($agood | Where-Object { $_ -notmatch 'DEFENDER cfa=' }) 'apply' 1 'apply: no CFA state fails'
Expect ($agood -replace 'codeintegrity-blocks=0', 'codeintegrity-blocks=1') 'apply' 1 'apply: a Code Integrity block fails, saying blocked' 'stop the story as blocked'
Expect ($agood -replace 'behavior=True', 'behavior=False') 'apply' 1 'apply: behaviour monitoring off fails'
Expect ($agood -replace 'NucleusRestart\.exe no threats found(.*)package=same', 'NucleusRestart.exe no threats found$1package=differs') 'apply' 1 'apply: a scan of another helper fails'
Expect ($agood -replace 'FILES changed: mods\.txt.*', 'FILES changed: Paks added x_P.pak') 'apply' 1 'apply: a pak change fails'

# ---------------------------------------------------------------- browse (Mod Manager v2 story 4)
$NN = 'nuclearnightmare-community'
function BrowseLog([string[]] $pkgs, [string[]] $filters, [string[]] $rows = @('ROW Nucleus | 0.25.0', 'ROW Mod Manager | 0.6.0', 'ROW ModManagerDriver | -'), [int] $dones = 2) {
    $l = (Start-Log) + @((L $D 'SCENARIO browse'), (L $D 'LOADED 60 steps'),
        (L $M 'CONNECT ok Nucleus 0.25.0 (pong 0.25.0 boot=1)'), (L $M 'CATALOG refresh job=1'), (L $M 'READY entry=manage need=>=0.25.0'),
        (L $M 'BUILD 26601774 from=index'))
    foreach ($p in $pkgs) { $l += L $M "BROWSE pkg $p" }
    $l += L $M "CATALOG done outcome=ok source=network packages=$($pkgs.Count) index_issued=2026-11-21T00:59:08Z"
    $l += L $D 'OK BWDONE startup 1 CATALOG done line(s) (want 1)'
    $l += L $M 'OPEN rows=3 total=3 lang=en game=V8.2.3 build=- us=4000'
    foreach ($r in $rows) { $l += L $D $r }
    $l += L $D 'OK BWROWS 3 installed rows'
    foreach ($f in $filters) { $l += L $M "BROWSE filter $f" }
    $l += L $M "BROWSE open shown=5 total=5 state=ok"
    foreach ($ok in 'BWOPEN x', 'BWLIST x', 'BWCAT x', 'BWSHOW x', 'BWRESET x', 'BWSEARCH x', 'BWDETAILS x') { $l += L $D "OK $ok" }
    $l += L $M "DETAILS $NN.hud-clock lines=1"
    if ($dones -ge 2) {
        $l += L $M 'CATALOG refresh job=2'
        $l += L $M "CATALOG done outcome=ok source=network packages=$($pkgs.Count) index_issued=2026-11-21T00:59:08Z"
        $l += L $D 'OK BWDONE after REFRESH 2 CATALOG done line(s) (want 2)'
    }
    $l += L $D 'END result=PASS checks=12 failures=0'
    $l += '[run.ps1] RUN finished'
    $l += '[run.ps1] FILES unchanged'
    return $l
}
$bPkgs = @("$NN.nucleus v=0.22.0 cat=library scope=client state=installed core=ok", "$NN.mod-manager v=0.4.0 cat=tools,ui scope=client state=installed core=ok",
    "$NN.hud-clock v=0.3.0 cat=ui,qol scope=client state=available core=ok", "$NN.waypoints v=0.3.1 cat=qol,ui scope=client state=available core=ok",
    "$NN.whistle-mute v=0.2.1 cat=audio,qol scope=client state=available core=ok")
$all5 = "$NN.hud-clock,$NN.waypoints,$NN.mod-manager,$NN.nucleus,$NN.whistle-mute"
$bFilters = @("cat=all show=all scope=all for=game q= shown=5 ids=$all5", "cat=audio show=all scope=all for=game q= shown=1 ids=$NN.whistle-mute",
    'cat=audio show=installed scope=all for=game q= shown=0 ids=-', "cat=all show=all scope=all for=game q= shown=5 ids=$all5",
    "cat=all show=all scope=all for=game q=c shown=1 ids=$NN.hud-clock", "cat=all show=all scope=all for=game q=clock shown=1 ids=$NN.hud-clock")
$bgood = BrowseLog $bPkgs $bFilters
Expect $bgood 'browse' 0 'browse: passes' 'All checks passed' 'vm'
Expect (BrowseLog $bPkgs ($bFilters[0..2] + "cat=all show=installed scope=all for=game q= shown=1 ids=$NN.nucleus" + $bFilters[3..5])) 'browse' 1 'browse: a filter line that differs from the pkg lines fails' 'differ from the recomputation' 'vm'
Expect (BrowseLog $bPkgs ($bFilters[0..4] + "cat=all show=all scope=all for=game q=clock shown=1 ids=$NN.base")) 'browse' 1 'browse: a search id outside the pkg lines fails' 'outside the recomputation' 'vm'
Expect (BrowseLog $bPkgs ($bFilters[0..4] + "cat=all show=all scope=all for=game q=clock shown=2 ids=$NN.hud-clock,$NN.waypoints")) 'browse' 1 'browse: clock with two ids fails' 'clock' 'vm'
Expect (BrowseLog ($bPkgs + "$NN.base v=0.6.0 cat=- scope=unknown state=available core=ok") $bFilters) 'browse' 1 'browse: a base package listed fails' 'base' 'vm'
Expect (BrowseLog ($bPkgs -replace 'hud-clock v=0.3.0 cat=ui,qol scope=client state=available', 'hud-clock v=0.3.0 cat=ui,qol scope=client state=installed') ($bFilters -replace "show=installed scope=all for=game q= shown=0 ids=-", "show=installed scope=all for=game q= shown=0 ids=-")) 'browse' 1 'browse: a state that disagrees with the ROW lines fails' 'STATE .*hud-clock' 'vm'
Expect (BrowseLog $bPkgs $bFilters -rows @('ROW Mod Manager | 0.6.0')) 'browse' 1 'browse: Nucleus installed without its ROW line fails' 'STATE .*nucleus' 'vm'
Expect (BrowseLog $bPkgs $bFilters -dones 1) 'browse' 1 'browse: no second done fails' 'CATALOG done' 'vm'
Expect (BrowseLog ($bPkgs | Where-Object { $_ -notmatch 'waypoints' }) ($bFilters -replace ",$NN.waypoints", '' -replace 'shown=5', 'shown=4')) 'browse' 1 'browse: one of the five missing fails' 'missing' 'vm'
Expect ($bgood + (L $M 'WARN catalog package 3 skipped: no name')) 'browse' 1 'browse: a WARN fails' '' 'vm'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("check_test: {0} passed, {1} failed" -f $script:passed, $script:failed)
exit $(if ($script:failed) { 1 } else { 0 })
