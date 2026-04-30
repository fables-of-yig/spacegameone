param(
    [string]$PackId = "demo",
    [switch]$GenerateMissing,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$packRoot = Join-Path $repoRoot "Content\$PackId"
$entityPath = Join-Path $packRoot "Entities\entities.json"

if (-not (Test-Path -LiteralPath $entityPath)) {
    throw "Missing entity registry: $entityPath"
}

function Normalize-Slug([string]$Text) {
    $lower = $Text.ToLowerInvariant()
    $clean = [regex]::Replace($lower, '[^a-z0-9]+', '_')
    return $clean.Trim('_')
}

function ConvertTo-OrderedData($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $out[$key] = ConvertTo-OrderedData $Value[$key]
        }
        return $out
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(ConvertTo-OrderedData $item)
        }
        return $items
    }
    if ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and $Value -isnot [string]) {
        $out = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) {
            $out[$prop.Name] = ConvertTo-OrderedData $prop.Value
        }
        return $out
    }
    return $Value
}

function Get-Entry($Dict, [string]$Key, $Default = $null) {
    if ($null -eq $Dict) { return $Default }
    if ($Dict -is [System.Collections.IDictionary] -and $Dict.Contains($Key)) {
        return $Dict[$Key]
    }
    return $Default
}

function Set-Entry($Dict, [string]$Key, $Value) {
    if ($Dict -isnot [System.Collections.IDictionary]) { return }
    $Dict[$Key] = $Value
}

function Get-RelativeContentPath([string]$FullPath) {
    $rootFull = [System.IO.Path]::GetFullPath($packRoot)
    if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $rootFull += [System.IO.Path]::DirectorySeparatorChar
    }
    $rootUri = New-Object System.Uri($rootFull)
    $pathUri = New-Object System.Uri([System.IO.Path]::GetFullPath($FullPath))
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString())
}

function Resolve-ContentPath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return "" }
    return Join-Path $packRoot ($RelativePath -replace '/', '\')
}

function Test-SpriteSetExists([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
    $full = Resolve-ContentPath $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { return $false }
    return @(Get-ChildItem -LiteralPath $full -File -Filter *.png -ErrorAction SilentlyContinue).Count -gt 0
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

function Get-CanonicalAnimationStates([string]$SpriteDir) {
    $states = New-Object System.Collections.Generic.List[string]
    foreach ($png in Get-ChildItem -LiteralPath $SpriteDir -File -Filter *.png -ErrorAction SilentlyContinue) {
        $name = $png.BaseName.ToLowerInvariant()
        if ($name -match 'death|dying|defeat|\bdie\b') { $states.Add("death"); continue }
        if ($name -match 'hithurt|hurt|\bhit\b|damage') { $states.Add("hurt"); continue }
        if ($name -match 'attack|shoot|slash|cast|throw|stab|punch|kick|bite|fire|spit|breath') { $states.Add("attack"); continue }
        if ($name -match 'jump|rise|upward') { $states.Add("jump"); continue }
        if ($name -match 'fall|inair|drop|air') { $states.Add("fall"); continue }
        if ($name -match 'flying|float|\bfly\b|hover') { $states.Add("fly"); continue }
        if ($name -match 'walk|run|chase|gallop|crawl|dash|move') { $states.Add("walk"); continue }
        if ($name -match 'appear|spawn|vanish|rise') { $states.Add("spawn"); continue }
        if ($name -match 'idle|stand|wait|front|hang') { $states.Add("idle"); continue }
    }
    return @($states | Select-Object -Unique)
}

function ConvertTo-Title([string]$Text) {
    $slug = Normalize-Slug $Text
    if ([string]::IsNullOrWhiteSpace($slug)) { return "" }
    $words = @()
    foreach ($part in ($slug -split '_')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $words += $part.Substring(0, 1).ToUpperInvariant() + $part.Substring(1)
    }
    return ($words -join " ")
}

function Get-ThemeName([string]$LeafName) {
    $tokens = @((Normalize-Slug $LeafName) -split '_' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $noise = @{
        "enemy" = $true; "enemies" = $true; "boss" = $true; "bosses" = $true
        "pixel" = $true; "art" = $true; "sprite" = $true; "sprites" = $true
        "sheet" = $true; "sheets" = $true; "pack" = $true; "game" = $true
        "asset" = $true; "assets" = $true; "character" = $true; "characters" = $true
        "png" = $true; "files" = $true; "from" = $true; "for" = $true
    }
    $kept = @()
    foreach ($token in $tokens) {
        if ($token -match '^\d+$') { continue }
        if ($noise.ContainsKey($token)) { continue }
        if ($kept -contains $token) { continue }
        $kept += $token
        if ($kept.Count -ge 3) { break }
    }
    if ($kept.Count -eq 0) {
        $kept = @($tokens | Select-Object -First 2)
    }
    return ConvertTo-Title ($kept -join "_")
}

function Get-CategoryForSpriteSet([string]$RelativePath, [string[]]$States) {
    $lower = $RelativePath.ToLowerInvariant()
    if ($lower -match 'death|explosion|impact|muzzle|fireball|projectile|venom|shuriken|fx|vfx') {
        return "fx"
    }
    if ($lower -match 'coin|coins|key|keys|chest|money|card|pickup|collect') {
        return "pickup"
    }
    if ($lower -match 'boss') {
        return "boss"
    }
    if ($lower -match 'playable') {
        return "enemy"
    }
    if ($lower -match '/002_npcs/' -or $lower -match 'npc|civilian|crowd|peasant|villager|trader|shop|vendor|scientist|worker|blacksmith|oldman|old_woman|woman|annette|forgeron') {
        return "interactable"
    }
    return "enemy"
}

function Get-MovementMode([string]$RelativePath, [string[]]$States) {
    $lower = $RelativePath.ToLowerInvariant()
    if ($States -contains "fly" -or $lower -match 'bat|ghost|crow|vulture|dragon|angel|skull|flying|eye_demon|gargoyle|beholder') {
        return "fly"
    }
    return "ground"
}

function Get-BehaviorId([string]$Category, [string]$MovementMode, [string[]]$States, [string]$RelativePath) {
    if ($Category -eq "interactable" -or $Category -eq "pickup" -or $Category -eq "fx") { return "" }
    if ($Category -eq "boss") { return "boss_phased" }
    $joined = (($States + @($RelativePath)) -join " ").ToLowerInvariant()
    if ($joined -match 'shoot|cast|wizard|mage|sorcerer|warlock|skull|shuriken|rifle|gun|shotgun|turret') {
        if ($MovementMode -ne "ground") { return "flyer_ranged" }
        if (($States -contains "walk") -or ($States -contains "idle")) { return "ranged_attacker" }
        return "stationary_attacker"
    }
    if ($MovementMode -ne "ground") { return "flyer_basic" }
    if ($joined -match 'jump|toad|slime|imp|amphibean') { return "jumper" }
    if ($States -contains "attack") { return "melee_aggressive" }
    return "patrol_basic"
}

function Get-DefaultStats([string]$Category, [string]$BehaviorId, [string]$MovementMode) {
    if ($Category -eq "interactable") {
        return @{
            hp = 1; attack_damage = 0; contact_damage = 0; contact_cooldown = 0.8
            move_speed = 40; projectile_damage = 0; projectile_speed = 160
            melee_range = 24; projectile_range = 160
        }
    }
    if ($Category -eq "pickup" -or $Category -eq "fx") {
        return @{
            hp = 1; attack_damage = 0; contact_damage = 0; contact_cooldown = 0.8
            move_speed = 0; projectile_damage = 0; projectile_speed = 0
            melee_range = 0; projectile_range = 0
        }
    }
    if ($Category -eq "boss") {
        return @{
            hp = 120; attack_damage = 5; contact_damage = 2; contact_cooldown = 0.8
            move_speed = if ($MovementMode -eq "ground") { 44 } else { 56 }
            projectile_damage = 4; projectile_speed = 160
            melee_range = 40; projectile_range = 260
        }
    }
    switch ($BehaviorId) {
        "flyer_ranged" { return @{ hp = 10; attack_damage = 1; contact_damage = 1; contact_cooldown = 0.8; move_speed = 58; projectile_damage = 3; projectile_speed = 180; melee_range = 24; projectile_range = 220 } }
        "flyer_basic" { return @{ hp = 8; attack_damage = 2; contact_damage = 1; contact_cooldown = 0.8; move_speed = 54; projectile_damage = 0; projectile_speed = 180; melee_range = 28; projectile_range = 180 } }
        "jumper" { return @{ hp = 14; attack_damage = 2; contact_damage = 1; contact_cooldown = 0.8; move_speed = 42; projectile_damage = 0; projectile_speed = 180; melee_range = 30; projectile_range = 180 } }
        "ranged_attacker" { return @{ hp = 16; attack_damage = 1; contact_damage = 1; contact_cooldown = 0.8; move_speed = 38; projectile_damage = 3; projectile_speed = 180; melee_range = 24; projectile_range = 220 } }
        "stationary_attacker" { return @{ hp = 18; attack_damage = 2; contact_damage = 0; contact_cooldown = 0.8; move_speed = 0; projectile_damage = 3; projectile_speed = 170; melee_range = 30; projectile_range = 240 } }
        "melee_aggressive" { return @{ hp = 24; attack_damage = 3; contact_damage = 1; contact_cooldown = 0.8; move_speed = 48; projectile_damage = 0; projectile_speed = 180; melee_range = 34; projectile_range = 180 } }
        default { return @{ hp = 12; attack_damage = 1; contact_damage = 1; contact_cooldown = 0.8; move_speed = 34; projectile_damage = 0; projectile_speed = 180; melee_range = 24; projectile_range = 180 } }
    }
}

function Get-PlacementFolder([string]$Category, [string]$RelativePath) {
    $leaf = Split-Path -Leaf ($RelativePath -replace '/', '\')
    $theme = Get-ThemeName $leaf
    if ([string]::IsNullOrWhiteSpace($theme)) { $theme = "Imported" }
    switch ($Category) {
        "boss" { return "Bosses/$theme" }
        "interactable" { return "NPCs/$theme" }
        "pickup" { return "Pickups/$theme" }
        "fx" { return "FX/$theme" }
        default { return "Enemies/$theme" }
    }
}

function New-EntityRecord([object]$SpriteSet) {
    $entityId = Normalize-Slug $SpriteSet.Leaf
    $category = Get-CategoryForSpriteSet $SpriteSet.Rel $SpriteSet.States
    $movementMode = if ($category -eq "interactable" -or $category -eq "pickup" -or $category -eq "fx") { "ground" } else { Get-MovementMode $SpriteSet.Rel $SpriteSet.States }
    $behavior = Get-BehaviorId $category $movementMode $SpriteSet.States $SpriteSet.Rel
    $stats = Get-DefaultStats $category $behavior $movementMode
    return [ordered]@{
        category = $category
        id = $entityId
        name = ConvertTo-Title $entityId
        description = "Generated imported entity from $($SpriteSet.Rel)"
        scene = if ($category -eq "interactable") { "res://Scenes/NPC.tscn" } else { "res://Scenes/Enemy.tscn" }
        sprite_set = $SpriteSet.Rel
        behavior = $behavior
        movement_mode = $movementMode
        hp = $stats.hp
        attack_damage = $stats.attack_damage
        contact_damage = $stats.contact_damage
        contact_cooldown = $stats.contact_cooldown
        move_speed = $stats.move_speed
        projectile_damage = $stats.projectile_damage
        projectile_speed = $stats.projectile_speed
        melee_range = $stats.melee_range
        melee_attack_trigger_frame = -1
        projectile_range = $stats.projectile_range
        projectile_attack_trigger_frame = -1
        placement_folder = Get-PlacementFolder $category $SpriteSet.Rel
        source_pack = $SpriteSet.Leaf
        import_status = "linked"
    }
}

function Add-DefaultRuntimeFields($Entity, [string]$Category, [string]$Behavior, [string]$MovementMode) {
    $stats = Get-DefaultStats $Category $Behavior $MovementMode
    foreach ($key in @("hp", "attack_damage", "contact_damage", "contact_cooldown",
            "move_speed", "projectile_damage", "projectile_speed", "melee_range",
            "projectile_range")) {
        if ($null -eq (Get-Entry $Entity $key $null)) {
            Set-Entry $Entity $key $stats[$key]
        }
    }
    if ($null -eq (Get-Entry $Entity "melee_attack_trigger_frame" $null)) {
        Set-Entry $Entity "melee_attack_trigger_frame" -1
    }
    if ($null -eq (Get-Entry $Entity "projectile_attack_trigger_frame" $null)) {
        Set-Entry $Entity "projectile_attack_trigger_frame" -1
    }
}

function Score-Candidate($Entity, $Candidate, [string]$WantedLeaf, [string]$Category) {
    $score = 0
    $id = [string](Get-Entry $Entity "id" "")
    if ($Candidate.Leaf -eq $WantedLeaf) { $score += 1000 }
    if ($Candidate.Leaf -eq $id) { $score += 800 }
    if ($Category -eq "interactable" -and $Candidate.Rel.StartsWith("Sprites/002_NPCs/")) { $score += 100 }
    if (($Category -eq "enemy" -or $Category -eq "boss") -and $Candidate.Rel.StartsWith("Sprites/001_Enemies/")) { $score += 100 }
    if ($Category -eq "boss" -and $Candidate.Rel.ToLowerInvariant().Contains("boss")) { $score += 50 }
    $score -= [Math]::Min(200, $Candidate.Rel.Length)
    return $score
}

$raw = Get-Content -Raw -LiteralPath $entityPath | ConvertFrom-Json
$entitiesDoc = ConvertTo-OrderedData $raw
$entities = @(Get-Entry $entitiesDoc "entities" @())

$spriteSets = New-Object System.Collections.Generic.List[object]
$spriteRoot = Join-Path $packRoot "Sprites"
if (Test-Path -LiteralPath $spriteRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $spriteRoot -Directory -Recurse) {
        $directPngs = @(Get-ChildItem -LiteralPath $dir.FullName -File -Filter *.png -ErrorAction SilentlyContinue)
        if ($directPngs.Count -lt 1) { continue }
        $rel = Get-RelativeContentPath $dir.FullName
        if (Should-SkipSpriteSet $rel) { continue }
        $spriteSets.Add([pscustomobject]@{
            Rel = $rel
            Leaf = (Split-Path -Leaf $dir.FullName)
            FullName = $dir.FullName
            States = @(Get-CanonicalAnimationStates $dir.FullName)
        })
    }
}

$byLeaf = @{}
foreach ($set in $spriteSets) {
    if (-not $byLeaf.ContainsKey($set.Leaf)) {
        $byLeaf[$set.Leaf] = New-Object System.Collections.Generic.List[object]
    }
    $byLeaf[$set.Leaf].Add($set)
}

$existingIds = @{}
$referencedSpriteSets = @{}
$relinked = 0
$metadataUpdated = 0
$unresolved = New-Object System.Collections.Generic.List[object]

foreach ($entity in $entities) {
    $id = [string](Get-Entry $entity "id" "")
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        $existingIds[$id] = $true
    }
    $category = [string](Get-Entry $entity "category" "enemy")
    $spriteSet = [string](Get-Entry $entity "sprite_set" "")
    $finalSpriteSet = $spriteSet

    if (-not [string]::IsNullOrWhiteSpace($spriteSet) -and -not (Test-SpriteSetExists $spriteSet)) {
        $wantedLeaf = Split-Path -Leaf ($spriteSet -replace '/', '\')
        $candidates = @()
        if ($byLeaf.ContainsKey($wantedLeaf)) { $candidates += @($byLeaf[$wantedLeaf]) }
        if ($byLeaf.ContainsKey($id)) { $candidates += @($byLeaf[$id]) }
        $candidates = @($candidates | Sort-Object Rel -Unique)
        if ($candidates.Count -gt 0) {
            $best = $candidates |
                Sort-Object @{ Expression = { Score-Candidate $entity $_ $wantedLeaf $category }; Descending = $true } |
                Select-Object -First 1
            $finalSpriteSet = $best.Rel
            Set-Entry $entity "sprite_set" $finalSpriteSet
            $relinked += 1
        } else {
            Set-Entry $entity "missing_sprite_set" $spriteSet
            Set-Entry $entity "sprite_set" ""
            $finalSpriteSet = ""
            Set-Entry $entity "import_status" "missing_sprite"
            $unresolved.Add([pscustomobject]@{
                id = $id
                category = $category
                sprite_set = $spriteSet
            })
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($finalSpriteSet) -and (Test-SpriteSetExists $finalSpriteSet)) {
        $leaf = Split-Path -Leaf ($finalSpriteSet -replace '/', '\')
        $states = @()
        $matchingSet = $spriteSets | Where-Object { $_.Rel -eq $finalSpriteSet } | Select-Object -First 1
        if ($matchingSet) { $states = @($matchingSet.States) }
        $movementMode = [string](Get-Entry $entity "movement_mode" "")
        if ([string]::IsNullOrWhiteSpace($movementMode)) {
            $movementMode = if ($category -eq "interactable") { "ground" } else { Get-MovementMode $finalSpriteSet $states }
            Set-Entry $entity "movement_mode" $movementMode
        }
        $behavior = [string](Get-Entry $entity "behavior" "")
        if ([string]::IsNullOrWhiteSpace($behavior) -and $category -ne "interactable" -and $category -ne "pickup" -and $category -ne "fx") {
            $behavior = Get-BehaviorId $category $movementMode $states $finalSpriteSet
            Set-Entry $entity "behavior" $behavior
        }
        Add-DefaultRuntimeFields $entity $category $behavior $movementMode
        Set-Entry $entity "placement_folder" (Get-PlacementFolder $category $finalSpriteSet)
        Set-Entry $entity "source_pack" $leaf
        Set-Entry $entity "import_status" "linked"
        $referencedSpriteSets[$finalSpriteSet] = $true
        $metadataUpdated += 1
    } elseif ([string]::IsNullOrWhiteSpace([string](Get-Entry $entity "placement_folder" ""))) {
        if ([string](Get-Entry $entity "import_status" "") -eq "missing_sprite") {
            Set-Entry $entity "placement_folder" "Review/Missing Sprites"
        } else {
            switch ($category) {
                "boss" { Set-Entry $entity "placement_folder" "Core/Bosses" }
                "enemy" { Set-Entry $entity "placement_folder" "Core/Enemies" }
                "interactable" { Set-Entry $entity "placement_folder" "Core/NPCs" }
                "pickup" { Set-Entry $entity "placement_folder" "Core/Pickups" }
                "logic" { Set-Entry $entity "placement_folder" "Core/Logic" }
                default { Set-Entry $entity "placement_folder" "Core/Other" }
            }
        }
    }
}

$generated = 0
if ($GenerateMissing) {
    foreach ($set in $spriteSets) {
        if ($referencedSpriteSets.ContainsKey($set.Rel)) { continue }
        $entity = New-EntityRecord $set
        $entityId = [string](Get-Entry $entity "id" "")
        if ([string]::IsNullOrWhiteSpace($entityId)) { continue }
        if ($existingIds.ContainsKey($entityId)) {
            $suffix = Normalize-Slug (($set.Rel -replace '^Sprites/', '') -replace '/', '_')
            $entityId = $suffix
            Set-Entry $entity "id" $entityId
            Set-Entry $entity "name" (ConvertTo-Title $entityId)
        }
        if ($existingIds.ContainsKey($entityId)) { continue }
        $entities += ,$entity
        $existingIds[$entityId] = $true
        $referencedSpriteSets[$set.Rel] = $true
        $generated += 1
    }
}

$entities = @($entities | Sort-Object `
    @{ Expression = { [string](Get-Entry $_ "category" "") } }, `
    @{ Expression = { [string](Get-Entry $_ "placement_folder" "") } }, `
    @{ Expression = { [string](Get-Entry $_ "id" "") } })

Set-Entry $entitiesDoc "entities" $entities

Write-Host "Relink imported entity sprite sets for pack '$PackId'"
Write-Host "sprite_sets_found=$($spriteSets.Count)"
Write-Host "relinked=$relinked"
Write-Host "metadata_updated=$metadataUpdated"
Write-Host "generated=$generated"
Write-Host "unresolved=$($unresolved.Count)"

if ($unresolved.Count -gt 0) {
    Write-Host ""
    Write-Host "Unresolved samples:"
    $unresolved | Select-Object -First 30 | Format-Table -AutoSize
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to write $entityPath"
    exit 0
}

$json = $entitiesDoc | ConvertTo-Json -Depth 20
Set-Content -LiteralPath $entityPath -Encoding UTF8 -Value $json
Write-Host "Wrote $entityPath"
