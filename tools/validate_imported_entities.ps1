param(
    [string]$PackId = "demo"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$packRoot = Join-Path $repoRoot "Content\$PackId"
$entityPath = Join-Path $packRoot "Entities\entities.json"
$behaviorPath = Join-Path $packRoot "Entities\behaviors.json"

if (-not (Test-Path -LiteralPath $entityPath)) {
    throw "Missing entity registry: $entityPath"
}

function Get-JsonProperty($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Resolve-ContentPath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return "" }
    return Join-Path $packRoot ($RelativePath -replace '/', '\')
}

function Get-RelativePathCompat([string]$Root, [string]$Path) {
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $rootFull += [System.IO.Path]::DirectorySeparatorChar
    }
    $rootUri = New-Object System.Uri($rootFull)
    $pathUri = New-Object System.Uri([System.IO.Path]::GetFullPath($Path))
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString())
}

function Get-DirectPngCount([string]$DirPath) {
    if (-not (Test-Path -LiteralPath $DirPath)) { return 0 }
    return @(Get-ChildItem -LiteralPath $DirPath -File -Filter *.png -ErrorAction SilentlyContinue).Count
}

function Should-SkipSpriteSet([string]$RelativePath) {
    $lower = $RelativePath.ToLowerInvariant()
    foreach ($needle in @(
        "/presets/",
        "/vfx/",
        "/__macosx/",
        "macosx",
        "/psd",
        "_psd",
        "/default_player/"
    )) {
        if ($lower.Contains($needle)) { return $true }
    }
    return $false
}

$entitiesDoc = Get-Content -Raw -LiteralPath $entityPath | ConvertFrom-Json
$entities = @(Get-JsonProperty $entitiesDoc "entities" @())

$behaviorIds = @{}
if (Test-Path -LiteralPath $behaviorPath) {
    $behDoc = Get-Content -Raw -LiteralPath $behaviorPath | ConvertFrom-Json
    foreach ($behavior in @(Get-JsonProperty $behDoc "behaviors" @())) {
        $id = [string](Get-JsonProperty $behavior "id" "")
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $behaviorIds[$id] = $true
        }
    }
}

$seenEntityIds = @{}
$duplicateIds = New-Object System.Collections.Generic.List[string]
$missingSpriteSets = New-Object System.Collections.Generic.List[object]
$emptySpriteSets = New-Object System.Collections.Generic.List[object]
$missingBehaviors = New-Object System.Collections.Generic.List[object]
$categoryCounts = @{}
$referencedSpriteSets = @{}

foreach ($entity in $entities) {
    $id = [string](Get-JsonProperty $entity "id" "")
    if ($seenEntityIds.ContainsKey($id)) {
        $duplicateIds.Add($id)
    } else {
        $seenEntityIds[$id] = $true
    }

    $category = [string](Get-JsonProperty $entity "category" "")
    if ([string]::IsNullOrWhiteSpace($category)) { $category = "(missing)" }
    if (-not $categoryCounts.ContainsKey($category)) { $categoryCounts[$category] = 0 }
    $categoryCounts[$category] += 1

    $spriteSet = [string](Get-JsonProperty $entity "sprite_set" "")
    if (-not [string]::IsNullOrWhiteSpace($spriteSet)) {
        $referencedSpriteSets[$spriteSet] = $true
        $spritePath = Resolve-ContentPath $spriteSet
        if (-not (Test-Path -LiteralPath $spritePath)) {
            $missingSpriteSets.Add([pscustomobject]@{
                id = $id
                category = $category
                sprite_set = $spriteSet
            })
        } elseif ((Get-DirectPngCount $spritePath) -lt 1) {
            $emptySpriteSets.Add([pscustomobject]@{
                id = $id
                category = $category
                sprite_set = $spriteSet
            })
        }
    }

    $behavior = [string](Get-JsonProperty $entity "behavior" "")
    if (-not [string]::IsNullOrWhiteSpace($behavior) -and -not $behaviorIds.ContainsKey($behavior)) {
        $missingBehaviors.Add([pscustomobject]@{
            id = $id
            behavior = $behavior
        })
    }
}

$spriteRoot = Join-Path $packRoot "Sprites"
$spriteSetDirs = @()
if (Test-Path -LiteralPath $spriteRoot) {
    $spriteSetDirs = Get-ChildItem -LiteralPath $spriteRoot -Directory -Recurse |
        Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -File -Filter *.png -ErrorAction SilentlyContinue).Count -gt 0 }
}

$unreferencedSpriteSets = New-Object System.Collections.Generic.List[string]
foreach ($dir in $spriteSetDirs) {
    $rel = Get-RelativePathCompat $packRoot $dir.FullName
    if (Should-SkipSpriteSet $rel) { continue }
    if (-not $referencedSpriteSets.ContainsKey($rel)) {
        $unreferencedSpriteSets.Add($rel)
    }
}

Write-Host "Imported entity validation for pack '$PackId'"
Write-Host "entities=$($entities.Count)"
foreach ($key in ($categoryCounts.Keys | Sort-Object)) {
    Write-Host ("category.{0}={1}" -f $key, $categoryCounts[$key])
}
Write-Host "sprite_sets_on_disk=$($spriteSetDirs.Count)"
Write-Host "missing_sprite_sets=$($missingSpriteSets.Count)"
Write-Host "empty_sprite_sets=$($emptySpriteSets.Count)"
Write-Host "unreferenced_sprite_sets=$($unreferencedSpriteSets.Count)"
Write-Host "duplicate_entity_ids=$($duplicateIds.Count)"
Write-Host "unknown_behaviors=$($missingBehaviors.Count)"

if ($missingSpriteSets.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing sprite_set samples:"
    $missingSpriteSets | Select-Object -First 20 | Format-Table -AutoSize
}

if ($emptySpriteSets.Count -gt 0) {
    Write-Host ""
    Write-Host "Empty sprite_set samples:"
    $emptySpriteSets | Select-Object -First 20 | Format-Table -AutoSize
}

if ($missingBehaviors.Count -gt 0) {
    Write-Host ""
    Write-Host "Unknown behavior samples:"
    $missingBehaviors | Select-Object -First 20 | Format-Table -AutoSize
}

if ($unreferencedSpriteSets.Count -gt 0) {
    Write-Host ""
    Write-Host "Unreferenced sprite_set samples:"
    $unreferencedSpriteSets | Sort-Object | Select-Object -First 30
}

if ($missingSpriteSets.Count -gt 0 -or $emptySpriteSets.Count -gt 0 -or
        $duplicateIds.Count -gt 0 -or $missingBehaviors.Count -gt 0) {
    exit 1
}
