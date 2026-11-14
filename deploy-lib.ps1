<#
.SYNOPSIS
  Pure helpers for deploy.ps1 (dot-source it), testable on their own (test/unit/deploy_test.ps1).
  Version needs use the same rule as core's nucleus.semver (api-contract.md, "Versioning"; core story 18): a need is
  a minimum. ">=X.Y.Z", the old caret form "^X.Y.Z" and a bare "X.Y.Z" all mean "this version or newer", and a need
  below the installed core's compatibility floor (its mod.json "compat.floor") is refused. Versions are plain
  MAJOR.MINOR.PATCH; anything else is not a version.
.EXAMPLE
  . ./deploy-lib.ps1; Test-VersionNeed -Version '0.4.0' -Need '>=0.2.0'   # ok
#>

# The Scripts/ files a deploy installs and a release ships under ue4ss/Mods/<name>/Scripts/ (deploy.ps1 and
# build.ps1 both use this list).
$ModScripts = 'main.lua', 'json.lua', 'inventory.lua', 'strings.lua', 'screen.lua'

# Core's id (distribution story 13, mod-ids.md).
$CoreId = 'nuclearnightmare-community.nucleus'

# ConvertTo-ModId <id> -> the normalized id, or $null (dev-only; no message): the rule of core's nucleus.modid
# (mod-ids.md "Normalizer"): lowercase; github.com/<owner>.<mod> -> <owner>.<mod>; [a-z0-9-] owner and mod part;
# other hosts, www./http(s):// and a bare id refused; at most 200 characters. test/unit/deploy_test.ps1 runs it over
# the workspace's shared cases (tools/release/tests/modid-cases.json).
function ConvertTo-ModId {
    param([AllowNull()] [AllowEmptyString()] [object] $Id)
    if ($Id -isnot [string] -or $Id.Length -eq 0 -or $Id.Length -gt 200) { return $null }
    # Non-ASCII is never part of an id; refusing it first keeps ToLowerInvariant from mapping, say, the Kelvin sign to k.
    if ($Id -cnotmatch '\A[\x00-\x7F]*\z') { return $null }
    $s = $Id.ToLowerInvariant()
    if ($s.StartsWith('github.com/')) { $s = $s.Substring(11) }
    if ($s.StartsWith('www.')) { return $null }
    if ($s -cnotmatch '\A[a-z0-9-]+\.[a-z0-9-]+\z') { return $null }
    return $s
}

# Test-CoreId <id> -> $true when the id names Nucleus (through the normalizer).
function Test-CoreId {
    param([AllowNull()] [AllowEmptyString()] [object] $Id)
    return (ConvertTo-ModId $Id) -eq $CoreId
}

# ConvertTo-Semver '0.2.0' -> @{ Major = 0; Minor = 2; Patch = 0 }, or $null when the text isn't plain semver
# (ASCII digits only, 1-9 per part, nothing after the patch, not even a newline).
function ConvertTo-Semver {
    param([AllowNull()] [AllowEmptyString()] [object] $Text)
    if ($Text -isnot [string]) { return $null }
    if ($Text -notmatch '\A([0-9]{1,9})\.([0-9]{1,9})\.([0-9]{1,9})\z') { return $null }
    return @{ Major = [int]$Matches[1]; Minor = [int]$Matches[2]; Patch = [int]$Matches[3] }
}

# ConvertFrom-VersionNeed '>=0.2.0' -> the minimum as ConvertTo-Semver gives it, or $null when the text isn't
# ">=X.Y.Z", "^X.Y.Z" or "X.Y.Z" (at most 64 bytes, as core's semver.parseNeed).
function ConvertFrom-VersionNeed {
    param([AllowNull()] [AllowEmptyString()] [object] $Need)
    if ($Need -isnot [string] -or $Need.Length -eq 0 -or $Need.Length -gt 64) { return $null }
    $body = if ($Need.StartsWith('>=')) { $Need.Substring(2) } elseif ($Need.StartsWith('^')) { $Need.Substring(1) } else { $Need }
    return ConvertTo-Semver $body
}

# Compare-Semver a b -> -1 | 0 | 1 for two ConvertTo-Semver results.
function Compare-Semver {
    param([Parameter(Mandatory)] $A, [Parameter(Mandatory)] $B)
    foreach ($k in 'Major', 'Minor', 'Patch') { if ($A[$k] -ne $B[$k]) { return $(if ($A[$k] -lt $B[$k]) { -1 } else { 1 }) } }
    return 0
}

# Test-VersionNeed -Version <have> -Need <need> [-Floor <floor>] -> 'ok' | 'core-too-old' | 'mod-too-old' | 'bad-have',
# as core's semver.check: 'bad-have' when the installed version isn't plain semver (an installed mod.json we don't
# control: simply not compatible), 'core-too-old' when it is below the need's minimum, 'mod-too-old' when the minimum
# is below the floor. A floor that is missing or not plain semver means no floor. A need that isn't ">=X.Y.Z",
# "^X.Y.Z" or "X.Y.Z" throws (it's our own mod.json, so that's a bug to fix, not a reason to refuse an install).
function Test-VersionNeed {
    param(
        [AllowNull()] [AllowEmptyString()] [object] $Version,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Need,
        [AllowNull()] [AllowEmptyString()] [object] $Floor
    )
    $n = ConvertFrom-VersionNeed $Need
    if (-not $n) { throw "unsupported version need '$Need' (only >=MAJOR.MINOR.PATCH, ^MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH)" }
    $h = ConvertTo-Semver $Version
    if (-not $h) { return 'bad-have' }
    if ((Compare-Semver $h $n) -lt 0) { return 'core-too-old' }
    $f = ConvertTo-Semver $Floor
    if ($f -and (Compare-Semver $n $f) -lt 0) { return 'mod-too-old' }
    return 'ok'
}

# Edit-ModsTxt -Lines <mods.txt lines> -Remove <names> -Add <names in order> [-Disabled <names>] -After <name> -> new
# lines. Drops every line of each name in -Remove, -Add and -Disabled (enabled or not), then inserts "<name> : 1" for
# each of -Add and "<name> : 0" for each of -Disabled, in that order: right below -After's line when that line is
# above "Keybinds : 1"; otherwise right above Keybinds (AGENTS.md: never appended at the end), or at the end only when
# there is no Keybinds line at all. Other lines keep their order.
function Edit-ModsTxt {
    param(
        [AllowEmptyCollection()] [string[]] $Lines = @(),
        [string[]] $Remove = @(),
        [string[]] $Add = @(),
        [string[]] $Disabled = @(),
        [string] $After
    )
    $names = @($Remove) + @($Add) + @($Disabled) | Where-Object { $_ }
    $kept = [Collections.Generic.List[string]]::new()
    foreach ($l in $Lines) {
        $drop = $false
        foreach ($n in $names) { if ($l -match ('^\s*' + [regex]::Escape($n) + '\s*:')) { $drop = $true; break } }
        if (-not $drop) { $kept.Add($l) }
    }
    $Add = @($Add | Where-Object { $_ }); $Disabled = @($Disabled | Where-Object { $_ })
    if (-not $Add -and -not $Disabled) { return , $kept.ToArray() }
    $k = -1; $a = -1
    for ($i = 0; $i -lt $kept.Count; $i++) {
        if ($k -lt 0 -and $kept[$i] -match '^\s*Keybinds\s*:') { $k = $i }
        if ($After -and $a -lt 0 -and $kept[$i] -match ('^\s*' + [regex]::Escape($After) + '\s*:')) { $a = $i }
    }
    $at = if ($a -ge 0 -and ($k -lt 0 -or $a -lt $k)) { $a + 1 } elseif ($k -ge 0) { $k } else { $kept.Count }
    $kept.InsertRange($at, [string[]](@($Add | ForEach-Object { "$_ : 1" }) + @($Disabled | ForEach-Object { "$_ : 0" })))
    return , $kept.ToArray()
}

# Get-ModsTxtState -Lines <lines> -Name <name> -> 'enabled' | 'disabled' | 'absent' (the first line for that name).
function Get-ModsTxtState {
    param([AllowEmptyCollection()] [string[]] $Lines = @(), [Parameter(Mandatory)] [string] $Name)
    foreach ($l in $Lines) {
        if ($l -match ('^\s*' + [regex]::Escape($Name) + '\s*:\s*(\d+)')) { return $(if ($Matches[1] -eq '1') { 'enabled' } else { 'disabled' }) }
    }
    return 'absent'
}

# Read-ModsTxt <path> -> @{ Lines; Newline; Trailing; Bom }: the lines plus how the file ends them, so
# Write-ModsTxt writes back byte-identical text when the lines are unchanged.
function Read-ModsTxt {
    param([Parameter(Mandatory)] [string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [Text.Encoding]::UTF8.GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $trailing = $text.EndsWith("`n")
    $body = if ($trailing) { $text.Substring(0, $text.Length - $(if ($text.EndsWith("`r`n")) { 2 } else { 1 })) } else { $text }
    $lines = if ($body.Length) { [string[]]($body -split "`r?`n") } else { [string[]]@() }
    return @{ Lines = $lines; Newline = $nl; Trailing = $trailing; Bom = $bom }
}
function Write-ModsTxt {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] $File, [AllowEmptyCollection()] [string[]] $Lines = @())
    $text = ($Lines -join $File.Newline) + $(if ($File.Trailing -and $Lines.Count) { $File.Newline } else { '' })
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new([bool]$File.Bom))
}

# The FILES check of run.ps1 (the Mod Manager writes nothing in story 3).
# The state of a copy: mods.txt's SHA-256 and the file names under Content/Paks and Content/Paks/LogicMods.
function Get-FileState([string] $instance) {
    $mt = Join-Path $instance 'NuclearNightmare\Binaries\Win64\ue4ss\Mods\mods.txt'
    $pk = Join-Path $instance 'NuclearNightmare\Content\Paks'
    $names = { param($d) if (Test-Path $d) { (@(Get-ChildItem -LiteralPath $d -File -Force | ForEach-Object Name | Sort-Object) -join '|') } else { '' } }
    [pscustomobject]@{
        ModsTxt = if (Test-Path $mt) { (Get-FileHash -LiteralPath $mt -Algorithm SHA256).Hash } else { 'missing' }
        Paks = & $names $pk
        LogicMods = & $names (Join-Path $pk 'LogicMods')
    }
}
# "[run.ps1] FILES unchanged" or "[run.ps1] FILES changed: <what>" (or "not recorded"), appended to the kept log.
function Get-FilesLine($before, $after) {
    if (-not $before -or -not $after) { return '[run.ps1] FILES not recorded' }
    $what = @()
    if ($before.ModsTxt -ne $after.ModsTxt) { $what += "mods.txt sha256 $($before.ModsTxt) -> $($after.ModsTxt)" }
    foreach ($k in 'Paks', 'LogicMods') {
        if ($before.$k -ne $after.$k) {
            $b = @($before.$k -split '\|' | Where-Object { $_ }); $a = @($after.$k -split '\|' | Where-Object { $_ })
            $gone = @($b | Where-Object { $_ -notin $a }); $new = @($a | Where-Object { $_ -notin $b })
            $what += "$k$(if ($gone) { ' removed ' + ($gone -join ',') })$(if ($new) { ' added ' + ($new -join ',') })"
        }
    }
    if ($what) { return "[run.ps1] FILES changed: $($what -join '; ')" }
    return '[run.ps1] FILES unchanged'
}
