-- ModManagerApplyC: a fixture of the Mod Manager's apply scenario (Mod Manager v2 story 3). Never deployed as a mod and
-- never shipped: the runner stages it as plan C in session 3 ("stage C"): this mod's files, then an overwrite of a
-- file of ModManagerApplyA that the runner holds locked, then "ModManagerApplyC on". The locked file fails the apply,
-- which puts every earlier step back, so this mod must never load.
print("[ModManagerApplyC] loaded\n")
ModRef:SetSharedVariable("modmanagerapplyc.loaded", true)
