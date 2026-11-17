# Changelog

All notable changes to the Mod Manager are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
