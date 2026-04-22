param(
    [string]$SourceRoot = "D:\SPaceAssetsNoisey\4-17\characters\Non-Player Characters",
    [string]$PackId = "demo"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

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

function Join-SlugParts([string[]]$Parts) {
    $filtered = @()
    foreach ($part in $Parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $slug = Normalize-Slug $part
        if ($slug -in @("characters", "npc_and_enemies", "npc", "enemies", "playable_characters", "sprites", "spritesheet", "spritesheets", "png")) {
            continue
        }
        $filtered += $slug
    }
    return ($filtered -join "_").Trim("_")
}

function Shorten-EntityId([string]$EntityId) {
    if ($EntityId.Length -le 64) { return $EntityId }
    $parts = @($EntityId -split '_')
    if ($parts.Count -ge 4) {
        $short = (($parts[0..1] + $parts[($parts.Count - 2)..($parts.Count - 1)]) -join "_").Trim("_")
        if ($short.Length -gt 0) { return $short }
    }
    return $EntityId.Substring(0, 64).Trim('_')
}

function Get-RelativePath([string]$Root, [string]$Path) {
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $rootFull += [System.IO.Path]::DirectorySeparatorChar
    }
    $rootUri = New-Object System.Uri($rootFull)
    $pathUri = New-Object System.Uri([System.IO.Path]::GetFullPath($Path))
    $relative = $rootUri.MakeRelativeUri($pathUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Should-SkipPng([string]$Path) {
    $lower = $Path.ToLowerInvariant()
    foreach ($needle in @("\preview\", "\previews\", "\gif\", "\gifs\", "\psd\", "\spritesseparated\", "\effects\", "\demo\", "\sheet file\", "\example\", "\icons\", "\icon\", "\weapon\", "\constructor\", "\vehicle\", "\tileset\", "\tilesets\", "\props\")) {
        if ($lower.Contains($needle)) {
            return $true
        }
    }
    if ($lower.Contains("\__macosx\")) { return $true }
    if ($lower.Contains("\aliens-avatar-game-icons\")) { return $true }
    if ($lower.Contains("\gun-constructor-pixel-art\")) { return $true }
    if ($lower.Contains("\bike-constructor-pixel-art\")) { return $true }
    if ($lower.Contains("\car-constructor-pixel-art\")) { return $true }
    return $false
}

function Get-CanonicalAnimation([string]$Text) {
    $lower = $Text.ToLowerInvariant()
    if ($lower -match 'death|dying|defeat|\bdie\b') { return "death" }
    if ($lower -match 'hithurt|hurt|\bhit\b|damage') { return "hurt" }
    if ($lower -match 'attack|shoot|slash|cast|throw|stab|punch|kick|bite') { return "attack" }
    if ($lower -match 'firebreath|breath|venom|poison|shuriken|fireball|projectile|bolt|blast|spit|shot') { return "special" }
    if ($lower -match 'doublejump|jump|rise|upward') { return "jump" }
    if ($lower -match 'fall|inair|drop|air') { return "fall" }
    if ($lower -match 'flying|float|\bfly\b|hover') { return "fly" }
    if ($lower -match 'walk|run|chase|gallop|crawl|dash|move') { return "walk" }
    if ($lower -match 'appear|spawn|vanish|rise') { return "spawn" }
    if ($lower -match 'crouch') { return "crouch" }
    if ($lower -match 'idle|stand|wait|front|hang') { return "idle" }
    return $null
}

function Get-ImageInfo([string]$Path) {
    $img = [System.Drawing.Image]::FromFile($Path)
    try {
        [pscustomobject]@{
            Width = $img.Width
            Height = $img.Height
        }
    } finally {
        $img.Dispose()
    }
}

function Get-FrameCount([string]$Path) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $stripMatch = [regex]::Match($name, '_strip(\d+)$', 'IgnoreCase')
    if ($stripMatch.Success) {
        return [int]$stripMatch.Groups[1].Value
    }
    $info = Get-ImageInfo $Path
    if ($info.Height -gt 0 -and $info.Width -ge $info.Height) {
        return [Math]::Max(1, [int]([math]::Floor($info.Width / $info.Height)))
    }
    return 1
}

function Get-NaturalNumber([string]$Name) {
    $match = [regex]::Match($Name, '(\d+)')
    if ($match.Success) { return [int]$match.Groups[1].Value }
    return 0
}

function Stitch-FramesToStrip([string[]]$Frames, [string]$DestPath) {
    if ($Frames.Count -eq 0) { return $null }
    $ordered = $Frames | Sort-Object @{ Expression = { Get-NaturalNumber $_ } }, @{ Expression = { $_ } }
    $bitmaps = @()
    $maxWidth = 0
    $maxHeight = 0
    foreach ($frame in $ordered) {
        try {
            $img = [System.Drawing.Image]::FromFile($frame)
        } catch {
            Write-Warning "Skipping unreadable frame: $frame"
            continue
        }
        $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $copyGraphics = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $copyGraphics.DrawImage($img, 0, 0, $img.Width, $img.Height)
        } finally {
            $copyGraphics.Dispose()
            $img.Dispose()
        }
        $bitmaps += $bmp
        if ($bmp.Width -gt $maxWidth) { $maxWidth = $bmp.Width }
        if ($bmp.Height -gt $maxHeight) { $maxHeight = $bmp.Height }
    }
    if (@($bitmaps).Count -eq 0) { return $null }
    $stripWidth = [int]$maxWidth * [int](@($bitmaps).Count)
    $strip = New-Object System.Drawing.Bitmap($stripWidth, [int]$maxHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($strip)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        for ($i = 0; $i -lt @($bitmaps).Count; $i++) {
            $bmp = $bitmaps[$i]
            $x = ($i * $maxWidth) + [int](($maxWidth - $bmp.Width) / 2)
            $y = $maxHeight - $bmp.Height
            $graphics.DrawImage($bmp, $x, $y, $bmp.Width, $bmp.Height)
        }
        if (Test-Path $DestPath) {
            Remove-Item -Force -LiteralPath $DestPath
        }
        try {
            $strip.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } catch {
            Write-Warning "Failed to save stitched strip: $DestPath"
            return $null
        }
    } finally {
        $graphics.Dispose()
        $strip.Dispose()
        foreach ($bmp in $bitmaps) { $bmp.Dispose() }
    }
    return [pscustomobject]@{
        Frames = @($ordered).Count
        Width = $maxWidth
        Height = $maxHeight
    }
}

function Collect-AnimationCandidates([string]$Root, [string]$MatchPrefix = "") {
    $groups = @{}
    $files = Get-ChildItem -Path $Root -Recurse -File -Include *.png |
        Where-Object { -not (Should-SkipPng $_.FullName) }
    foreach ($file in $files) {
        if ($MatchPrefix) {
            $joined = ($file.BaseName + " " + $file.Directory.Name).ToLowerInvariant()
            if (-not $joined.Contains($MatchPrefix.ToLowerInvariant())) { continue }
        }
        $state = Get-CanonicalAnimation -Text ($file.BaseName + " " + $file.Directory.Name)
        if (-not $state) { continue }
        if (-not $groups.ContainsKey($state)) {
            $groups[$state] = [ordered]@{
                StripCandidates = New-Object System.Collections.Generic.List[object]
                Frames = New-Object System.Collections.Generic.List[string]
            }
        }
        $lowerDir = $file.DirectoryName.ToLowerInvariant()
        $isStrip = $file.Name -match '_strip\d+\.png$' -or $lowerDir.Contains("spritesheet") -or $file.BaseName.ToLowerInvariant().Contains("sheet")
        if ($isStrip) {
            $frameCount = Get-FrameCount $file.FullName
            $groups[$state].StripCandidates.Add([pscustomobject]@{
                Path = $file.FullName
                Frames = $frameCount
                Score = $frameCount * 100000 + $file.Length
            })
        } else {
            $groups[$state].Frames.Add($file.FullName)
        }
    }
    return $groups
}

function Export-SpriteSet([string]$Root, [string]$PackId, [string]$EntityId, [string]$MatchPrefix = "") {
    $spriteSetRel = "Sprites/$EntityId"
    $destDir = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Content\$PackId\Sprites") -ChildPath $EntityId
    $destDir = [System.IO.Path]::GetFullPath($destDir)
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $groups = Collect-AnimationCandidates -Root $Root -MatchPrefix $MatchPrefix
    $poses = [ordered]@{ poses = [ordered]@{} }
    $exported = @()
    foreach ($state in ($groups.Keys | Sort-Object)) {
        $destPng = Join-Path $destDir "$state.png"
        $pose = [ordered]@{
            fps = if ($state -in @("attack", "special", "jump", "death", "hurt", "spawn")) { 10 } else { 8 }
            loop_from = 0
        }
        $frameCount = 1
        if ($groups[$state].StripCandidates.Count -gt 0) {
            $chosen = $groups[$state].StripCandidates | Sort-Object Score -Descending | Select-Object -First 1
            Copy-Item -Force -LiteralPath $chosen.Path -Destination $destPng
            $frameCount = [int]$chosen.Frames
        } elseif ($groups[$state].Frames.Count -gt 0) {
            $stripInfo = Stitch-FramesToStrip -Frames @($groups[$state].Frames) -DestPath $destPng
            if (-not $stripInfo) { continue }
            $frameCount = [int]$stripInfo.Frames
        } else {
            continue
        }
        $pose.frames = $frameCount
        $poses.poses["$state.png"] = $pose
        $exported += $state
    }
    if ($exported.Count -eq 0) { return $null }
    $posesPath = Join-Path $destDir "poses.json"
    $poses | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $posesPath
    return [pscustomobject]@{
        SpriteSet = $spriteSetRel
        ExportedStates = $exported
    }
}

function Get-BehaviorId([string]$Category, [string]$MovementMode, [string[]]$States, [string]$SourcePath) {
    $joined = (($States + @($SourcePath)) -join " ").ToLowerInvariant()
    if ($Category -eq "interactable") { return "npc_idle" }
    if ($Category -eq "boss") { return "boss_phased" }
    if ($joined -match 'shoot|cast|wizard|mage|sorcerer|warlock|skull|shuriken|rifle|gun|shotgun') {
        if ($MovementMode -ne "ground") {
            return "flyer_ranged"
        }
        if (($States -contains "walk") -or ($States -contains "idle")) {
            return "ranged_attacker"
        }
        return "stationary_attacker"
    }
    if ($MovementMode -ne "ground") {
        return "flyer_basic"
    }
    if ($joined -match 'jump|toad|slime|imp|amphibean') { return "jumper" }
    if ($joined -match 'spider|hell_beast|fireball') {
        if (($States -contains "walk") -or ($States -contains "idle")) {
            return "ranged_attacker"
        }
        return "stationary_attacker"
    }
    if ($States -contains "attack" -or $States -contains "special") { return "melee_aggressive" }
    return "patrol_basic"
}

function Get-MovementMode([string]$SourcePath, [string[]]$States) {
    $lower = $SourcePath.ToLowerInvariant()
    if ($States -contains "fly" -or $lower -match 'bat|ghost|crow|vulture|dragon|angel|fire_skull|flying|eye_demon|gargoyle|skull') {
        return "fly"
    }
    return "ground"
}

function Get-Category([string]$SourcePath) {
    $lower = $SourcePath.ToLowerInvariant()
    $parts = @($SourcePath -split '[\\/]') |
        Where-Object {
            $_ -and $_.Trim() -and $_.ToLowerInvariant() -notin @(
                "characters", "npc and enemies", "npc", "enemies",
                "playable characters", "enemy_sprites", "sprites", "spritesheets", "png"
            )
        }
    $keyText = (($parts | Select-Object -Last 4) -join " ").ToLowerInvariant()
    if ($keyText -match 'enemy death|fireballattack|\\bfx\\b|enemy-death|fireball|venom|shuriken') { return "fx" }
    if ($lower.Contains("playable characters")) { return "enemy" }
    if ($keyText -match 'boss') { return "boss" }
    if ($keyText -match '\bnpc\b|old woman|young woman|villager|civilian|crowd|peasant|scientist|worker|trader|blacksmith|oldman|annette|bearded|hat-man|forgeron') {
        return "interactable"
    }
    return "enemy"
}

function Get-DefaultStats([string]$Category, [string]$BehaviorId, [string]$MovementMode) {
    if ($Category -eq "interactable") {
        return @{
            hp = 1; attack_damage = 0; contact_damage = 0; contact_cooldown = 0.8
            move_speed = 40; projectile_damage = 0; projectile_speed = 160
        }
    }
    if ($Category -eq "boss") {
        return @{
            hp = 120; attack_damage = 5; contact_damage = 2; contact_cooldown = 0.8
            move_speed = if ($MovementMode -eq "ground") { 44 } else { 56 }
            projectile_damage = 4; projectile_speed = 160
        }
    }
    switch ($BehaviorId) {
        "flyer_ranged" { return @{ hp = 10; attack_damage = 1; contact_damage = 1; contact_cooldown = 0.8; move_speed = 58; projectile_damage = 3; projectile_speed = 180 } }
        "flyer_basic" { return @{ hp = 8; attack_damage = 2; contact_damage = 1; contact_cooldown = 0.8; move_speed = 54; projectile_damage = 0; projectile_speed = 180 } }
        "jumper" { return @{ hp = 14; attack_damage = 2; contact_damage = 1; contact_cooldown = 0.8; move_speed = 42; projectile_damage = 0; projectile_speed = 180 } }
        "ranged_attacker" { return @{ hp = 16; attack_damage = 1; contact_damage = 1; contact_cooldown = 0.8; move_speed = 38; projectile_damage = 3; projectile_speed = 180 } }
        "stationary_attacker" { return @{ hp = 18; attack_damage = 2; contact_damage = 0; contact_cooldown = 0.8; move_speed = 0; projectile_damage = 3; projectile_speed = 170 } }
        "melee_aggressive" { return @{ hp = 24; attack_damage = 3; contact_damage = 1; contact_cooldown = 0.8; move_speed = 48; projectile_damage = 0; projectile_speed = 180 } }
        default { return @{ hp = 12; attack_damage = 1; contact_damage = 1; contact_cooldown = 0.8; move_speed = 34; projectile_damage = 0; projectile_speed = 180 } }
    }
}

function New-EntityRecord([string]$EntityId, [string]$SourcePath, [string]$SpriteSet, [string[]]$States) {
    $category = Get-Category $SourcePath
    if ($category -eq "fx") { return $null }
    $movementMode = if ($category -eq "interactable") { "ground" } else { Get-MovementMode -SourcePath $SourcePath -States $States }
    $behaviorId = Get-BehaviorId -Category $category -MovementMode $movementMode -States $States -SourcePath $SourcePath
    $stats = Get-DefaultStats -Category $category -BehaviorId $behaviorId -MovementMode $movementMode
    return [ordered]@{
        category = $category
        id = $EntityId
        name = (($EntityId -split "_") | ForEach-Object { if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } }) -join " "
        description = "Imported default entity from $(Get-RelativePath $SourceRoot $SourcePath)"
        scene = if ($category -eq "interactable") { "res://Scenes/NPC.tscn" } elseif ($category -eq "boss") { "res://Scenes/Enemy.tscn" } else { "res://Scenes/Enemy.tscn" }
        sprite_set = $SpriteSet
        behavior = if ($category -eq "interactable") { "" } else { $behaviorId }
        movement_mode = $movementMode
        hp = $stats.hp
        attack_damage = $stats.attack_damage
        contact_damage = $stats.contact_damage
        contact_cooldown = $stats.contact_cooldown
        move_speed = $stats.move_speed
        projectile_damage = $stats.projectile_damage
        projectile_speed = $stats.projectile_speed
    }
}

function Add-RootSpec($list, [string]$Path, [string]$IdOverride = "", [string]$Prefix = "", [string]$MatchPrefix = "") {
    if (-not (Test-Path $Path)) { return }
    $null = $list.Add([pscustomobject]@{
        Path = $Path
        IdOverride = $IdOverride
        Prefix = $Prefix
        MatchPrefix = $MatchPrefix
    })
}

function Get-RootSpecs([string]$SourceRoot) {
    $roots = New-Object System.Collections.Generic.List[object]
    foreach ($name in @(
        "annette-sprites-v1",
        "bluemagestaff-v3",
        "doublesword-v7",
        "long-sword-free-walk-attack1",
        "long-sword-sprites-v5",
        "Pixel Prototype Enemy\Pixel Prototype Enemy"
    )) {
        Add-RootSpec $roots (Join-Path $SourceRoot $name)
    }

    $legacyRoot = Join-Path $SourceRoot "legacy-vania-npc-v7\spritesheets"
    if (Test-Path $legacyRoot) {
        $legacyPrefixes = Get-ChildItem -Path $legacyRoot -File |
            Where-Object { $_.Extension -eq ".png" } |
            ForEach-Object {
                $name = $_.BaseName.ToLowerInvariant()
                if ($name -notmatch '^npc-') { return }
                if ($name -match '^(npc-[a-z0-9]+(?:-[a-z0-9]+)?)') {
                    $Matches[1]
                }
            } |
            Where-Object { $_ } |
            Select-Object -Unique
        foreach ($prefix in $legacyPrefixes) {
            Add-RootSpec $roots $legacyRoot -IdOverride (Normalize-Slug $prefix) -MatchPrefix $prefix
        }
    }

    $npcEnemiesRoot = Join-Path $SourceRoot "Characters\NPC and ENEMIES"
    foreach ($entry in Get-ChildItem -Path $npcEnemiesRoot -Directory) {
        switch -Regex ($entry.Name) {
            '^Bridge Enemies$' {
                foreach ($sub in Get-ChildItem -Path $entry.FullName -Directory) {
                    Add-RootSpec $roots $sub.FullName -Prefix "bridge"
                }
            }
            '^Cemetery Enemies$' {
                foreach ($sub in Get-ChildItem -Path $entry.FullName -Directory) {
                    Add-RootSpec $roots $sub.FullName -Prefix "cemetery"
                }
            }
            '^Church Enemies$' {
                foreach ($sub in Get-ChildItem -Path $entry.FullName -Directory) {
                    Add-RootSpec $roots $sub.FullName -Prefix "church"
                }
            }
            '^Enemies Pack' {
                foreach ($sub in Get-ChildItem -Path $entry.FullName -Directory) {
                    Add-RootSpec $roots $sub.FullName -Prefix (Normalize-Slug $entry.Name)
                }
            }
            '^Town NPCs$' {
                $stems = Get-ChildItem -Path (Join-Path $entry.FullName "spritesheets") -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -eq ".png" } |
                    ForEach-Object { $_.BaseName -replace '-(idle|walk)$', '' } |
                    Select-Object -Unique
                foreach ($stem in $stems) {
                    Add-RootSpec $roots (Join-Path $entry.FullName "spritesheets") -IdOverride ("town_" + (Normalize-Slug $stem)) -MatchPrefix $stem
                }
            }
            default {
                Add-RootSpec $roots $entry.FullName
            }
        }
    }

    $playableRoot = Join-Path $SourceRoot "Characters\PLAYABLE CHARACTERS"
    foreach ($entry in Get-ChildItem -Path $playableRoot -Directory) {
        Add-RootSpec $roots $entry.FullName -Prefix "playable"
    }

    $enemySpritesRoot = Join-Path $SourceRoot "enemy_sprites"
    foreach ($packDir in Get-ChildItem -Path $enemySpritesRoot -Directory) {
        $packSlug = Normalize-Slug $packDir.Name
        foreach ($candidate in Get-ChildItem -Path $packDir.FullName -Recurse -Directory) {
            if (Should-SkipPng $candidate.FullName) { continue }
            $pngs = @(Get-ChildItem -Path $candidate.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".png" })
            if (-not $pngs -or @($pngs).Count -lt 3) { continue }
            $states = @()
            foreach ($png in $pngs) {
                $state = Get-CanonicalAnimation ($png.BaseName + " " + $candidate.Name)
                if ($state) { $states += $state }
            }
            $states = @($states | Select-Object -Unique)
            if (@($states).Count -lt 2) { continue }
            $parentPngCount = @(Get-ChildItem -Path $candidate.Parent.FullName -File -Include *.png -ErrorAction SilentlyContinue).Count
            if ($parentPngCount -ge 6) { continue }
            Add-RootSpec $roots $candidate.FullName -Prefix $packSlug
        }
    }

    return $roots
}

function Import-RootSpec($spec) {
    $path = $spec.Path
    $baseId =
        if ($spec.IdOverride) { $spec.IdOverride }
        else {
            $parts = (Get-RelativePath $SourceRoot $path) -split '[\\/]'
            $slug = Join-SlugParts $parts
            if ($spec.Prefix) {
                $slug = Join-SlugParts @($spec.Prefix, $slug)
            }
            $slug
        }
    if ([string]::IsNullOrWhiteSpace($baseId)) { return $null }
    $entityId = Shorten-EntityId (Normalize-Slug $baseId)
    $sprite = Export-SpriteSet -Root $path -PackId $PackId -EntityId $entityId -MatchPrefix $spec.MatchPrefix
    if (-not $sprite) { return $null }
    return New-EntityRecord -EntityId $entityId -SourcePath $path -SpriteSet $sprite.SpriteSet -States $sprite.ExportedStates
}

$packRoot = Join-Path $PSScriptRoot "..\Content\$PackId"
$packRoot = [System.IO.Path]::GetFullPath($packRoot)
if (-not (Test-Path $packRoot)) {
    throw "Pack root not found: $packRoot"
}

$entityPath = Join-Path $packRoot "Entities\entities.json"
$entitiesDoc = ConvertTo-OrderedData (Get-Content -Raw -Path $entityPath | ConvertFrom-Json)
$existingById = @{}
foreach ($entity in $entitiesDoc.entities) {
    $desc = if ($entity.Contains("description")) { "$($entity.description)" } else { "" }
    if ($desc.StartsWith("Imported default entity from ")) { continue }
    $existingById[$entity.id] = $entity
}

$imported = New-Object System.Collections.Generic.List[object]
$rootSpecs = Get-RootSpecs -SourceRoot $SourceRoot
foreach ($spec in $rootSpecs) {
    $entity = Import-RootSpec $spec
    if (-not $entity) { continue }
    $existingById[$entity.id] = $entity
    $imported.Add($entity)
}

foreach ($entity in @($existingById.Values)) {
    if ($entity.category -eq "interactable") {
        if (-not $entity.Contains("movement_mode")) { $entity.movement_mode = "ground" }
        continue
    }
    $states = @()
    $spriteSetValue = if ($entity.Contains("sprite_set")) { "$($entity.sprite_set)" } else { "" }
    $spriteDir = Join-Path $packRoot ($spriteSetValue -replace '/', '\')
    if (Test-Path $spriteDir) {
        foreach ($png in Get-ChildItem -Path $spriteDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".png" }) {
            $states += $png.BaseName.ToLowerInvariant()
        }
    }
    $movementMode = if ($entity.Contains("movement_mode")) { "$($entity.movement_mode)" } else { (Get-MovementMode -SourcePath $entity.id -States $states) }
    $entity.movement_mode = $movementMode
    $behaviorValue = if ($entity.Contains("behavior")) { "$($entity.behavior)" } else { "" }
    if ([string]::IsNullOrWhiteSpace($behaviorValue)) {
        $entity.behavior = Get-BehaviorId -Category $entity.category -MovementMode $movementMode -States $states -SourcePath $entity.id
    }
}

$sortedEntities = @($existingById.Values | Sort-Object category, id)
@{
    _comment = "Phase 4 entity registry. Each entry maps an id (referenced from rooms.json entities[].type) to a Godot scene path. Per-instance overrides live in the room's entity entry under 'properties'. Tags are per-instance and used by the trigger system for matching."
    entities = $sortedEntities
} | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -Path $entityPath

Write-Host ("Imported or refreshed {0} default NPC/enemy entities into {1}" -f $imported.Count, $entityPath)
