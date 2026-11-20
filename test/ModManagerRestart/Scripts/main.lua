-- ModManagerRestart: the fixture of the Mod Manager's restart scenario (story 8). Installed only by deploy.ps1 -Test
-- -Scenario restart, never shipped. It only says that it loaded: the scenario turns it off in the Mod Manager, clicks
-- RESTART NOW, and checks that the relaunched game doesn't load it (no log line, no shared variable).
print("[ModManagerRestart] loaded\n")
ModRef:SetSharedVariable("modmanagerrestart.loaded", true)
