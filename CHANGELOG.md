# Changelog

All notable changes to the Mod Manager are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- 0.1.1 (story 9): the MOD MANAGER window fits Nucleus 0.12.0's window card. Its title, header and list stack in the card's top-left corner instead of sitting at fixed full-screen offsets, and the list's height leaves room for the title, the header and BACK, so the card is no longer clamped (no `WARN window 'main': its content ... the card is clamped` in the log), the list no longer draws past the card's bottom edge, and the empty band on the card's left side is gone. The Configure window's heading and lines stack in its card's top-left corner the same way. Still needs Nucleus 0.12.0 or newer (`>=0.12.0`).

## [0.1.0] - 2026-11-14

### Added

- 0.1.0 (story 3): MANAGE MODS in the title-screen menu opens a full-screen MOD MANAGER window listing every installed mod (toggle box, name, version, status slot, gear), read-only. The gear opens a Configure window with the mod's version, Nucleus need and game build. Game: Nuclear Nightmare V8.2.3 (build 26601774). UE4SS: v3.0.1-1181-g83330635. Needs Nucleus 0.12.0 or newer (`>=0.12.0`).

### Changed

- Distribution story 13: mod ids go through core's shared normalizer `nucleus.modid` (Nucleus 0.12.0, which also renamed core's id to `nuclearnightmare-community.nucleus`), so the Mod Manager needs Nucleus `>=0.12.0`. The local `Scripts/modid.lua` and its test are gone, and so is the legacy bare `nucleus` alias (`inventory.lua`, `deploy-lib.ps1`). The unit tests load `nucleus.modid` from the Nucleus repo (`test.ps1 -Nucleus`), and `deploy_test.ps1` runs the dev-only `ConvertTo-ModId` over the workspace's shared id cases.
