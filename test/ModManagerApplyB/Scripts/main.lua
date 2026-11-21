-- ModManagerApplyB: a fixture of the Mod Manager's apply scenario (Mod Manager v2 story 3). Never deployed as a mod and
-- never shipped: the runner stages it as plan B in session 2 ("stage B"), and core's helper installs it after the game
-- is killed. It only says that it loaded.
print("[ModManagerApplyB] loaded\n")
ModRef:SetSharedVariable("modmanagerapplyb.loaded", true)
