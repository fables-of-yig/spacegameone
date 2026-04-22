[CmdletBinding()]
param(
    [string]$SourceRoot = 'D:\SPaceAssetsNoisey\4-17',
    [string]$PackId = 'demo'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packRoot = Join-Path $repoRoot ("Content\" + $PackId)

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-RelativeUnixPath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )
    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $fileFull = [System.IO.Path]::GetFullPath($FullPath)
    $baseUri = [System.Uri]::new(($baseFull.TrimEnd('\') + '\'))
    $fileUri = [System.Uri]::new($fileFull)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString())
}

function New-Slug {
    param([string]$Text)
    $slug = $Text.ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $slug = $slug.Trim('_')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return 'asset'
    }
    return $slug
}

function ConvertTo-HashtableRecursive {
    param([object]$Value)
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $table = @{}
        foreach ($key in $Value.Keys) {
            $table[$key] = ConvertTo-HashtableRecursive $Value[$key]
        }
        return $table
    }
    if ($Value -is [pscustomobject]) {
        $table = @{}
        foreach ($prop in $Value.PSObject.Properties) {
            $table[$prop.Name] = ConvertTo-HashtableRecursive $prop.Value
        }
        return $table
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(ConvertTo-HashtableRecursive $item)
        }
        return $items
    }
    return $Value
}

function Read-JsonFile {
    param(
        [string]$Path,
        [object]$Fallback
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $Fallback
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Fallback
    }
    return ConvertTo-HashtableRecursive (ConvertFrom-Json -InputObject $raw)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )
    Ensure-Dir (Split-Path -Parent $Path)
    $json = $Data | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Copy-FilteredFiles {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Extension
    )
    $copied = @()
    Ensure-Dir $DestPath
    Get-ChildItem -LiteralPath $SourcePath -Recurse -File | ForEach-Object {
        $name = $_.Name
        if ($name.StartsWith('._') -or $name -eq '.DS_Store') {
            return
        }
        if ($_.Extension.ToLowerInvariant() -ne $Extension.ToLowerInvariant()) {
            return
        }
        $rel = Get-RelativeUnixPath -BasePath $SourcePath -FullPath $_.FullName
        $destFile = Join-Path $DestPath ($rel -replace '/', '\')
        Ensure-Dir (Split-Path -Parent $destFile)
        Copy-Item -LiteralPath $_.FullName -Destination $destFile -Force
        $copied += [ordered]@{
            source = $_.FullName
            relative = $rel
            destination = $destFile
        }
    }
    return $copied
}

function Select-ParallaxCandidates {
    param([array]$PngFiles)
    $candidates = @()
    foreach ($entry in $PngFiles) {
        $rel = [string]$entry.relative
        $lower = $rel.ToLowerInvariant()
        if ($lower -match '(^|/)(bg|background|backdrop|sky|skyline|parallax|horizon|city|nebula)' -or
            $lower -match '(background|backdrop|sky|skyline|parallax|horizon|city|nebula)') {
            $candidates += ,$entry
        }
    }
    return $candidates
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Source root not found: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $packRoot)) {
    throw "Pack root not found: $packRoot"
}

$musicFiles = Copy-FilteredFiles -SourcePath (Join-Path $SourceRoot 'music') -DestPath (Join-Path $packRoot 'Audio\Music\imported') -Extension '.ogg'
$sfxFiles = Copy-FilteredFiles -SourcePath (Join-Path $SourceRoot 'SFX') -DestPath (Join-Path $packRoot 'Audio\Sfx\imported') -Extension '.ogg'
$portraitFiles = Copy-FilteredFiles -SourcePath (Join-Path $SourceRoot 'Portraits') -DestPath (Join-Path $packRoot 'Portraits\imported') -Extension '.png'
$vfxFiles = Copy-FilteredFiles -SourcePath (Join-Path $SourceRoot 'VFX') -DestPath (Join-Path $packRoot 'Sprites\VFX\imported') -Extension '.png'
$astralFiles = Copy-FilteredFiles -SourcePath (Join-Path $SourceRoot 'AstralBodies') -DestPath (Join-Path $packRoot 'Systems\AstralBodies\imported') -Extension '.png'
$shipFiles = Copy-FilteredFiles -SourcePath (Join-Path $SourceRoot 'Ships') -DestPath (Join-Path $repoRoot 'Space\art\ships\noisey_4_17') -Extension '.png'
$tilesetPngs = Copy-FilteredFiles -SourcePath (Join-Path $SourceRoot 'SidescrollerTilesets') -DestPath (Join-Path $packRoot 'TilesetSources\imported') -Extension '.png'

$parallaxRoot = Join-Path $packRoot 'Backdrops\Parallax\imported'
Ensure-Dir $parallaxRoot
$parallaxFiles = @()
foreach ($entry in Select-ParallaxCandidates -PngFiles $tilesetPngs) {
    $rel = [string]$entry.relative
    $sourceFile = [string]$entry.source
    $destFile = Join-Path $parallaxRoot ($rel -replace '/', '\')
    Ensure-Dir (Split-Path -Parent $destFile)
    Copy-Item -LiteralPath $sourceFile -Destination $destFile -Force
    $parallaxFiles += [ordered]@{
        source = $sourceFile
        relative = $rel
        destination = $destFile
    }
}

$manifestPath = Join-Path $packRoot 'Audio\manifest.json'
$clipsPath = Join-Path $packRoot 'Audio\clips.json'
$manifest = Read-JsonFile -Path $manifestPath -Fallback @{ sfx = @{}; ambience = @{}; music = @{} }
if (-not $manifest.ContainsKey('sfx')) { $manifest['sfx'] = @{} }
if (-not $manifest.ContainsKey('ambience')) { $manifest['ambience'] = @{} }
if (-not $manifest.ContainsKey('music')) { $manifest['music'] = @{} }

$clipsRoot = Read-JsonFile -Path $clipsPath -Fallback @{ clips = @() }
if (-not $clipsRoot.ContainsKey('clips')) { $clipsRoot['clips'] = @() }
$clipIndex = @{}
foreach ($clip in $clipsRoot['clips']) {
    if ($clip -is [System.Collections.IDictionary] -and $clip.ContainsKey('id')) {
        $clipIndex[[string]$clip['id']] = $clip
    }
}

foreach ($entry in $musicFiles) {
    $packRel = ('Audio/Music/imported/' + [string]$entry.relative).Replace('\', '/')
    $id = 'music_' + (New-Slug ([System.IO.Path]::ChangeExtension([string]$entry.relative, $null)))
    $manifest['music'][$id] = $packRel
    $clipIndex[$id] = [ordered]@{
        id = $id
        file = $packRel
        start_sec = 0.0
        end_sec = -1.0
        tags = @('music', 'imported')
    }
}

foreach ($entry in $sfxFiles) {
    $packRel = ('Audio/Sfx/imported/' + [string]$entry.relative).Replace('\', '/')
    $id = 'sfx_' + (New-Slug ([System.IO.Path]::ChangeExtension([string]$entry.relative, $null)))
    $manifest['sfx'][$id] = $packRel
    $clipIndex[$id] = [ordered]@{
        id = $id
        file = $packRel
        start_sec = 0.0
        end_sec = -1.0
        tags = @('sfx', 'imported')
    }
}

$clipList = @()
foreach ($key in ($clipIndex.Keys | Sort-Object)) {
    $clipList += ,$clipIndex[$key]
}
$clipsRoot['clips'] = $clipList

$portraitEntries = @()
$portraitSeen = @{}
foreach ($entry in $portraitFiles) {
    $baseId = [System.IO.Path]::GetFileNameWithoutExtension([string]$entry.relative)
    $portraitId = $baseId
    if ($portraitSeen.ContainsKey($portraitId)) {
        $portraitId = $baseId + '_' + (New-Slug ([string]$entry.relative))
    }
    $portraitSeen[$portraitId] = $true
    $relPath = ('Portraits/imported/' + [string]$entry.relative).Replace('\', '/')
    $portraitEntries += [ordered]@{
        id = $portraitId
        file = $relPath
        aliases = @($portraitId.ToUpperInvariant())
    }
}

$parallaxManifest = [ordered]@{
    images = @()
}
foreach ($entry in $parallaxFiles) {
    $parallaxManifest.images += [ordered]@{
        file = ('Backdrops/Parallax/imported/' + [string]$entry.relative).Replace('\', '/')
    }
}

$tilesetManifest = [ordered]@{
    sources = @()
}
foreach ($entry in $tilesetPngs) {
    $tilesetManifest.sources += [ordered]@{
        file = ('TilesetSources/imported/' + [string]$entry.relative).Replace('\', '/')
    }
}

$astralManifest = [ordered]@{
    sprites = @()
}
foreach ($entry in $astralFiles) {
    $astralManifest.sprites += [ordered]@{
        file = ('Systems/AstralBodies/imported/' + [string]$entry.relative).Replace('\', '/')
    }
}

$shipManifest = [ordered]@{
    hulls = @()
}
foreach ($entry in $shipFiles) {
    $shipManifest.hulls += [ordered]@{
        file = ('res://Space/art/ships/noisey_4_17/' + [string]$entry.relative).Replace('\', '/')
    }
}

Write-JsonFile -Path $manifestPath -Data $manifest
Write-JsonFile -Path $clipsPath -Data $clipsRoot
Write-JsonFile -Path (Join-Path $packRoot 'Portraits\manifest.json') -Data ([ordered]@{ portraits = $portraitEntries })
Write-JsonFile -Path (Join-Path $packRoot 'Backdrops\Parallax\imported_manifest.json') -Data $parallaxManifest
Write-JsonFile -Path (Join-Path $packRoot 'TilesetSources\imported_manifest.json') -Data $tilesetManifest
Write-JsonFile -Path (Join-Path $packRoot 'Systems\AstralBodies\manifest.json') -Data $astralManifest
Write-JsonFile -Path (Join-Path $repoRoot 'Space\art\ships\noisey_4_17\manifest.json') -Data $shipManifest

[pscustomobject]@{
    music_ogg = $musicFiles.Count
    sfx_ogg = $sfxFiles.Count
    portraits_png = $portraitFiles.Count
    vfx_png = $vfxFiles.Count
    astral_png = $astralFiles.Count
    ship_png = $shipFiles.Count
    tileset_png = $tilesetPngs.Count
    parallax_png = $parallaxFiles.Count
} | Format-List
