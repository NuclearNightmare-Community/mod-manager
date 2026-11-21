# Changelog

All notable changes to the Mod Manager are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.8.0] - 2026-11-21

### Added

- UPDATE (Mod Manager v2 story 6). Browse rows with an update (`UPDATE AVAILABLE`), and installed mods whose version was revoked when the catalog offers another good version, get an **UPDATE** button where INSTALL sits, and so does their DETAILS window. It works like INSTALL: the confirm window reads `UPDATE <NAME> <FROM> → <TO>?` with ALSO INSTALLS and DOWNLOAD, its button UPDATE; the result reads `<NAME> UPDATES WHEN THE GAME RESTARTS`, `UPDATE REFUSED (<outcome>)` or `UPDATE FAILED`. Nucleus and the Mod Manager update like any mod. Going down a version is offered only away from a revoked version (Nucleus checks that again against its own verified list).
- The MOD MANAGER window shows `<installed> → <offered>` in the version column of a mod with an update, and one notice line under the title, `<n> REVOKED` and/or `<m> UPDATES AVAILABLE`, with **REVIEW** (the revoked window) and **UPDATES** (Browse showing UPDATE AVAILABLE).
- Revocations are flagged, never acted on. An installed version the verified revoked list names (same id and version, and the revoked SHA-256 is the catalog's for that version, or the catalog no longer lists that version; either action) gets a red badge (Nucleus's warning icon tinted red, tooltip `REVOKED: <reason>`) on its main-window row, reads `REVOKED` in Browse, and a notice shows on the title screen (top right): `<NAME> <V> WAS REVOKED` or `<n> INSTALLED MODS WERE REVOKED`, with **REVIEW**. It shows at every launch until the mod is updated, uninstalled, or a fix is staged; there is no "seen" and no timer.
- The **REVOKED MODS** window: each revoked mod with its version and reason (at most 120 characters), **UPDATE TO <v>** (the newest good version for this build, newer or older; none when there is none) and **UNINSTALL**; BACK is LATER and changes nothing. Keys and a gamepad reach every button.
- UNINSTALL (story 7, merged into 6). In DETAILS of an installed mod (not Nucleus or the Mod Manager) and in the revoked window. Refused without a confirm while an installed mod, or one staged this session, needs it: `CAN'T UNINSTALL <NAME>: NEEDED BY <A>, <B>` (at most 4 names, then `AND <n> MORE`). Otherwise the confirm `UNINSTALL <NAME> <V>?`, `REMOVES ITS FILES AND ITS MODS.TXT LINE`; confirming hands the id and version to Nucleus (`core.catalog.unstage`), which stages the removal of exactly that version's files (a file the player changed is kept) and of its `mods.txt` line. Then `<NAME> IS REMOVED WHEN THE GAME RESTARTS`, RESTART NOW, and the row reads `PENDING RESTART`; otherwise `UNINSTALL REFUSED (<outcome>)` or `UNINSTALL FAILED`.
- `Scripts/catalog.lua`: `revokedMatch`, `revokedInstalled`, `dependents`, `action`, `canUninstall`; rows gain `revoked`. Log lines `UPDATE ask|refuse|cancel|stage|done|message`, `REVOKED <id> v=<v> action=<a> fix=<v|none>`, `NOTICE shown n=<n>` / `NOTICE removed`, `REVIEW open n=<n>` / `REVIEW closed (<reason>)`, `UNINSTALL ask <id>|refuse <id> needed-by=<ids>|cancel|stage job=<n>|<reason>|done outcome=<o> txn=<t> files=<n> kept=<n>|message`.

### Changed

- Needs Nucleus 0.27.0 or newer (`>=0.27.0`, was `>=0.26.0`), which stages removals (`core.catalog.unstage`).
- The main window's status slot has four icons (build, dependency, restart, revoked).

## [0.7.0] - 2026-11-21

### Added

- INSTALL (Mod Manager v2 story 5). Browse's rows of mods that aren't installed get an **INSTALL** button (beside the description), and so does their DETAILS window. INSTALL works out everything needed: the mod's version for this build and every dependency that is missing or too old (checked recursively, dependencies first, at most 16), and asks in one window: `INSTALL <NAME> <VERSION>?`, `ALSO INSTALLS:` (`<NAME> <VERSION> (NEW)` or `(UPDATE FROM <v>)`, at most 8 lines, then `AND <n> MORE`) and `DOWNLOAD <size>`. Confirming hands the list to Nucleus (`core.catalog.stage`), which downloads, verifies and opens each mod and stages its files; the Mod Manager polls it from the game thread, shows `DOWNLOADING <NAME>...`, then starts Nucleus's helper, marks the rows `PENDING RESTART` and shows `<NAME> INSTALLS WHEN THE GAME RESTARTS` with QUIT GAME and RESTART NOW: the mod is put in place when the game closes. A refusal changes nothing and says why (`INSTALL REFUSED (<outcome>)`, `INSTALL FAILED`, `CATALOG BUSY`, `CAN'T INSTALL: <NAME> NEEDS <DEP> <need>`, `CAN'T INSTALL <NAME> (<REASON>)`). A second install before the restart joins the same change.
- `Scripts/catalog.lua` `installSet` and `sizeText`; log lines `INSTALL ask|refuse|cancel|stage|done|message` and `APPLY start` after an install; the `install` test scenario (VM, the live catalog, two sessions: install HUD Clock, RESTART NOW, HUD Clock runs).

### Changed

- Needs Nucleus 0.26.0 or newer (`>=0.26.0`, was `>=0.25.0`), which stages installs (`core.catalog.stage`). Without it Browse has no INSTALL (one `WARN`).
- The `mod.json` description says the catalog's mods can be installed too.

## [0.6.0] - 2026-11-21

### Added

- Browse (Mod Manager v2 story 4). A **BROWSE** button at the top right of the MOD MANAGER window opens **BROWSE MODS**: every mod the verified community catalog offers for this game build. Nucleus's `core.catalog` fetches and verifies the catalog (the Mod Manager reads no catalog file and fetches nothing itself): once when the game starts and again on **REFRESH**, polled from the game thread every 250 ms, one refresh at a time (`CATALOG BUSY` otherwise; never on a timer).
- Search (a text box: every word must be in the name or the description) and four filters: CATEGORY (the 14 catalog categories), SHOW (all, installed, not installed, update available), SCOPE (the four scopes) and FOR (this game, ready to run with the installed Nucleus, all builds). All reset when Browse opens. Each filter is its own row, so keys and a gamepad reach every one; search needs a keyboard.
- Each mod: name, primary category, the version offered for this build (the newest one of this build that isn't revoked and whose dependencies can be met), the scope icon, its state (`INSTALLED`, `UPDATE AVAILABLE`, `NOT INSTALLED`, `FOLDER IN USE`, `OTHER GAME BUILD`), a warning when it needs a newer Nucleus, a DETAILS button, and its description. The catalog's age (`CATALOG UPDATED ...`, `REVOCATIONS CHECKED ...`), `OFFLINE: SAVED CATALOG` when the catalog came from the last verified copy, and `<n> OF <m> MODS` (at most 120 shown).
- DETAILS: the description, categories, version, RUNS ON, the game it is for, what it needs (met or not), whether it is installed, publisher and license.
- Offline and refusals: no endpoint reachable and no saved copy shows `CATALOG UNAVAILABLE. CHECK YOUR CONNECTION AND PRESS REFRESH.`; a catalog the verifier rejects shows only `CATALOG REFUSED (<outcome>)`, never the saved copy; a catalog schema too new shows `CATALOG NEEDS A NEWER MOD MANAGER`.
- Log lines `CATALOG refresh`, `CATALOG done`, `CATALOG message`, `BUILD`, `BROWSE open`, `BROWSE pkg`, `BROWSE filter`, `DETAILS`; the `browse` test scenario (VM, the live catalog).
- Nothing is installed, downloaded or updated from Browse yet.

### Changed

- Needs Nucleus 0.25.0 or newer (`>=0.25.0`, was `>=0.24.0`), which has the text box (`core.ui.textbox`); `core.catalog` (Nucleus 0.23.0) shows BROWSE, and without it the button is absent (one `WARN`).
- The `mod.json` description mentions browsing instead of "coming".

## [0.5.0] - 2026-11-21

### Added

- Changes staged until the game exits (Mod Manager v2 story 3). Installs, updates and removals from the catalog (coming next) can't replace the files of a running game, so they are staged and Nucleus's helper applies them once the game has closed, however it closes. At start the Mod Manager reads the staged change's state (`core.apply.status`, `APPLY status ...`) and, when a change is staged and no helper waits for it yet, starts the helper (`APPLY start ok`). A staged change counts as one pending change: the banner, QUIT GAME and RESTART NOW show for it, and RESTART NOW applies it before the game starts again. The first time the window opens after a change was applied or not, its message line says so once (`THE STAGED CHANGE WAS APPLIED.`, `A STAGED CHANGE COULD NOT BE APPLIED (<file>). IT IS TRIED AGAIN AT THE NEXT RESTART.` or `A STAGED CHANGE COULD NOT BE APPLIED AND WAS DROPPED.`) and the result is acknowledged (`APPLY result ...`, `APPLY ack ...`). The Mod Manager itself stages nothing yet.
- The `apply` test scenario (VM only): four game sessions ending by RESTART NOW, a kill and a window close, and a change rolled back because one of its files was held open.

### Changed

- Needs Nucleus 0.24.0 or newer (`>=0.24.0`, was `>=0.21.0`), which has `core.apply`.

## [0.4.0] - 2026-11-20

- Catalog listing: the display name "Mod Manager", a description and categories.

### Added

- Where a mod runs (story 12). A new column between the version and the status icons shows one icon per mod from its `mod.json` `scope`: a house for `host` (HOST ONLY), a person for `client` (JUST YOU), a house with a small person for `host-plus` (HOST, PLAYERS OPTIONAL), a house and a person with a plus for `both` (HOST AND PLAYERS), and a question mark for anything else (UNKNOWN: no scope, the retired `all`, a wrong case, a Blueprint-only mod). The icon's tooltip says what it means, and Configure repeats it as a `RUNS ON:` line, so keyboard and gamepad players get the words through the gear. The icon only informs; nothing is turned off because of it.

### Changed

- Needs Nucleus 0.21.0 or newer (`>=0.21.0`, was `>=0.20.0`), which has the five scope icons.
- Configure's settings list is 46 units shorter (its reserve is 586 units, was 540) to make room for the RUNS ON line.

## [0.3.0] - 2026-11-20

### Added

- RESTART NOW (story 8). While changes are pending and the game can be started again the way it was launched, a RESTART NOW button shows right above QUIT GAME. It closes the game and starts it again: through Steam on a normal Steam install (with your Steam launch options), or the same exe with the same command line on a dev copy. Nucleus's small relaunch helper does the waiting and the starting; the Mod Manager asks `core.restart` once per session which way applies (`RESTARTMODE`), and a click starts the helper and then quits like QUIT GAME (`RESTART mode=<m> pending=<n>`). If the helper can't start, the game keeps running and the window says `CAN'T RESTART: USE QUIT GAME AND START THE GAME AGAIN.` (one `WARN`). A game started some other way shows QUIT GAME only. Pending Blueprint (pak) changes are still not applied by a restart. Needs Nucleus 0.20.0 or newer (`>=0.20.0`).

## [0.2.1] - 2026-11-17

### Fixed

- 0.2.1 (story 11): the game no longer freezes on the first mod turned on or off in a session. A row's checkbox, a Configure control and TURN OFF used to save and redraw the window inside Nucleus's click hook, where the first restart icon of a session loads its texture and stalls the engine. That work now runs on the game thread about 10 ms later, after the hook has returned, and checks first that the same row or setting is still under the click (if the list changed in between, nothing is written and the box shows its row's real state). BACK on the confirm between the click and that work still cancels. A TURN OFF that fails sets the box back on with `COULD NOT SAVE THE CHANGE`, and a setting that fails before it is saved goes back with `NOT SAVED (error)`. Still needs Nucleus 0.12.0 or newer (`>=0.12.0`).

## [0.2.0] - 2026-11-17

### Added

- 0.2.0 (story 6): turning mods on and off, warnings, Configure and Quit. Still needs Nucleus 0.12.0 or newer (`>=0.12.0`).
  - The row's toggle is Nucleus's checkbox. A click writes `mods.txt` at once (atomically, through `.mm-tmp` and `.mm-bak`; only the value after the line's last `:` changes, every other byte stays; with no line, `<Folder> : 1` goes above `Keybinds`), and turning off renames a folder's `enabled.txt` to `enabled.txt.disabled`. The change applies at the next start; the row shows it as pending. A failed write puts everything back, sets the box back and shows `COULD NOT SAVE THE CHANGE`.
  - Turning off a mod that other enabled mods need asks first (`TURN OFF <name>? <names> NEED IT.`); BACK cancels and writes nothing. Nothing is ever turned off by itself.
  - Nucleus and the Mod Manager keep the lock. Blueprint (pak) mods show their state in a disabled box: renaming a mounted pak crashes the game, so pak toggles wait for the installer or the relaunch helper.
  - The status slot shows up to three icons with tooltips: made for another game build (the running version from the title-screen footer, the build from Steam's appmanifest when there is one), dependency problems (not installed, turned off, too old), and a restart pending.
  - One alert when Nucleus itself was made for another game, once per Nucleus version and game.
  - Configure lists the status problems and the mod's settings from `core.settings` with checkboxes, choices, sliders and read-only values (`SET BY <SOURCE>`); a change is saved through `core.settings.setFor`, a refusal shows `NOT SAVED (<code>)`.
  - While changes are pending, `CHANGES APPLY AFTER A RESTART.` and a `QUIT GAME` button.
  - The Mod Manager's own state: `Mods/ModManager/state.json` (the folders turned off here, the alerts already shown), for the installer to honour later.
  - New log lines `STATUS`, `TOGGLE`, `CONFIRM`, `ALERT`, `SET`, `QUIT`, `RESTORED`; `OPEN` names the running game and build.
  - The main list is 100 units shorter (about 10 rows before it scrolls), leaving room for QUIT GAME and the banner on the window's card.

### Fixed

- 0.1.1 (story 9): the MOD MANAGER window fits Nucleus 0.12.0's window card. Its title, header and list stack in the card's top-left corner instead of sitting at fixed full-screen offsets, and the list's height leaves room for the title, the header and BACK, so the card is no longer clamped (no `WARN window 'main': its content ... the card is clamped` in the log), the list no longer draws past the card's bottom edge, and the empty band on the card's left side is gone. The Configure window's heading and lines stack in its card's top-left corner the same way. Still needs Nucleus 0.12.0 or newer (`>=0.12.0`).

## [0.1.0] - 2026-11-14

### Added

- 0.1.0 (story 3): MANAGE MODS in the title-screen menu opens a full-screen MOD MANAGER window listing every installed mod (toggle box, name, version, status slot, gear), read-only. The gear opens a Configure window with the mod's version, Nucleus need and game build. Game: Nuclear Nightmare V8.2.3 (build 26601774). UE4SS: v3.0.1-1181-g83330635. Needs Nucleus 0.12.0 or newer (`>=0.12.0`).

### Changed

- Distribution story 13: mod ids go through core's shared normalizer `nucleus.modid` (Nucleus 0.12.0, which also renamed core's id to `nuclearnightmare-community.nucleus`), so the Mod Manager needs Nucleus `>=0.12.0`. The local `Scripts/modid.lua` and its test are gone, and so is the legacy bare `nucleus` alias (`inventory.lua`, `deploy-lib.ps1`). The unit tests load `nucleus.modid` from the Nucleus repo (`test.ps1 -Nucleus`), and `deploy_test.ps1` runs the dev-only `ConvertTo-ModId` over the workspace's shared id cases.
