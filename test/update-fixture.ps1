<#
.SYNOPSIS
  The update scenario's fixture catalog (Mod Manager v2 story 6; dot-source it): release zips, a signed index and
  revoked list, the fixture server's transport map and the catalog-test template, all made at deploy time.
.DESCRIPTION
  New-UpdateFixture -Workspace <main checkout> -Out <folder> [-Minisign <exe>] writes into -Out (deleted first):
    site/hud-clock-0.3.0.zip, site/hud-clock-0.3.1.zip   from mods/hud-clock (mod.json, Scripts/<its $ModScripts>), the
                                                         version patched into the zip's mod.json; 0.3.0 also has
                                                         Scripts/old-0.3.0.txt, a file only it has
    site/whistle-mute-0.2.1.zip                          from mods/whistle-mute, as it is
    site/nucleus-<core patch + 1>.zip                    <CoreName>'s build/package (a normal build) with the version patched
    index.json(.minisig)   schema 2, game_builds and every version for the build in the mods' mod.json, each url in
                           the real release form (https://github.com/NuclearNightmare-Community/<mod>/releases/...)
    revoked.json(.minisig) HUD Clock 0.3.0 revoked (its index sha256, action disable), signed with the revoke key
    map.json               https-fixture-server.ps1's transport map: both built-in bases (keys.json 404, index,
                           revoked and their signatures) and every zip url
    catalog-test.template.json  {"keys": [release, backup, revoke]}: the public keys core's test main.dll trusts
  The keys are made with minisign -G -W in a temporary folder and deleted with their secret halves once signed; nothing
  of this is ever committed or packaged (the deploy writes it into the VM run's stage only). Zips are built like
  tools/release/release.ps1's (sorted entries, Deflate, release layout). Returns @{ Core; Files } (the new core
  version, and the installer-layout files of the installed fixtures: HudClock 0.3.0 and WhistleMute 0.2.1, as
  relative path -> bytes, for the deploy to put in the copy).
#>
Add-Type -AssemblyName System.IO.Compression

function Get-UpdateFixtureSha([byte[]] $b) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)).ToLowerInvariant() }

# A mod.json's text with its first "version" (the mod's own, above dependsOn) set to $Version.
function Set-UpdateFixtureVersion([string] $Text, [string] $Version) {
    $new = [regex]::new('("version"\s*:\s*")[^"]*(")').Replace($Text, "`${1}$Version`${2}", 1)
    if ($new -eq $Text -and $Text -notmatch [regex]::Escape("`"$Version`"")) { throw 'no "version" in the mod.json' }
    $new
}

# Release-layout entry name for a build/package-style relative path (Mods/<Name>/..., LogicMods/<X>.pak, <X>_P.pak).
function Get-UpdateFixtureZipName([string] $Rel) {
    $r = $Rel -replace '\\', '/'
    if ($r -like 'Mods/*') { return "NuclearNightmare/Binaries/Win64/ue4ss/$r" }
    if ($r -like 'LogicMods/*') { return "NuclearNightmare/Content/Paks/$r" }
    if ($r -notmatch '/') { return "NuclearNightmare/Content/Paks/$r" }
    throw "not a package path: $Rel"
}

# Zip bytes from @{ <relative package path> = <bytes> } (sorted, Deflate).
function New-UpdateFixtureZip([System.Collections.IDictionary] $Files) {
    $ms = [IO.MemoryStream]::new()
    $za = [IO.Compression.ZipArchive]::new($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($k in @($Files.Keys | Sort-Object { Get-UpdateFixtureZipName $_ } -CaseSensitive)) {
        $e = $za.CreateEntry((Get-UpdateFixtureZipName $k), [IO.Compression.CompressionLevel]::Optimal)
        $e.LastWriteTime = [DateTimeOffset]::new(2026, 11, 21, 0, 0, 0, [TimeSpan]::Zero)
        $b = [byte[]]$Files[$k]
        $s = $e.Open(); $s.Write($b, 0, $b.Length); $s.Dispose()
    }
    $za.Dispose()
    , $ms.ToArray()
}

# A Lua mod's package files (mod.json with $Version, Scripts/<its deploy-lib $ModScripts>).
function Get-UpdateFixtureLuaMod([string] $Repo, [string] $Version) {
    $manifest = Get-Content (Join-Path $Repo 'mod.json') -Raw | ConvertFrom-Json
    $name = $manifest.name
    $libText = Get-Content (Join-Path $Repo 'deploy-lib.ps1') -Raw
    if ($libText -notmatch '(?m)^\$ModScripts\s*=\s*(.+)$') { throw "no `$ModScripts in $Repo/deploy-lib.ps1" }
    $scripts = @([regex]::Matches($Matches[1], "'([A-Za-z0-9_.-]+\.lua)'") | ForEach-Object { $_.Groups[1].Value })
    if (-not $scripts) { throw "no scripts in $Repo/deploy-lib.ps1's `$ModScripts" }
    $files = [ordered]@{}
    $json = Set-UpdateFixtureVersion ([IO.File]::ReadAllText((Join-Path $Repo 'mod.json'))) $Version
    $files["Mods/$name/mod.json"] = [Text.UTF8Encoding]::new($false).GetBytes($json)
    foreach ($s in $scripts) { $files["Mods/$name/Scripts/$s"] = [IO.File]::ReadAllBytes((Join-Path $Repo "Scripts\$s")) }
    @{ Manifest = $manifest; Name = $name; Files = $files }
}

function New-UpdateFixture {
    param([Parameter(Mandatory)] [string] $Workspace, [Parameter(Mandatory)] [string] $Out, [Parameter(Mandatory)] [string] $CoreName, [string] $Minisign)
    $ErrorActionPreference = 'Stop'
    if (-not $Minisign) {
        $cmd = Get-Command minisign -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { throw 'the update scenario signs its fixture catalog with minisign: not found on PATH (winget install jedisct1.minisign)' }
        $Minisign = $cmd.Source
    }
    $corePkg = Join-Path $Workspace "mods\$CoreName\build\package"
    $coreJsonFile = Join-Path $corePkg "Mods\$CoreName\mod.json"
    foreach ($p in (Join-Path $Workspace 'mods\hud-clock\mod.json'), (Join-Path $Workspace 'mods\whistle-mute\mod.json'), $coreJsonFile) {
        if (-not (Test-Path -LiteralPath $p)) { throw "the update scenario's fixtures need $p" }
    }
    if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
    $site = Join-Path $Out 'site'
    New-Item -ItemType Directory -Force $site | Out-Null
    $utf8 = [Text.UTF8Encoding]::new($false)
    $now = [datetime]::UtcNow.AddMinutes(-5).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)

    # ---- the zips
    $hc0 = Get-UpdateFixtureLuaMod (Join-Path $Workspace 'mods\hud-clock') '0.3.0'
    $hc0.Files["Mods/$($hc0.Name)/Scripts/old-0.3.0.txt"] = $utf8.GetBytes("Only HUD Clock 0.3.0 (the update fixture) has this file.`r`n")
    $hc1 = Get-UpdateFixtureLuaMod (Join-Path $Workspace 'mods\hud-clock') '0.3.1'
    $wm = Get-UpdateFixtureLuaMod (Join-Path $Workspace 'mods\whistle-mute') ([string](Get-Content (Join-Path $Workspace 'mods\whistle-mute\mod.json') -Raw | ConvertFrom-Json).version)
    $coreManifest = Get-Content $coreJsonFile -Raw | ConvertFrom-Json
    $cv = [string]$coreManifest.version
    if ($cv -notmatch '^(\d+)\.(\d+)\.(\d+)$') { throw "core's build/package version '$cv' is not plain semver" }
    $coreNew = "$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)"
    $coreFiles = [ordered]@{}
    foreach ($f in Get-ChildItem -LiteralPath $corePkg -Recurse -File) {
        $rel = $f.FullName.Substring($corePkg.Length + 1) -replace '\\', '/'
        $coreFiles[$rel] = if ($rel -eq "Mods/$CoreName/mod.json") { $utf8.GetBytes((Set-UpdateFixtureVersion ([IO.File]::ReadAllText($f.FullName)) $coreNew)) } else { [IO.File]::ReadAllBytes($f.FullName) }
    }
    $zips = [ordered]@{
        'hud-clock|0.3.0'                    = @{ Mod = $hc0; Bytes = (New-UpdateFixtureZip $hc0.Files) }
        'hud-clock|0.3.1'                    = @{ Mod = $hc1; Bytes = (New-UpdateFixtureZip $hc1.Files) }
        "whistle-mute|$($wm.Manifest.version)" = @{ Mod = $wm; Bytes = (New-UpdateFixtureZip $wm.Files) }
        "$($CoreName.ToLowerInvariant())|$coreNew"                   = @{ Mod = @{ Manifest = $coreManifest; Name = $coreManifest.name }; Bytes = (New-UpdateFixtureZip $coreFiles) }
    }

    # ---- the index, the map
    $map = [ordered]@{}
    $bases = 'https://nuclearnightmare-community.github.io/catalog/', 'https://github.com/NuclearNightmare-Community/catalog/releases/download/catalog/'
    foreach ($b in $bases) {
        $map["${b}keys.json"] = @{ status = 404 }
        foreach ($f in 'index.json', 'index.json.minisig', 'revoked.json', 'revoked.json.minisig') { $map["$b$f"] = @{ status = 200; file = $f } }
    }
    $pkgs = [ordered]@{}
    foreach ($k in $zips.Keys) {
        $mod, $v = $k -split '\|'
        $z = $zips[$k]; $m = $z.Mod.Manifest
        $file = "$mod-$v.zip"
        [IO.File]::WriteAllBytes((Join-Path $site $file), $z.Bytes)
        $repo = "NuclearNightmare-Community/$mod"
        $url = "https://github.com/$repo/releases/download/v$v/$file"
        $map[$url] = @{ status = 200; file = "site/$file" }
        $deps = @(@($m.dependsOn) | Where-Object { $_ } | ForEach-Object { [ordered]@{ id = "$($_.id)".ToLowerInvariant(); version = $_.version } })
        $ver = [ordered]@{ version = $v; scope = $m.scope; game = [ordered]@{ version = $m.game.version; build = $m.game.build }; ue4ss = $m.ue4ss
            dependsOn = $deps; url = $url; sha256 = (Get-UpdateFixtureSha $z.Bytes); size = $z.Bytes.Length; published = $now; installable_after = $now
            changelog_url = "https://github.com/$repo/releases/tag/v$v"; attestation = $null }
        if (-not $pkgs.Contains($mod)) {
            $p = [ordered]@{ id = "$($m.id)".ToLowerInvariant(); name = $z.Mod.Name }
            if ($m.displayName) { $p.displayName = $m.displayName }
            $p.description = $m.description; $p.categories = @($m.categories); $p.kind = 'mod'
            $p.publisher = 'NuclearNightmare-Community'; $p.repo = $repo; $p.license = $(if ($m.license) { $m.license } else { 'MIT' }); $p.nexus_url = $null
            $p.versions = [Collections.Generic.List[object]]::new()
            $pkgs[$mod] = $p
        }
        $pkgs[$mod].versions.Insert(0, $ver) # newest first (each package's versions above are listed oldest first)
    }
    $build = $hc1.Manifest.game
    $ix = [ordered]@{ schema = 2; serial = 3; issued = $now; game_builds = @([ordered]@{ version = $build.version; build = $build.build })
        packages = @($pkgs.Values | ForEach-Object { $_.versions = $_.versions.ToArray(); $_ }) }
    $hcSha = Get-UpdateFixtureSha $zips['hud-clock|0.3.0'].Bytes
    $rv = [ordered]@{ schema = 1; serial = 2; issued = $now; revoked = @([ordered]@{ id = "$($hc0.Manifest.id)".ToLowerInvariant(); version = '0.3.0'; sha256 = $hcSha
                reason = 'Fixture revocation: crashes on map load (update scenario).'; action = 'disable' }) }
    [IO.File]::WriteAllText((Join-Path $Out 'index.json'), ($ix | ConvertTo-Json -Depth 16), $utf8)
    [IO.File]::WriteAllText((Join-Path $Out 'revoked.json'), ($rv | ConvertTo-Json -Depth 16), $utf8)
    [IO.File]::WriteAllText((Join-Path $Out 'map.json'), ($map | ConvertTo-Json -Depth 8), $utf8)

    # ---- keys (made, used and deleted here), signatures, the template
    $keyDir = Join-Path ([IO.Path]::GetTempPath()) ("mm-update-keys-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $keyDir | Out-Null
    try {
        $keys = [ordered]@{}
        foreach ($role in 'release', 'backup', 'revoke') {
            $pub = Join-Path $keyDir "$role.pub"; $sec = Join-Path $keyDir "$role.key"
            $o = & $Minisign -G -W -p $pub -s $sec 2>&1
            if ($LASTEXITCODE) { throw "minisign -G failed for $role`: $o" }
            $keys[$role] = @{ Pub = (Get-Content $pub)[1].Trim(); Sec = $sec }
        }
        foreach ($s in @(@('index.json', 'release'), @('revoked.json', 'revoke'))) {
            $o = & $Minisign -S -s $keys[$s[1]].Sec -m (Join-Path $Out $s[0]) -t 'mod-manager update fixture' 2>&1
            if ($LASTEXITCODE) { throw "minisign -S failed for $($s[0]): $o" }
        }
        $tpl = [ordered]@{ keys = @(foreach ($role in $keys.Keys) { [ordered]@{ role = $role; name = "update-fixture-$role"; key = $keys[$role].Pub } }) }
        [IO.File]::WriteAllText((Join-Path $Out 'catalog-test.template.json'), ($tpl | ConvertTo-Json -Depth 8), $utf8)
    } finally { Remove-Item $keyDir -Recurse -Force -ErrorAction SilentlyContinue }

    $installed = [ordered]@{}
    foreach ($src in $hc0.Files, $wm.Files) { foreach ($k in $src.Keys) { $installed[$k] = $src[$k] } }
    @{ Core = $coreNew; Files = $installed; HudClockSha = $hcSha }
}
