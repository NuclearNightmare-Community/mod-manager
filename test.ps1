<#
.SYNOPSIS
  Runs the Mod Manager's unit tests, no game needed: the Lua tests (the JSON reader, the id normalizer, the strings,
  the inventory against a fake file system, story 6's pure modules (mods.txt, atomic writes, state, status), v2 story 4's catalog
  model against fixture payloads, the screen and the Browse window against a fake core.ui, main.lua's bootstrap and glue against a
  fake core, the driver's load test) and the PowerShell tests (deploy-lib.ps1 and deploy.ps1 against a fake instance,
  run.ps1's run guard, check.ps1 against synthetic logs). check.ps1 -Scenario unit runs this too.
  Lua: the first of lua, lua5.4, lua54, lua5.3, texlua (MiKTeX's texlua.exe is Lua 5.3) found on PATH; -Lua picks one.
  The Lua tests load core's pure nucleus.modid from the Nucleus repo: <Nucleus>/lua/pkg goes on the Lua path (LUA_PATH,
  read by test/unit/nucleus_pkg.lua). -Nucleus names that repo; else $env:NN_NUCLEUS (set by the ci workflow to its
  Nucleus checkout); else the Nucleus checkout beside this repo's main checkout (the sibling of the folder that holds
  git's common dir, so a worktree finds mods/Nucleus too).
.EXAMPLE
  ./test.ps1
  ./test.ps1 -Only lua
#>
param([string] $Lua, [ValidateSet('all', 'lua', 'ps')] [string] $Only = 'all', [string] $Nucleus)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $Nucleus -and $env:NN_NUCLEUS) { $Nucleus = $env:NN_NUCLEUS }
if (-not $Nucleus) {
    $common = git -C $here rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($common) { $Nucleus = Join-Path (Split-Path (Split-Path $common)) 'Nucleus' }
}
if (-not $Lua) { $Lua = @('lua', 'lua5.4', 'lua54', 'lua5.3', 'texlua') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1 }
$failed = @()
Push-Location $here
try {
    if ($Only -in 'all', 'lua') {
        $pkg = if ($Nucleus) { Join-Path $Nucleus 'lua/pkg' }
        if (-not $Lua) { Write-Host 'FAIL: no Lua 5.3/5.4 interpreter on PATH (lua, texlua, ...); pass -Lua'; $failed += 'lua' }
        elseif (-not $pkg -or -not (Test-Path -LiteralPath (Join-Path $pkg 'modid.lua'))) {
            Write-Host "FAIL: core's lua/pkg/modid.lua not found (Nucleus '$Nucleus'); pass -Nucleus <Nucleus repo>"; $failed += 'lua'
        } else {
            $oldLuaPath = $env:LUA_PATH
            $env:LUA_PATH = ($pkg -replace '\\', '/') + '/?.lua;;'
            foreach ($t in 'json_test', 'strings_test', 'inventory_test', 'modstxt_test', 'files_test', 'state_test', 'status_test', 'catalog_test', 'screen_test', 'browse_test', 'main_test', 'driver_test') {
                # texlua prints a MiKTeX update reminder on stderr; only the test's own output matters.
                $out = & $Lua "test/unit/$t.lua" 2>$null
                $code = $LASTEXITCODE
                $out | ForEach-Object { Write-Host $_ }
                if ($code -ne 0) { $failed += $t }
            }
            $env:LUA_PATH = $oldLuaPath
        }
    }
    if ($Only -in 'all', 'ps') {
        foreach ($t in 'deploy_test', 'check_test', 'run_guard_test') {
            & pwsh -NoProfile -NonInteractive -File "test/unit/$t.ps1"
            if ($LASTEXITCODE -ne 0) { $failed += $t }
        }
    }
} finally { Pop-Location }
if ($failed) { Write-Host "Unit tests failed: $($failed -join ', ')"; exit 1 }
Write-Host 'All unit tests passed.'
