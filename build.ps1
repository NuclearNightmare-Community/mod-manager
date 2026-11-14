<#
.SYNOPSIS
  Stages the Mod Manager as a release package: build/package/Mods/<name>/{mod.json, Scripts/}, <name> = mod.json
  "name". -Fixtures instead builds the screen scenario's fixture pak.
.DESCRIPTION
  Writes only build/ (ignored by git). The package, deleted first, is in the layout tools/release/release.ps1 maps to
  the player zip (_bmad-output/specs/spec-distribution-v0/packages.md): Mods/<name>/mod.json (this repo's, byte for
  byte) and Mods/<name>/Scripts/ with the Lua files deploy.ps1 installs (deploy-lib.ps1 $ModScripts). No DLL, no pak,
  no settings file: the mod is Lua only, and it never ships any of core's files or a test file.
  -Fixtures packs build/fixtures/<name>Pak_P.pak with the workspace's repak (V11, uncompressed; AGENTS.md): one text
  file of ours under NuclearNightmare/Content/Mods/<name>Pak/, nothing the game loads. deploy.ps1 -Test installs it as
  Content/Paks/<name>Pak_P.pak and <name>PakOff_P.pak.disabled. Test tooling; never shipped.
  Never touches a game copy. Exit 0 on success; a missing source file stops it (exit 1).
.EXAMPLE
  ./build.ps1
  ./build.ps1 -Fixtures
#>
param([switch] $Fixtures)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'deploy-lib.ps1')

$manifest = Get-Content (Join-Path $here 'mod.json') -Raw | ConvertFrom-Json
$name = $manifest.name
if ($name -isnot [string] -or $name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*\z') { throw "mod.json name '$name' is not a folder name" }

if ($Fixtures) {
    # The workspace's repak: tools/repak/repak.exe above this repo (a worktree's workspace may lack the binary; the
    # main checkout has it).
    $repak = $null
    $d = $here
    while ($d) {
        $c = Join-Path $d 'tools\repak\repak.exe'
        if (Test-Path $c) { $repak = $c; break }
        $d = Split-Path $d
    }
    if (-not $repak) {
        $gc = & git -C $here rev-parse --path-format=absolute --git-common-dir 2>$null
        if ($gc) {
            $d = Split-Path ($gc -replace '/', '\')
            while ($d) { $c = Join-Path $d 'tools\repak\repak.exe'; if (Test-Path $c) { $repak = $c; break }; $d = Split-Path $d }
        }
    }
    if (-not $repak) { throw 'repak not found (the workspace tools/README.md)' }
    $out = Join-Path $here 'build\fixtures'
    $stage = Join-Path $out 'stage'
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    $dir = Join-Path $stage "NuclearNightmare\Content\Mods\${name}Pak"
    New-Item -ItemType Directory -Force $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'mod-manager-fixture.txt'), "Mod Manager test fixture (mods/mod-manager). Holds nothing the game loads.")
    $pak = Join-Path $out "${name}Pak_P.pak"
    Remove-Item -LiteralPath $pak -ErrorAction SilentlyContinue
    & $repak pack --version V11 -q $stage $pak
    if ($LASTEXITCODE) { throw "repak pack failed ($LASTEXITCODE)" }
    Remove-Item -LiteralPath $stage -Recurse -Force
    Write-Host "$pak ($((Get-Item $pak).Length) bytes):"
    & $repak list $pak | ForEach-Object { Write-Host "  $_" }
    exit 0
}

foreach ($f in $ModScripts) {
    if (-not (Test-Path -LiteralPath (Join-Path $here "Scripts\$f") -PathType Leaf)) { throw "missing Scripts/$f" }
}
$pkgRoot = Join-Path $here 'build\package'
Remove-Item -LiteralPath $pkgRoot -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $pkgRoot) { throw "could not delete $pkgRoot" }
$modDir = Join-Path $pkgRoot "Mods\$name"
$scripts = Join-Path $modDir 'Scripts'
New-Item -ItemType Directory -Force $scripts | Out-Null
Copy-Item -LiteralPath (Join-Path $here 'mod.json') -Destination $modDir
foreach ($f in $ModScripts) { Copy-Item -LiteralPath (Join-Path $here "Scripts\$f") -Destination $scripts }

Write-Host "$name $($manifest.version) staged in build/package/:"
Get-ChildItem -LiteralPath $pkgRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    Write-Host ("  {0,-40} {1,8:N0} bytes" -f $_.FullName.Substring($pkgRoot.Length + 1).Replace('\', '/'), $_.Length)
}
exit 0
