# Mod Manager

A Nuclear Nightmare mod that adds **MANAGE MODS** to the title-screen menu, between OPTIONS and QUIT. It opens a full-screen **MOD MANAGER** window that lists every installed mod, one row each: `toggle box | name | version | status | gear`. Built on **Nucleus** (core): its menu entry, windows, lists, rows, images, icons and tooltips are core's (`core.ui`, Nucleus 0.8.0). Spec: `_bmad-output/specs/spec-mod-manager-v1/` in the workspace (this is story 3).

- Story 3 is **read-only**: nothing is written anywhere. The toggle box shows on, off, or a lock for Nucleus and the Mod Manager (they can't be turned off), and does nothing yet; the status slot stays empty; the gear opens a Configure window with the mod's details, which only closes. Turning mods on and off (story 6), the status icons (story 6) and settings (story 8) come later.
- Scope `client`: it reads the local game folder only, sends nothing over the network and reads nothing from other players.
- Version 0.1.0, built for game V8.2.3 (build 26601774) and UE4SS `v3.0.1-1181-g83330635`. Needs Nucleus `>=0.12.0`.
- Id `nuclearnightmare-community.mod-manager`; folder, `mods.txt` line and log tag `ModManager` (UE4SS removes spaces from `mods.txt` lines, so the folder can't be `Mod Manager`); shown as "Mod Manager" through `displayName`.
- License: MIT (`LICENSE`); changes: `CHANGELOG.md`; `build.ps1` stages the release package for the workspace's `tools/release/release.ps1`.

## Install

Nucleus 0.12.0 or newer must be installed in the dev copy first (its own `deploy.ps1`). Then, from this repo (from a worktree, pass the main checkout's instance path):

```powershell
./deploy.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774
./deploy.ps1 -Instance C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774 -Remove
```

`deploy.ps1` refuses, with one line and exit code 1, when Nucleus isn't installed in the copy, is disabled in `mods.txt`, or its installed `mod.json` version doesn't satisfy `dependsOn` (`>=0.12.0`: a minimum, and not below the installed core's `compat.floor`). Core's `dependsOn` entry is the one whose id names Nucleus: `nuclearnightmare-community.nucleus`, compared through the id normalizer (any case, or the `github.com/` long form). Otherwise it copies `mod.json` and `Scripts/` to `Mods/ModManager/` and puts `ModManager : 1` in `mods.txt` right below Nucleus's line and above `Keybinds : 1`. It never bundles core's files. `-Remove` takes all of it out again; `mods.txt` keeps its exact bytes otherwise.

Launch only with the workspace's `tools/launch.ps1 -Instance <copy>`.

## What it shows

- **Rows:** one per folder `ue4ss/Mods/<F>` whose name is 1-64 of `A-Z a-z 0-9 _ -`, except UE4SS's own mods (`BPML_GenericFunctions`, `BPModLoaderMod`, `CheatManagerEnablerMod`, `ConsoleCommandsMod`, `ConsoleEnablerMod`, `Keybinds`, `LineTraceMod`, `SplitScreenMod`) and `shared`. `<F>_P.pak[.disabled]` (`_P` in any case, or no `_P` at all) in `Content/Paks`, and `<F>.pak[.disabled]` in `Content/Paks/LogicMods` or one of its subfolders (BPModLoaderMod loads those too; a subfolder whose name isn't a mod name is skipped with one WARN), belong to folder `<F>`'s row; a pak with no folder is its own row (named after the file without `_P`, version `UNMANAGED`), and a pak named like a UE4SS built-in or `shared` is never a row. The game's own paks (`NuclearNightmare-Windows.*`, `pakchunk*`) and `.utoc`/`.ucas` files are never rows.
- **Order:** Nucleus, the Mod Manager, then the rest by shown name, ignoring case. At most 200 rows (one `WARN` when there are more).
- **Toggle box:** on when the folder has `enabled.txt` or a `mods.txt` line whose value starts with `1` (UE4SS's own reading: a line with `;` or of 4 characters or fewer is skipped, spaces are removed); a pak-only row is on when one of its paks is `.pak`. A lock (ALWAYS ON) for Nucleus and the Mod Manager. An image, so a click does nothing.
- **Name:** `displayName`, else `name`, else the folder name. A `displayName` that isn't 1-64 characters, with no control character and no leading or trailing space, is ignored (one `WARN` per folder per session). Cut with `…` at its column's edge.
- **Version:** `version`, `-` when missing or unreadable, `UNMANAGED` for a pak-only row. Values are capped at 64 characters (a bound on untrusted input, not a width).
- **Gear:** lit when `mod.json` declares a non-empty `settings` object, dimmed otherwise; either way it opens **Configure**: the shown name, `VERSION`, `NUCLEUS` (the `dependsOn` version for Nucleus, matched through the mod id normalizer, `-` when none) and `GAME BUILD` (`game.version` and `game.build`), with core's Close.
- `mod.json` is read with a strict bounded JSON reader (`Scripts/json.lua`: at most 65,536 bytes, depth 16, 4,096 values, 1,024-byte strings; never `load` on data). A broken `mod.json` gives one `WARN` per folder per session and a row of `-`.
- The window's layout: core's `screen` host, a title, a one-row header list and the list of rows, both 360 layout units in from each side. The game scales UI by the shortest side (1080 = 1.0), so 1280x720 and 1920x1080 look the same, and a wider screen only widens the columns.
- **Strings:** every string the player sees is in `Scripts/strings.lua`, per language (English required, upper case), picked by the game's language (`GetCurrentLanguage`): the exact tag, then the prefix before `-`, then English.

Log lines (`UE4SS.log`): `[ModManager] CONNECT ok ...`, `READY entry=manage need=>=0.12.0`, `OPEN rows=<n> total=<n> lang=<tag> us=<scan and build>` at each open, `MOD <n> <folder> | <name> | <version> | <state> | settings=<yes|no> | need=<..> | build=<..>` once per mod (again when it changes), `CONFIGURE <n> <folder>` when a gear opens Configure, and one `WARN` per problem per session.

## How it works

- `Scripts/main.lua`: the dependent bootstrap from core's `api-contract.md`, then `connect{ mod = "ModManager", need = ">=0.12.0" }`. In `onReady` it adds the menu entry (`core.ui.menu.entry`, style `options`). A click scans and opens (or refreshes) the window; every callback runs under `pcall`, and a fault is logged once with context.
- `Scripts/inventory.lua`: the scan, a pure function over a file system it is given (`listDir`, `readFile`, `exists`), so the unit tests run it offline; the game adapter lists folders and paks through `IterateGameDirectories()` and reads `mods.txt` and `mod.json` with `io.open(path, "rb")`. No shell, no write, no path built from a name that hasn't passed the name rule.
- Mod ids go through core's normalizer `nucleus.modid` (Nucleus 0.12.0, distribution story 13; `_bmad-output/specs/spec-distribution-v0/mod-ids.md`), loaded with `require` like any pure core module. The Mod Manager ships no copy of it, and the bare `nucleus` is no longer read as core's id.
- `Scripts/screen.lua`: the windows. Elements are made once per session and reused at every open (index-based ids `r<n>.on|name|ver|st|cfg`); rows past the current count are hidden, never removed.
- If core is missing, disabled, failed or older than 0.12.0, the log has exactly one `[ModManager]` line naming the cause and the mod does nothing else.

## Tests

### Unit tests (no game)

```powershell
./test.ps1                      # or: ./check.ps1 -Scenario unit
```

Lua (any Lua 5.3/5.4 on PATH; MiKTeX's `texlua.exe` is one): `json_test` (the reader, its caps and refusals), `strings_test` (the tables, the picker), `inventory_test` (every row of story 3's I/O matrix against a fake file system, `mods.txt` the way UE4SS reads it, the adapter over a stubbed `IterateGameDirectories`), `screen_test` (the windows against a fake `core.ui`: ids, icons, dimmed, tooltips, overflow, the header, reuse, the 200 rows), `main_test` (the bootstrap, the entry, the click, warnings and faults once, nothing written), `driver_test` (the driver loads in every scenario). PowerShell: `deploy_test` (version needs, core ids, `mods.txt` editing, `deploy.ps1` against a fake instance, `build.ps1`'s package), `check_test` (each scenario's checks against synthetic logs), `run_guard_test` (the workspace's run guard).

### Scenarios (in game, unattended)

```powershell
$copy = 'C:\...\nuclear-nightmare\game-instances\v8.2.3-build26601774'
./run.ps1 -Instance $copy -Scenario screen              # in the VM (the default -Target vm)
./run.ps1 -Instance $copy -Scenario screen -Target host # on the host
./check.ps1 -Log <workspace>\dumps\v8.2.3-build26601774\mod-manager\screen.vm.log -Scenario screen -Target vm
```

`run.ps1` deploys with the driver and the fixtures, launches, serves the driver's requests (Enter at the press-any-key screen, real clicks, the wheel, screenshots in the VM), waits for the driver's `END` line (or a crash or the time limit), closes the game, appends `[run.ps1] FILES unchanged` (or what changed: `mods.txt`'s SHA-256 and the file names under `Content/Paks` and `LogicMods`, after the deploy and after the game closed) to the kept log `dumps/<copy>/mod-manager/<scenario>[.vm].log`, and runs `check.ps1` on it. In the VM it uses the workspace's `tools/vm/vm-sp.ps1` (`-BasePaks` for the fixture paks, `-FileState` for the file check) and Nucleus from `mods/Nucleus/build/package`; take `dumps\vm.lock` around it.

| Scenario | What it proves |
|---|---|
| `screen` | MANAGE MODS between OPTIONS and QUIT in the options style; one click opens MOD MANAGER; the rows of Nucleus, Mod Manager, ModManagerBare, ModManagerDriver, ModManagerFixture, ModManagerLong…, ModManagerPak and ModManagerPakOff with the matrix's values (`ROW` lines; need and build read from each row's Configure window); no built-in, `shared` or base-pak row; every status slot empty; the long name cut with `…` inside its column and the header's NAME aligned with the rows' names (`MEASURE`); clicks on a toggle box and Nucleus's lock change and log nothing (`INERT`); Configure on top, a dimmed gear opens it too, the main window's Close blocked under it; the closes; Tower Island and back, then the entry again lists the same rows (DW-59); no file changed |
| `no-core` | `deploy.ps1` refuses in one line; forced, exactly one `[ModManager]` line ("Nucleus is not installed. ModManager will not run.") and no entry in the menu |
| `old-core` | `deploy.ps1` refuses naming both versions; forced (core's `mod.json` set to 0.1.0, which the driver publishes as core's runtime version), exactly one `[ModManager]` line and no entry |

`no-core` and `old-core` exist but aren't part of routine checks: the bootstrap is Clock's, and `main_test` covers it.

Fixtures (`deploy.ps1 -Test`, never shipped): `Mods/ModManagerFixture` (mod.json 9.9.9, `dependsOn` `nuclearnightmare-community.nucleus` `>=0.1.0`, game V0.0.0/1, one setting; `ModManagerFixture : 0`), `Mods/ModManagerBare` (an empty `Scripts/`, no line), `Mods/ModManagerLong` (a 64-character `displayName` starting `ModManagerLong`, `dependsOn` bare `nucleus` `>=0.2.0`, no line), and `Content/Paks/ModManagerPak_P.pak` and `ModManagerPakOff_P.pak.disabled` (`build.ps1 -Fixtures`: one text file of ours, nothing the game loads). The driver (`test/ModManagerDriver/`) is plain UE4SS Lua; it can't reach the Mod Manager's Lua state, so it judges what is on screen, finding core's widgets by their tags (`nucleus:ModManager:<id>`).

## Layout

| Path | What |
|---|---|
| `mod.json` | The manifest (id, name, displayName, version, scope, game build, UE4SS, `dependsOn`) |
| `Scripts/*.lua` | The mod (what ships): `main`, `inventory`, `json`, `strings`, `screen` |
| `deploy.ps1`, `deploy-lib.ps1` | Install/remove; the lib holds the version-need check, the core id rule and `mods.txt` editing |
| `build.ps1` | The release package (`-Fixtures`: the fixture pak) |
| `check.ps1`, `run.ps1`, `test.ps1` | Judge a log, run a scenario, run the unit tests |
| `test/ModManagerDriver/`, `test/ModManagerFixture/`, `test/ModManagerLong/` | The driver and the fixtures (never shipped) |
| `test/unit/` | Unit tests (`fakeui.lua`: a fake `core.ui`) |
