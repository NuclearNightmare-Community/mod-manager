<#
.SYNOPSIS
  Judges one run of the Mod Manager from UE4SS.log.
.DESCRIPTION
  Prints the Mod Manager's, the driver's and UE4SS's relevant lines, then checks the patterns the scenario needs.
  A pattern must match somewhere; "!pattern" must match nowhere; "#N|pattern" must match exactly N lines;
  "?pattern" is a soft check (reported as "warn:", never failing); "?!pattern" is a soft check that it matches nowhere.
  Then the scenario's computed checks (screen):
    - the ROW lines: Nucleus, Mod Manager, Mod Manager Base, Mod Manager Dep, ModManagerBare, ModManagerDriver,
      ModManagerFixture, ModManagerLong..., ModManagerPak and ModManagerPakOff each exactly once, in that relative order
      (other installed mods may sit between them), with the values of the stories' I/O matrices; Nucleus's and the Mod
      Manager's expected values (their scope too) come from their deployed mod.json (-CoreManifest; this repo's mod.json). Per row: the
      toggle (lock | on | off), its box (none | live | fixed), the gear (what the row's Configure offers: dim for NO
      SETTINGS, lit for a settings list; not its look), the status icons (the fixture: build and dependency;
      every other row none), story 12's scope (from the icon's texture: Nucleus and the Mod Manager client, Base host,
      Dep both, Long host-plus, the fixture's retired 'all' and every row without a mod.json unknown), its tooltip
      (stip, that scope's words) and Configure's RUNS ON line (runs, 'RUNS ON: ' and the same words). No row for a
      UE4SS built-in, shared or NuclearNightmare-Windows.
    - GEARLOOK: at least one "OK GEARLOOK ... looks dim (offers dim)" (a dimmed gear drawn as its Configure offers;
      a gear holding keyboard focus is skipped; a FAIL GEARLOOK fails the run like any driver FAIL).
    - STATUS (story 6): the Mod Manager's first STATUS line for Nucleus, ModManagerBase, ModManagerDep and ModManagerBare
      is "none"; the fixture's names both games and both dependency problems.
    - MEASURE: the long name's desired width over its allotted width (cut), its right edge left of the version
      column's left edge, the header's NAME within 1 unit of the row's name.
    - TGFIRST (story 11): the first toggle of the session, before any Configure and with no restart icon shown
      (TGFIRSTCOLD: core's restart texture still cold): ENTER on Dep's focused checkbox
      (TGFIRSTFOCUS) turns it off within 10 s with the restart icon (TGFIRST); core story 42: core's CommonInput calls
      work (CIPROBE: the class, the subsystem, a number input type, a boolean simulated-click flag), the focus chip stays on
      the checkbox, over core's dark IconBack with the icon not in the chip's ink, after that ENTER (CHIP enter1, box
      off) and after a second ENTER (CHIP enter2, box on), a third ENTER turns it off again; a mouse click turns it back
      on within 10 s (TGFIRSTCLICK) and the IconBack is collapsed after it (CHIP backoff); so Dep is toggled off and on
      three times in the run, seven TOGGLE lines in all.
    - FIXED: no [ModManager] line between the driver's FIXED begin and FIXED end (the lock and a pak's box log nothing).
    - QUIT: the game closed itself ("[run.ps1] RUN game exited") with "[ModManager] QUIT pending=" after the driver's
      "END result=PASS".
    - FILES (run.ps1 appends it): screen: the pak folders as they were after the deploy (mods.txt may change: the
      scenario turns Base off); no-core and old-core: unchanged.
  restart (story 8; the VM runner's log holds both sessions, split at "[run.ps1] SESSION 2"): the whole log has no
  crash or driver FAIL, "[run.ps1] RELAUNCH ... cmdline=same userdir=yes", "[run.ps1] MOTW ...Restart.exe ZoneId=3",
  Defender's real-time and behaviour monitoring on with no detection, no event 1006/1015/1116/1117 and no Code
  Integrity block since the launch, and build.ps1's scans of main.dll and the helper "no threats found" for the
  packaged files (BUILDSCAN ... package=same); session 1: ModManagerRestart loaded, the driver's RS* checks, core's
  "helper started (mode=direct" once, "[ModManager] RESTART mode=direct pending=1" once, no END line; session 2: the
  Mod Manager running once more, no ModManagerRestart line, no helper started, the driver's facts and RS* checks, END
  result=PASS, then "[ModManager] QUIT pending=1" and the game closing itself. A failed check here is the story's
  evidence: a Defender, SmartScreen or Smart App Control line means stop and report, never work around it.
  apply (Mod Manager v2 story 3; the VM runner's log holds four sessions, split at its "[run.ps1] SESSION <n>" lines,
  which must read 2 relaunched by the game, 3 relaunched by the runner after kill, 4 after close): the whole log has no
  crash or driver FAIL, no "[ModManagerApplyC] loaded", one "RELAUNCH ... cmdline=same userdir=yes", "RUN finished",
  the MOTW and BUILDSCAN lines as restart, Defender's real-time and behaviour monitoring on, detections=0, events=0,
  cfa-events=0 (Controlled Folder Access 1123/1124), codeintegrity-blocks=0. Session 1: the Mod Manager's "APPLY
  status staged=pending result=none" and "APPLY start ok", the driver's AP*1 checks (the helper waiting, RESTART NOW
  shown), "CLICK RESTART NOW", "RESTART mode=direct"; session 2: "[ModManagerApplyA] loaded", "APPLY result applied",
  "APPLY ack ok", the driver's AP*2 checks (stage B pending, start() true, waiting); session 3: A and B loaded, the
  AP*3 checks (stage C, A's file locked, waiting); session 4: "APPLY start ok", "APPLY result failed reason=locked
  path=<A's Scripts\main.lua> attempts=1", "APPLY ack ok", the AP*4 checks (A byte-identical, none of C's files, C
  still pending, the buttons shown), END result=PASS. Any detection, event or block fails the run with a line saying
  the story stops blocked with that evidence.
  browse (Mod Manager v2 story 4; VM, the live catalog): two refreshes (startup and REFRESH), each "CATALOG done
  outcome=ok source=network", "BUILD <this repo's mod.json game.build> from=index|manifest", BROWSE open with at least five
  packages and state=ok, no base or installer package, Nucleus and the Mod Manager installed with their Nucleus need met,
  the CATEGORY audio and SHOW installed filter lines, the "clock" search leaving only HUD Clock, one DETAILS line, the
  driver's BW* checks, FILES unchanged; computed: every BROWSE filter line's ids recomputed from the run's own BROWSE
  pkg lines (equal without a search, a subset with one), the five mods of this build present, each package's state
  agreeing with the driver's ROW lines (named through -CatalogIndex: installed or update when a ROW line has its display
  name, else available), the second CATALOG done after DETAILS.
  Exit code 1 when any check fails; otherwise prints "All checks passed."
  Scenarios: screen, no-core, old-core, restart, apply, browse (run.ps1 drives them); unit needs no log: it runs test.ps1.
  -Target vm: a log from run.ps1 -Target vm. The VM's game shares the CPU with the host, so core's "hud slow tick"
  WARN under the Mod Manager's tag is soft there.
.EXAMPLE
  ./check.ps1 -Log C:\...\nuclear-nightmare\dumps\v8.2.3-build26601774\mod-manager\screen.vm.log -Scenario screen -Target vm
#>
param(
    [string] $Instance,
    [string] $Log,
    [ValidateSet('screen', 'no-core', 'old-core', 'restart', 'apply', 'browse', 'unit')]
    [string] $Scenario = 'screen',
    [ValidateSet('host', 'vm')] [string] $Target = 'host',
    [string] $CoreManifest, # Nucleus's deployed mod.json; default: -Instance's, else the workspace's mods/Nucleus/build/package
    [string] $CatalogIndex  # browse: the catalog's index.json to name packages by (default: the workspace's catalog/index.json)
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
    $_ -match "\[$M\]|\[$D\]|^\[run\.ps1\]|\[${M}Restart\]|\[${M}Apply[ABC]\]|\[$K\] native: (restart|apply)" -or
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
    # Story 6: the Mod Manager never renames, adds or removes a pak.
    '!^\[run\.ps1\] FILES changed: .*(Paks|LogicMods)'
)
$running = @(
    "\[$M\] CONNECT ok $K \d+\.\d+\.\d+ "
    "#1|\[$M\] READY entry=manage need=$NeedRx\s*$"
    "!\[$M\] ERROR"
    # Core's UI helpers log with the Mod Manager's tag; a slow tick of core's poller is core's to judge. In the VM every
    # slow tick is soft: the VM's game shares the CPU with the host.
    $(if ($Target -eq 'vm') { "!\[$M\] WARN (?!hud slow tick )" } else { "!\[$M\] WARN (?!hud slow tick .*(HUD event|steady state, a Lua GC step ran inside it))" })
    "?!\[$M\] WARN hud slow tick "
    # Core's card (0.12.0): a window whose content is larger than the viewport allows. Named so a failure says so.
    "!\[$M\] WARN window '.*': its content .* the card is clamped"
    # Story 6: Nucleus was made for this game: no alert.
    "!\[$M\] ALERT"
)
$expect = @{
    'screen' = $running + @(
        "\[$D\] SCENARIO screen\s*$"
        "\[$D\] END result=PASS"
        "\[$D\] ENTRY menu1 text=MANAGE MODS above=OPTIONS below=QUIT\s*$"
        "\[$D\] OK ENTRYPOS menu1 ", "\[$D\] OK ENTRYLOOK menu1 ", "\[$D\] OK ENTRYPOS menu2 ", "\[$D\] OK ENTRYLOOK menu2 "
        "\[$D\] OK OPEN first ", "\[$D\] OK TITLE first "
        "\[$D\] OK MEASURECUT ", "\[$D\] OK MEASUREEDGE ", "\[$D\] OK MEASUREALIGN "
        "\[$D\] OK CARDFIT "
        # story 10: ROW's gear is what Configure offers; the look is judged on gears without keyboard focus
        "\[$D\] OK GEARLOOK .* looks dim \(offers dim\)"
        # story 6: on/off, the confirm, the icons, the banner and QUIT GAME, state.json, the fixed rows
        "\[$D\] OK TGROWS ", "\[$D\] OK TXT0 ", "\[$D\] OK TGLIVE ", "\[$D\] OK TGSTART ", "\[$D\] OK TGDEPOFF ", "\[$D\] OK TGNOCONFIRM "
        "\[$D\] OK TGDEPICON ", "\[$D\] OK PENDINGUI ", "\[$D\] OK STATEOFF ", "\[$D\] OK CARDFIT2 ", "\[$D\] OK TGDEPON ", "\[$D\] OK TGDEPON2 "
        "\[$D\] OK PENDINGOFF ", "\[$D\] OK STATEON ", "\[$D\] OK CONFIRMTEXT ", "\[$D\] OK CONFIRMWAIT ", "\[$D\] OK CONFIRMBACK "
        "\[$D\] OK CONFIRMCLOSED ", "\[$D\] OK CONFIRMOFF ", "\[$D\] OK TGBASEICON ", "\[$D\] OK DEPICON ", "\[$D\] OK PENDINGUI2 "
        "\[$D\] OK STATEBASE ", "\[$D\] OK PAKFIXED ", "\[$D\] OK FIXEDINERT "
        # story 11: the first toggle before any Configure (cold T_Restart): ENTER on Dep's focused checkbox, then a mouse click
        "\[$D\] OK TGFIRSTCOLD ", "\[$D\] OK TGFIRSTFOCUS ", "\[$D\] OK TGFIRST ", "\[$D\] OK TGFIRSTCLICK "
        # core story 39 (0.15.4): no focus chip after the mouse open; the chip on Base's checkbox after LEFT, on its gear after RIGHT; no chip WARN
        "\[$D\] OK CHIP open ", "\[$D\] OK CHIP tg ", "\[$D\] OK CHIP cfg "
        # core story 42 (0.17.1): the chip stays on Dep's focused checkbox after ENTER, box off then on
        "\[$D\] OK CHIP enter1 ", "\[$D\] OK CHIP enter2 ", "\[$D\] OK CIPROBE ", "\[$D\] OK CHIP backoff "
        "!\[$M\] WARN .*(focus chip|list row)"
        "#3|\[$M\] TOGGLE ModManagerDep off\s*$", "#3|\[$M\] TOGGLE ModManagerDep on\s*$", "#1|\[$M\] TOGGLE ModManagerBase off\s*$"
        "#7|\[$M\] TOGGLE "
        "#1|\[$M\] CONFIRM ModManagerBase cancelled \(close\)\s*$"
        # story 6: Configure's problem lines and settings
        "\[$D\] OK CFGPROBLEMS ", "\[$D\] OK SETKINDS ", "\[$D\] OK SETBY ", "\[$D\] OK SETRO ", "\[$D\] OK SETMARK ", "\[$D\] OK SETFILE "
        "\[$D\] OK RESTARTICON ", "\[$D\] OK CFGRESTART ", "\[$D\] OK SETNOMSG "
        "#1|\[$M\] SET ModManagerFixture flag=true\s*$", "#1|\[$M\] SET ModManagerFixture mode=two\s*$"
        "#1|\[$M\] SET ModManagerFixture example=7\s*$", "#1|\[$M\] SET ModManagerFixture later=true\s*$"
        "\[$M\] STATUS ModManagerFixture build,dep \| MADE FOR GAME V0\.0\.0 \(BUILD 1\)\. THIS GAME: V\d[^ ]* \(BUILD [-\d]+\)\. / NEEDS nuclearnightmare-community\.mod-manager-missing \(NOT INSTALLED\) / NEEDS Mod Manager Base >=2\.0\.0 \(INSTALLED: 1\.0\.0\)\s*$"
        "\[$M\] STATUS ModManagerDep dep \| NEEDS Mod Manager Base \(TURNED OFF\)\s*$"
        # story 6: the end: QUIT GAME after END
        "\[$D\] OK QUITUI ", "\[$D\] OK BANNER ", "\[$D\] OK QUITPOINT "
        "#1|\[$M\] QUIT pending=[1-9]\d*\s*$"
        '^\[run\.ps1\] RUN game exited'
        '^\[run\.ps1\] FILES (unchanged|changed: mods\.txt sha256 [0-9A-F]{64} -> [0-9A-F]{64})$'
        "\[$D\] OK CFGTOP ", "\[$D\] OK CFGFIXTURE ", "\[$D\] OK CFGCLOSE ", "\[$D\] OK CFGDIM ", "\[$D\] OK CFGDIMOPEN "
        "\[$D\] OK BLOCKEDGEAR ", "\[$D\] OK BLOCKED ", "\[$D\] OK CFGCLOSE2 ", "\[$D\] OK CLOSEMAIN ", "\[$D\] OK MENUBACK "
        "\[$D\] OK ENTRYUP2 ", "\[$D\] OK OPEN after the match ", "\[$D\] OK SAME "
        # core story 35: no menu-entry pop-in on the first menu and three returns from a match (a per-frame sampler)
        "\[$D\] OK NOPOPIN menu1 ", "\[$D\] OK NOPOPIN menu2 ", "\[$D\] OK NOPOPIN menu3 ", "\[$D\] OK NOPOPIN menu4 "
        "\[$D\] OK HIDDENFIRST menu2 ", "\[$D\] OK HIDDENFIRST menu3 ", "\[$D\] OK HIDDENFIRST menu4 "
        "\[$D\] OK ENTRYUP3 ", "\[$D\] OK ENTRYUP4 ", "\[$D\] OK ENTRYPOS menu3 ", "\[$D\] OK ENTRYPOS menu4 "
        "\[$D\] OK ENTRYLOOK menu3 ", "\[$D\] OK ENTRYLOOK menu4 "
        "!\[$M\] WARN .*column.*still hidden"
        "\[$M\] CONFIGURE \d+ "
    )
    # Mod Manager v2 story 4: Browse against the live catalog (VM).
    'browse' = $running + @(
        "\[$D\] SCENARIO browse\s*$"
        "\[$D\] END result=PASS"
        "#2|\[$M\] CATALOG refresh job=\d+\s*$"
        "!\[$M\] CATALOG refresh (busy|error)"
        "\[$M\] CATALOG done outcome=ok source=network packages=\d+ index_issued=\S+\s*$"
        "#2|\[$M\] CATALOG done outcome=ok source=network "
        "\[$M\] BUILD $([regex]::Escape($manifest.game.build)) from=(index|manifest)\s*$"
        "\[$M\] BROWSE open shown=([5-9]|\d\d+) total=\d+ state=ok\s*$"
        "!\[$M\] BROWSE open .* state=(?!ok)"
        "!\[$M\] BROWSE pkg nuclearnightmare-community\.base(-installer)? "
        "\[$M\] BROWSE pkg nuclearnightmare-community\.nucleus v=\S+ cat=\S+ scope=\S+ state=installed core=ok\s*$"
        "\[$M\] BROWSE pkg nuclearnightmare-community\.mod-manager v=\S+ cat=\S+ scope=\S+ state=installed core=ok\s*$"
        "\[$M\] BROWSE filter cat=audio show=all "
        "\[$M\] BROWSE filter cat=audio show=installed "
        "\[$M\] BROWSE filter cat=all show=all scope=all for=game q=clock shown=1 ids=nuclearnightmare-community\.hud-clock\s*$"
        "#1|\[$M\] DETAILS nuclearnightmare-community\.hud-clock lines=[1-5]\s*$"
        "\[$D\] OK BWDONE startup ", "\[$D\] OK BWROWS ", "\[$D\] OK BWOPEN ", "\[$D\] OK BWLIST ", "\[$D\] OK BWCAT ", "\[$D\] OK BWSHOW "
        "\[$D\] OK BWRESET ", "\[$D\] OK BWSEARCH ", "\[$D\] OK BWDETAILS ", "\[$D\] OK BWDONE after REFRESH "
        '^\[run\.ps1\] FILES unchanged$'
    )
    'no-core' = @(
        '^\[run\.ps1\] FILES unchanged$'
        "#1|\[$M\] "
        "\[$M\] $K is not installed\. $M will not run\.\s*$"
        "\[$D\] OK NOENTRY "
        "\[$D\] END result=PASS"
    )
    # Story 8: the patterns of the whole log (session 1 and session 2 below are checked on their own part).
    'restart' = @(
        '^\[run\.ps1\] SESSION 2 \(relaunched by the game\)'
        '^\[run\.ps1\] RELAUNCH old=\d+ new=\d+ cmdline=same userdir=yes\s*$'
        "^\[run\.ps1\] MOTW .*/$K/bin/${K}Restart\.exe ZoneId=3\s*$"
        '^\[run\.ps1\] DEFENDER status realtime=True behavior=True '
        '^\[run\.ps1\] DEFENDER detections=0\s*$'
        '^\[run\.ps1\] DEFENDER events=0\s*$'
        '^\[run\.ps1\] DEFENDER codeintegrity-blocks=0\s*$'
        '!^\[run\.ps1\] DEFENDER (detection|event|codeintegrity|error) '
        '^\[run\.ps1\] BUILDSCAN main\.dll no threats found.* package=same\s*$'
        "^\[run\.ps1\] BUILDSCAN bin/${K}Restart\.exe no threats found.* package=same\s*$"
        '!^\[run\.ps1\] BUILDSCAN (missing|unreadable)'
        '^\[run\.ps1\] RUN game exited'
        '^\[run\.ps1\] FILES (unchanged|changed: mods\.txt sha256 [0-9A-F]{64} -> [0-9A-F]{64})$'
    )
    # Mod Manager v2 story 3: the patterns of the whole log (each session below is checked on its own part).
    'apply' = @(
        '^\[run\.ps1\] SESSION 2 \(relaunched by the game\)\s*$'
        '^\[run\.ps1\] SESSION 3 \(relaunched by the runner after kill\)\s*$'
        '^\[run\.ps1\] SESSION 4 \(relaunched by the runner after close\)\s*$'
        '#3|^\[run\.ps1\] SESSION '
        '#1|^\[run\.ps1\] RELAUNCH old=\d+ new=\d+ cmdline=same userdir=yes\s*$'
        '!^\[run\.ps1\] RELAUNCH (old|new) cmdline'
        "^\[run\.ps1\] MOTW .*/$K/bin/${K}Restart\.exe ZoneId=3\s*$"
        '^\[run\.ps1\] DEFENDER status realtime=True behavior=True '
        '^\[run\.ps1\] DEFENDER detections=0\s*$'
        '^\[run\.ps1\] DEFENDER events=0\s*$'
        '^\[run\.ps1\] DEFENDER cfa=\S+'
        '^\[run\.ps1\] DEFENDER cfa-events=0\s*$'
        '^\[run\.ps1\] DEFENDER codeintegrity-blocks=0\s*$'
        '!^\[run\.ps1\] DEFENDER (detection|event|cfa-event|codeintegrity|error) '
        '^\[run\.ps1\] BUILDSCAN main\.dll no threats found.* package=same\s*$'
        "^\[run\.ps1\] BUILDSCAN bin/${K}Restart\.exe no threats found.* package=same\s*$"
        '!^\[run\.ps1\] BUILDSCAN (missing|unreadable)'
        '^\[run\.ps1\] RUN finished\s*$'
        '^\[run\.ps1\] FILES (unchanged|changed: mods\.txt sha256 [0-9A-F]{64} -> [0-9A-F]{64})$'
        "!\[${M}ApplyC\] loaded"
        "!\[$M\] APPLY none"
        "#1|\[$D\] END result="
    )
    'old-core' = @(
        '^\[run\.ps1\] FILES unchanged$'
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
# Each pattern against $set (the whole log, or one session of the restart scenario); $tag names the part in the output.
function Test-Patterns([string[]] $patterns, [string[]] $set, [string] $tag = '') {
    foreach ($pattern in $patterns) {
        if ($pattern.StartsWith('#')) {
            $count, $p = $pattern.Substring(1) -split '\|', 2
            $hits = @($set | Where-Object { $_ -match $p }).Count
            if ($hits -eq [int]$count) { Pass "$tag$pattern (found $hits)" } else { Fail "$tag$pattern (found $hits)" }
        } elseif ($pattern.StartsWith('?!')) {
            if ($set | Where-Object { $_ -match $pattern.Substring(2) }) { Write-Host "warn: $tag$pattern"; $script:warned++ } else { Pass "$tag$pattern" }
        } elseif ($pattern.StartsWith('?')) {
            if ($set | Where-Object { $_ -match $pattern.Substring(1) }) { Pass "$tag$pattern" } else { Write-Host "warn: $tag$pattern"; $script:warned++ }
        } elseif ($pattern.StartsWith('!')) {
            if ($set | Where-Object { $_ -match $pattern.Substring(1) }) { Fail "$tag$pattern" } else { Pass "$tag$pattern" }
        } else {
            if ($set | Where-Object { $_ -match $pattern }) { Pass "$tag$pattern" } else { Fail "$tag$pattern" }
        }
    }
}
Write-Host "--- checks ($Scenario) ---"
Test-Patterns ($always + $expect[$Scenario]) $lines

if ($Scenario -eq 'restart') {
    # Story 8: session 1 runs until the RESTART NOW click, session 2 is the relaunched game.
    $cut = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\[run\.ps1\] SESSION 2 ') { $cut = $i; break } }
    $s1 = if ($cut -gt 0) { @($lines[0..($cut - 1)]) } elseif ($cut -lt 0) { $lines } else { @() }
    $s2 = if ($cut -ge 0 -and $cut + 1 -lt $lines.Count) { @($lines[($cut + 1)..($lines.Count - 1)]) } else { @() }
    $R = [regex]::Escape("${name}Restart")
    Test-Patterns ($running + @(
        "\[$D\] SCENARIO restart\s*$"
        "\[$D\] RESTART session 1\s*$"
        "#1|\[$R\] loaded\s*$"
        "\[$D\] OK RSLOADED1 ", "\[$D\] OK RSROW1 ", "\[$D\] OK RSHIDDEN ", "\[$D\] OK RSTXT0 ", "\[$D\] OK RSOFF ", "\[$D\] OK RSSHOWN "
        "\[$D\] OK RSPLACE ", "\[$D\] OK RSMODULE ", "\[$D\] OK RSMODE ", "\[$D\] OK RSSTART1 ", "\[$D\] OK RSSTART2 ", "\[$D\] OK RSFACTS "
        "\[$D\] CLICK RESTART NOW at "
        "#1|\[$M\] TOGGLE ${R} off\s*$"
        "#1|\[$M\] RESTARTMODE direct\s*$"
        "#1|\[$K\] native: restart: helper started \(mode=direct, pid=\d+\)"
        "!\[$K\] native: restart: not started"
        "#1|\[$M\] RESTART mode=direct pending=1\s*$"
        "!\[$M\] WARN RESTART NOW"
        "!\[$D\] END result="
        "!\[$M\] QUIT pending="
    )) $s1 'session 1: '
    Test-Patterns ($running + @(
        "\[$D\] SCENARIO restart\s*$"
        "\[$D\] RESTART session 2\s*$"
        "!\[$R\] loaded"
        "\[$D\] FACTS mode=direct start1=true start2=nil already started checks=\d+ failures=0\s*$"
        "\[$D\] OK RSFACTS2 ", "\[$D\] OK RSNOTLOADED ", "\[$D\] OK RSROW2 ", "\[$D\] OK RSNOPENDING ", "\[$D\] OK RSTXT2 ", "\[$D\] OK RSSHOWN2 "
        "\[$D\] OK QUITPOINT "
        "#1|\[$M\] TOGGLE ${R} on\s*$"
        "!\[$K\] native: restart: helper started"
        "!\[$M\] RESTART mode="
        "\[$D\] END result=PASS"
        "#1|\[$M\] QUIT pending=1\s*$"
    )) $s2 'session 2: '
    $iend, $iquit = -1, -1
    for ($i = 0; $i -lt $s2.Count; $i++) {
        if ($iend -lt 0 -and $s2[$i] -match "\[$D\] END result=PASS") { $iend = $i }
        if ($iquit -lt 0 -and $s2[$i] -match "\[$M\] QUIT pending=") { $iquit = $i }
    }
    if ($iend -ge 0 -and $iquit -gt $iend) { Pass 'session 2: QUIT GAME clicked after END result=PASS' } else { Fail "session 2: QUIT GAME clicked after END result=PASS (END at line $iend, QUIT at line $iquit)" }
}

if ($Scenario -eq 'apply') {
    # Mod Manager v2 story 3: four sessions, split at the runner's SESSION lines (the whole-log patterns above check
    # that there are three, saying how each session started).
    $cuts = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\[run\.ps1\] SESSION [2-9] ') { $i } })
    $bounds = @(-1) + $cuts + @($lines.Count)
    $part = @(for ($k = 0; $k -lt 4; $k++) {
        $a = if ($k -lt $bounds.Count - 1) { $bounds[$k] + 1 } else { $lines.Count }
        $b = if ($k + 1 -lt $bounds.Count) { $bounds[$k + 1] - 1 } else { -1 }
        , $(if ($b -ge $a) { @($lines[$a..$b]) } else { @() })
    })
    $MA = [regex]::Escape("${name}ApplyA"); $MB = [regex]::Escape("${name}ApplyB"); $MC = [regex]::Escape("${name}ApplyC")
    $lockRx = [regex]::Escape((Get-ApplyLockTarget $name))
    $each = $running + @("\[$D\] SCENARIO apply\s*$", "!\[$MC\] loaded")
    Test-Patterns ($each + @(
        "#1|\[$D\] APPLY session 1\s*$"
        "!\[$MA\] loaded", "!\[$MB\] loaded"
        "#1|\[$M\] APPLY status staged=pending result=none "
        "#1|\[$M\] APPLY start ok\s*$"
        "\[$D\] OK APWAIT1 ", "\[$D\] OK APRESULT1 ", "\[$D\] OK APNOTLOADED1 ", "\[$D\] OK APSHOWN1 "
        "\[$D\] CLICK RESTART NOW at "
        "#1|\[$M\] RESTART mode=direct pending=[1-9]\d*\s*$"
        "!\[$M\] WARN RESTART NOW"
        "!\[$D\] END result="
    )) $part[0] 'session 1: '
    Test-Patterns ($each + @(
        "#1|\[$D\] APPLY session 2\s*$"
        "#1|\[$MA\] loaded\s*$", "!\[$MB\] loaded"
        "#1|\[$M\] APPLY status staged=none result=applied "
        "!\[$M\] APPLY start "
        "#1|\[$M\] APPLY result applied "
        "#1|\[$M\] APPLY ack ok\s*$"
        "\[$D\] OK APLOADED2 ", "\[$D\] OK APRESULT2 ", "\[$D\] OK APACKED2 ", "\[$D\] OK APSTAGED2 ", "\[$D\] OK APSTART2 ", "\[$D\] OK APWAIT2 "
        "\[$D\] KILL "
        "!\[$M\] RESTART mode="
        "!\[$D\] END result="
    )) $part[1] 'session 2: '
    Test-Patterns ($each + @(
        "#1|\[$D\] APPLY session 3\s*$"
        "#1|\[$MA\] loaded\s*$", "#1|\[$MB\] loaded\s*$"
        "#1|\[$M\] APPLY status staged=none result=applied "
        "!\[$M\] APPLY start "
        "\[$D\] OK APLOADED3 ", "\[$D\] OK APRESULT3 ", "\[$D\] OK APSTAGED3 ", "\[$D\] OK APLOCK3 ", "\[$D\] OK APSTART3 ", "\[$D\] OK APWAIT3 "
        "\[$D\] CLOSE "
        "!\[$M\] RESTART mode="
        "!\[$D\] END result="
    )) $part[2] 'session 3: '
    Test-Patterns ($each + @(
        "#1|\[$D\] APPLY session 4\s*$"
        "#1|\[$MA\] loaded\s*$", "#1|\[$MB\] loaded\s*$"
        "#1|\[$M\] APPLY status staged=pending result=failed "
        "#1|\[$M\] APPLY start ok\s*$"
        "#1|\[$M\] APPLY result failed reason=locked path=$lockRx attempts=1\s*$"
        "#1|\[$M\] APPLY ack ok\s*$"
        "\[$D\] OK APRESULT4 ", "\[$D\] OK APSAME4 ", "\[$D\] OK APNOC4 ", "\[$D\] OK APNOTLOADED4 ", "\[$D\] OK APPENDING4 ", "\[$D\] OK APSHOWN4 "
        "\[$D\] END result=PASS"
        "!\[$M\] RESTART mode="
        "!\[$M\] QUIT pending="
    )) $part[3] 'session 4: '
    # The story's gate: a Defender detection or event, a Controlled Folder Access event or a Code Integrity block is
    # evidence, never something to work around.
    $gate = @($lines | Where-Object { $_ -match '^\[run\.ps1\] DEFENDER (detection|event|cfa-event|codeintegrity) ' -or $_ -match '^\[run\.ps1\] DEFENDER (detections|events|cfa-events|codeintegrity-blocks)=[1-9]' })
    if ($gate) {
        Fail "Windows Defender, Controlled Folder Access or Code Integrity reported something: stop the story as blocked with this evidence (never add an exclusion or change the helper to avoid it): $($gate -join ' / ')"
    } else { Pass 'no Defender detection or event, no Controlled Folder Access event, no Code Integrity block' }
}

function IndexOf([string] $p) { for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $p) { return $i } } return -1 }

if ($Scenario -eq 'screen') {
    $ic, $ir = (IndexOf "\[$M\] CONNECT ok "), (IndexOf "\[$M\] READY ")
    if ($ic -ge 0 -and $ir -gt $ic) { Pass 'READY comes after CONNECT ok' } else { Fail "READY comes after CONNECT ok (CONNECT at line $ic, READY at line $ir)" }
    $opens = @($lines | Where-Object { $_ -match "\[$M\] OPEN rows=\d+ total=\d+ lang=" }).Count
    if ($opens -ge 2) { Pass "the window opened twice or more ($opens OPEN lines)" } else { Fail "the window opened twice or more ($opens OPEN lines)" }

    # ---- ROW lines against the matrix
    $rows = @($lines | Where-Object { $_ -match "\[$D\] ROW " } | ForEach-Object {
        if ($_ -match "\[$D\] ROW (.*) \| (.*) \| toggle=(\S+) \| box=(\S+) \| gear=(\S+) \| status=(-?\d+) \| icons=(\S+) \| need=(.*) \| build=(.*?) \| scope=(\S+) \| stip=(.*) \| runs=(.*?)\s*$") {
            [pscustomobject]@{ Name = $Matches[1]; Ver = $Matches[2]; Toggle = $Matches[3]; Box = $Matches[4]; Gear = $Matches[5]; Status = [int]$Matches[6]; Icons = $Matches[7]; Need = $Matches[8]; Build = $Matches[9]
                Scope = $Matches[10]; Stip = $Matches[11]; Runs = $Matches[12] }
        } else { [pscustomobject]@{ Name = "(unparsed) $_"; Status = -1 } }
    })
    function BuildOf($mj) { $parts = @($mj.game.version, $mj.game.build | Where-Object { $_ }); if ($parts) { $parts -join ' ' } else { '-' } }
    function NeedOf($mj) { $dep = @($mj.dependsOn | Where-Object { Test-CoreId $_.id })[0]; if ($dep -and $dep.version) { $dep.version } else { '-' } }
    # Story 12: a manifest's scope as the row shows it (one of the four, else unknown; unknown without a manifest).
    function ScopeOf($mj) { $s = if ($mj) { $mj.scope } else { $null }; if ($s -is [string] -and $s -cin 'host', 'client', 'host-plus', 'both') { $s } else { 'unknown' } }
    function GearOf($mj) { if ($mj.settings -and @($mj.settings.PSObject.Properties).Count -gt 0) { 'lit' } else { 'dim' } }
    $core = $null
    try { $core = Get-Content $CoreManifest -Raw | ConvertFrom-Json } catch { Fail "Nucleus's deployed mod.json can't be read ($CoreManifest)" }
    $long = (Get-Content (Join-Path $PSScriptRoot "test\${name}Long\mod.json") -Raw | ConvertFrom-Json)
    $fixture = (Get-Content (Join-Path $PSScriptRoot "test\${name}Fixture\mod.json") -Raw | ConvertFrom-Json)
    $baseMj = (Get-Content (Join-Path $PSScriptRoot "test\${name}Base\mod.json") -Raw | ConvertFrom-Json)
    $depMj = (Get-Content (Join-Path $PSScriptRoot "test\${name}Dep\mod.json") -Raw | ConvertFrom-Json)
    # Story 12: each scope's words (Scripts/strings.lua, en), as the scope icon's tooltip; Configure's line is 'RUNS ON: ' and the same.
    $scopeWords = @{
        'host'      = "HOST ONLY - ONLY THE HOST NEEDS IT; PLAYERS WHO JOIN DON'T"
        'client'    = 'JUST YOU - WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN'
        'host-plus' = 'HOST, PLAYERS OPTIONAL - THE HOST NEEDS IT; PLAYERS WHO HAVE IT GET MORE'
        'both'      = 'HOST AND PLAYERS - THE HOST AND EVERY PLAYER NEED IT'
        'unknown'   = "UNKNOWN - THIS MOD DOESN'T SAY WHERE IT RUNS"
    }
    function W($n, $ver, $tog, $box, $gear, $need, $build, $status = 0, $icons = '-', $scope = 'unknown') {
        [pscustomobject]@{ Name = $n; Ver = $ver; Toggle = $tog; Box = $box; Gear = $gear; Need = $need; Build = $build; Status = $status; Icons = $icons
            Scope = $scope; Stip = $scopeWords[$scope]; Runs = "RUNS ON: $($scopeWords[$scope])" }
    }
    $want = @(
        (W $CoreName "$($core.version)" 'lock' 'none' $(if ($core) { GearOf $core } else { 'dim' }) $(if ($core) { NeedOf $core } else { '-' }) $(if ($core) { BuildOf $core } else { '-' }) 0 '-' (ScopeOf $core))
        (W $manifest.displayName $manifest.version 'lock' 'none' (GearOf $manifest) (NeedOf $manifest) (BuildOf $manifest) 0 '-' (ScopeOf $manifest))
        (W $baseMj.displayName $baseMj.version 'on' 'live' 'dim' (NeedOf $baseMj) (BuildOf $baseMj) 0 '-' 'host')
        (W $depMj.displayName $depMj.version 'on' 'live' 'dim' '-' (BuildOf $depMj) 0 '-' 'both')
        (W "${name}Bare" '-' 'off' 'live' 'dim' '-' '-')
        (W "${name}Driver" '-' 'on' 'live' 'dim' '-' '-')
        (W "${name}Fixture" $fixture.version 'off' 'live' 'lit' '>=0.1.0' 'V0.0.0 1' 2 'warning,warning' 'unknown')
        (W $long.displayName $long.version 'off' 'live' 'dim' '>=0.2.0' (BuildOf $long) 0 '-' 'host-plus')
        (W "${name}Pak" 'UNMANAGED' 'on' 'fixed' 'dim' '-' '-')
        (W "${name}PakOff" 'UNMANAGED' 'off' 'fixed' 'dim' '-' '-')
    )
    $last = -1
    foreach ($w in $want) {
        $hits = @(for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i].Name -ceq $w.Name) { $i } })
        $label = "ROW $($w.Name) | $($w.Ver) | toggle=$($w.Toggle) | box=$($w.Box) | gear=$($w.Gear) | status=$($w.Status) | icons=$($w.Icons) | need=$($w.Need) | build=$($w.Build) | scope=$($w.Scope) | stip=$($w.Stip) | runs=$($w.Runs)"
        if ($hits.Count -ne 1) { Fail "$label (found $($hits.Count) rows named so)"; continue }
        $r = $rows[$hits[0]]
        $same = $r.Ver -ceq $w.Ver -and $r.Toggle -ceq $w.Toggle -and $r.Box -ceq $w.Box -and $r.Gear -ceq $w.Gear -and $r.Status -eq $w.Status -and $r.Icons -ceq $w.Icons -and $r.Need -ceq $w.Need -and $r.Build -ceq $w.Build
        $same = $same -and $r.Scope -ceq $w.Scope -and $r.Stip -ceq $w.Stip -and $r.Runs -ceq $w.Runs
        if (-not $same) { Fail "$label (got $($r.Ver) | toggle=$($r.Toggle) | box=$($r.Box) | gear=$($r.Gear) | status=$($r.Status) | icons=$($r.Icons) | need=$($r.Need) | build=$($r.Build) | scope=$($r.Scope) | stip=$($r.Stip) | runs=$($r.Runs))" }
        elseif ($hits[0] -le $last) { Fail "$label (out of order: row $($hits[0] + 1))" }
        else { Pass $label }
        $last = [math]::Max($last, $hits[0])
    }
    # ---- STATUS (story 6): the first STATUS line of these rows says none
    foreach ($f in $CoreName, "${name}Base", "${name}Dep", "${name}Bare") {
        $first = @($lines | Where-Object { $_ -match "\[$M\] STATUS $([regex]::Escape($f)) " })[0]
        if ($first -and $first -match "\[$M\] STATUS $([regex]::Escape($f)) none \| \s*$") { Pass "STATUS $f none (first)" } else { Fail "STATUS $f none (first): $first" }
    }
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

    # ---- FIXED: nothing from the Mod Manager while the lock and a pak's disabled box are clicked
    $ib, $ie = (IndexOf "\[$D\] FIXED begin"), (IndexOf "\[$D\] FIXED end")
    if ($ib -ge 0 -and $ie -gt $ib) {
        $between = @($lines[($ib + 1)..($ie - 1)] | Where-Object { $_ -match "\[$M\] " -and $_ -notmatch "\[$M\] WARN hud slow tick " })
        if (-not $between) { Pass 'FIXED the lock and the pak box logged no [ModManager] line' } else { Fail "FIXED the lock and the pak box logged: $($between -join ' / ')" }
    } else { Fail 'FIXED begin/end lines' }

    # ---- TGFIRST before any Configure (story 11): a Configure first may warm core's restart texture and hide the freeze
    $itf, $icf = (IndexOf "\[$D\] OK TGFIRST "), (IndexOf "\[$M\] CONFIGURE ")
    if ($itf -ge 0 -and $icf -gt $itf) { Pass 'TGFIRST came before the first CONFIGURE' } else { Fail "TGFIRST came before the first CONFIGURE (TGFIRST at line $itf, CONFIGURE at line $icf)" }

    # ---- QUIT: QUIT GAME after END result=PASS, then the game closed itself (no crash: the $always patterns)
    $iend, $iquit = (IndexOf "\[$D\] END result=PASS"), (IndexOf "\[$M\] QUIT pending=")
    if ($iend -ge 0 -and $iquit -gt $iend) { Pass 'QUIT GAME clicked after END result=PASS' } else { Fail "QUIT GAME clicked after END result=PASS (END at line $iend, QUIT at line $iquit)" }
}

if ($Scenario -eq 'browse') {
    # ---- BROWSE pkg lines: the run's own model (the last line per id before each point of the log)
    $pkgRx = "\[$M\] BROWSE pkg (\S+) v=(\S+) cat=(\S+) scope=(\S+) state=(\S+) core=(ok|needs)\s*$"
    $filterRx = "\[$M\] BROWSE filter cat=(\S+) show=(\S+) scope=(\S+) for=(\S+) q=(.*) shown=(\d+) ids=(\S+)\s*$"
    $pkgs = @{}
    $nFilters = 0
    $anyPkg = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match $pkgRx) {
            $anyPkg = $true
            $pkgs[$Matches[1]] = [pscustomobject]@{ Id = $Matches[1]; Cats = @($Matches[3] -split ','); Scope = $Matches[4]; State = $Matches[5]; Core = $Matches[6] }
            continue
        }
        if ($l -notmatch $filterRx) { continue }
        $nFilters++
        $f = [pscustomobject]@{ Cat = $Matches[1]; Show = $Matches[2]; Scope = $Matches[3]; For = $Matches[4]; Q = $Matches[5]; Shown = [int]$Matches[6]; Ids = $Matches[7] }
        # The filters recomputed from the pkg lines (the search can't be: names and descriptions aren't logged, so a
        # query's ids must be a subset of the recomputed ones).
        $want = @($pkgs.Values | Where-Object {
            $p = $_
            $keep = switch ($f.Show) { 'all' { $true } 'installed' { $p.State -in 'installed', 'update' } 'not-installed' { $p.State -in 'available', 'conflict' } 'update' { $p.State -eq 'update' } default { $false } }
            if ($keep -and $f.Cat -ne 'all') { $keep = $p.Cats -contains $f.Cat }
            if ($keep -and $f.Scope -ne 'all') { $keep = $p.Scope -eq $f.Scope }
            if ($keep -and $f.For -ne 'all') { $keep = $p.State -ne 'other-build' -and ($f.For -ne 'ready' -or $p.Core -eq 'ok') }
            $keep
        } | ForEach-Object Id | Sort-Object)
        $got = if ($f.Ids -eq '-') { @() } else { @($f.Ids -split ',' | Sort-Object) }
        $label = "BROWSE filter line $($i + 1) (cat=$($f.Cat) show=$($f.Show) scope=$($f.Scope) for=$($f.For) q=$($f.Q))"
        if ($got -contains '...') { Write-Host "warn: $label ids were cut; not recomputed"; $warned++; continue }
        if ($f.Shown -ne $got.Count) { Fail "$label shown=$($f.Shown) but $($got.Count) ids"; continue }
        if ($f.Q -eq '') {
            if (($want -join ',') -ceq ($got -join ',')) { Pass "$label ids equal the recomputation ($($got.Count))" }
            else { Fail "$label ids $($got -join ',') differ from the recomputation $($want -join ',')" }
        } else {
            $extra = @($got | Where-Object { $_ -notin $want })
            if (-not $extra) { Pass "$label ids are within the recomputation (a search narrows it)" } else { Fail "$label ids outside the recomputation: $($extra -join ',')" }
        }
    }
    if ($nFilters -ge 3) { Pass "BROWSE filter lines: $nFilters" } else { Fail "BROWSE filter lines: $nFilters (at least 3: open, CATEGORY, SHOW)" }
    if (-not $anyPkg) { Fail 'no BROWSE pkg line' }
    # ---- the five mods of this build, base and installer absent, each state agreeing with the run's own ROW lines
    $five = 'nucleus', 'mod-manager', 'hud-clock', 'waypoints', 'whistle-mute' | ForEach-Object { "nuclearnightmare-community.$_" }
    $missing = @($five | Where-Object { -not $pkgs.ContainsKey($_) })
    if (-not $missing) { Pass 'BROWSE pkg lines for the five mods of this build' } else { Fail "BROWSE pkg lines missing: $($missing -join ', ')" }
    $rowNames = @($lines | Where-Object { $_ -match "\[$D\] ROW (.*) \| (\S*)\s*$" } | ForEach-Object { if ($_ -match "\[$D\] ROW (.*) \| (\S*)\s*$") { $Matches[1] } })
    if (-not $CatalogIndex) {
        $up = $PSScriptRoot
        while ($up -and -not (Test-Path (Join-Path $up 'catalog\index.json'))) { $up = Split-Path $up }
        if ($up) { $CatalogIndex = Join-Path $up 'catalog\index.json' }
    }
    $display = @{}
    if ($CatalogIndex -and (Test-Path $CatalogIndex)) {
        # a main-window row shows a mod's display name, or its folder name (Nucleus's row): either counts
        foreach ($p in @((Get-Content $CatalogIndex -Raw | ConvertFrom-Json).packages)) { $display[([string]$p.id).ToLowerInvariant()] = @(@($p.displayName, $p.name) | Where-Object { $_ }) }
    }
    if (-not $rowNames) { Fail 'no driver ROW line (the installed mods)' }
    elseif (-not $display.Count) { Write-Host "warn: no catalog index to map ids to names ($CatalogIndex); states not compared with the ROW lines"; $warned++ }
    else {
        foreach ($p in $pkgs.Values) {
            $dname = $display[$p.Id]
            if (-not $dname) { Write-Host "warn: $($p.Id) is not in $CatalogIndex"; $warned++; continue }
            $inst = [bool](@($dname | Where-Object { $rowNames -ccontains $_ }).Count)
            $okState = if ($inst) { $p.State -in 'installed', 'update' } else { $p.State -eq 'available' }
            $label = "STATE $($p.Id) $($p.State): '$($dname -join "' or '")' $(if ($inst) { 'has' } else { 'has no' }) ROW line"
            if ($okState) { Pass $label } else { Fail $label }
        }
    }
    # ---- the clock search: only HUD Clock
    $clock = @($lines | Where-Object { $_ -match "\[$M\] BROWSE filter cat=all show=all scope=all for=game q=clock shown=" })
    if ($clock -and $clock[-1] -match 'shown=1 ids=nuclearnightmare-community\.hud-clock\s*$') { Pass "'clock' leaves only nuclearnightmare-community.hud-clock" }
    else { Fail "'clock' leaves only nuclearnightmare-community.hud-clock: $($clock | Select-Object -Last 1)" }
    # ---- REFRESH reached a second done after the Details window
    $idet, $idone2 = (IndexOf "\[$M\] DETAILS "), -1
    $dones = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "\[$M\] CATALOG done ") { $i } })
    if ($dones.Count -ge 2) { $idone2 = $dones[1] }
    if ($idet -ge 0 -and $idone2 -gt $idet) { Pass 'REFRESH: the second CATALOG done after DETAILS' } else { Fail "REFRESH: the second CATALOG done after DETAILS (DETAILS at line $idet, second done at line $idone2)" }
}

if ($failed) { Write-Host "$failed check(s) failed."; exit 1 }
Write-Host ("All checks passed{0}." -f $(if ($warned) { " ($warned soft check(s) not met)" } else { '' }))
