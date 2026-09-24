$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repoRoot = [IO.Path]::GetFullPath('D:\code\pillage_people\art\references\ship-kit')
$archiveRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '_archive\before-consolidation'))
if (-not $archiveRoot.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive outside ship kit' }
$legacyNames = @('modeling-handoff','01-hull-modules-v1.png','02-hull-assembly-concepts-v1.png','03-captains-quarters-and-access-v1.png','04-masts-and-lookouts-v1.png','05-deck-fittings-v1.png','06-stern-and-quarter-galleries-v1.png','07-multi-deck-style-v1.png','08-corrected-stern-and-decks-v1.png','09-symmetric-closed-bow-v1.png','ship-modeling-handoff-v1.zip','ship-modeling-handoff-v2-floors.zip','ship-modeling-handoff-v3-corrected.zip')
$activeNames = @('canonical','accessories','previews','tools','START_HERE.md','index.html','ship-modeling-kit.zip')
# Refuse to overwrite an unknown active kit; preserve all prior work in one archive.
foreach ($name in $activeNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $name))) { throw "Missing staged item $name" }
    if (Test-Path -LiteralPath (Join-Path $repoRoot $name)) { throw "Destination already exists: $name" }
}
foreach ($name in $legacyNames) {
    $path = [IO.Path]::GetFullPath((Join-Path $repoRoot $name))
    if (-not $path.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Source outside ship kit' }
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing legacy source $path" }
    if (Test-Path -LiteralPath (Join-Path $archiveRoot $name)) { throw "Archive collision: $name" }
}
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
foreach ($name in $legacyNames) {
    Move-Item -LiteralPath (Join-Path $repoRoot $name) -Destination (Join-Path $archiveRoot $name)
}
foreach ($name in $activeNames) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $repoRoot $name) -Recurse
}
Write-Output 'Installed one active kit; all old revisions preserved in _archive/before-consolidation.'
