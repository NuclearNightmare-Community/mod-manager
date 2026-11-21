-- ModManagerApplyA: a fixture of the Mod Manager's apply scenario (Mod Manager v2 story 3). Never deployed as a mod and
-- never shipped: deploy.ps1 -Test -Scenario apply stages it as plan A (its mod.json and this file, then "ModManagerApplyA
-- on" in mods.txt), which core's relaunch helper installs after RESTART NOW. Plan C later tries to overwrite this file
-- while the runner holds it locked; the scenario checks it stays byte-identical. It only says that it loaded.
print("[ModManagerApplyA] loaded\n")
ModRef:SetSharedVariable("modmanagerapplya.loaded", true)
