$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = "D:\SPaceAssetsNoisey\4-17\characters\PixelPrototypePlayer\Pixel Prototype Player\Sprites\Weapons\Bullet"
$targetDir = Join-Path $repoRoot "Content\demo\Projectiles"
$jsonPath = Join-Path $targetDir "projectiles.json"

$seedVersion = 2

if(!(Test-Path -LiteralPath $targetDir)){
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

$copies = @(
    @{ Source = "Bullet01.png"; Target = "bullet_basic.png" },
    @{ Source = "Bullet02.png"; Target = "bullet_charged.png" }
)

foreach($copy in $copies){
    $src = Join-Path $sourceRoot $copy.Source
    $dst = Join-Path $targetDir $copy.Target
    Copy-Item -LiteralPath $src -Destination $dst -Force
}

$projectiles = @(
    [ordered]@{
        id = "beam_basic"
        name = "Sidearm Round"
        sprite_sheet = "bullet_basic.png"
        frame_width = 96
        frame_height = 84
        frame_index = 0
        frame_count = 1
        frame_tick = 10
        speed = 560
        gravity = 0
        lifetime_ticks = 90
        damage = 10
        pierces = $false
        homing = $false
        homing_strength = 0
        hitbox_w = 12
        hitbox_h = 6
        rotate_to_velocity = $false
        trail_color = "#ffd27a"
    },
    [ordered]@{
        id = "beam_charged"
        name = "Charged Slug"
        sprite_sheet = "bullet_charged.png"
        frame_width = 96
        frame_height = 84
        frame_index = 0
        frame_count = 1
        frame_tick = 10
        speed = 640
        gravity = 0
        lifetime_ticks = 110
        damage = 24
        pierces = $false
        homing = $false
        homing_strength = 0
        hitbox_w = 14
        hitbox_h = 8
        rotate_to_velocity = $false
        trail_color = "#fff1a0"
    },
    [ordered]@{
        id = "grenade"
        name = "Grenade"
        sprite_sheet = "bullet_charged.png"
        frame_width = 96
        frame_height = 84
        frame_index = 0
        frame_count = 1
        frame_tick = 10
        speed = 240
        gravity = 600
        lifetime_ticks = 180
        damage = 30
        pierces = $false
        homing = $false
        homing_strength = 0
        hitbox_w = 8
        hitbox_h = 8
        rotate_to_velocity = $true
        trail_color = "#ffaa33"
        explosive = $true
        blast_radius = 48
        explosion_damage = 30
        explode_on_hit = $true
        explode_on_timeout = $true
        break_blocks = $true
        bomb_jump = $true
        bomb_jump_speed = 180
    }
)

$json = [ordered]@{
    _comment = "Starter projectile registry aligned to the gun-based default ranged lane. Basic and charged ranged shots use copied bullet PNGs from the Pixel Prototype Player source set."
    seed_version = $seedVersion
    projectiles = $projectiles
}

$json | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Output "Wrote:"
Write-Output "  $jsonPath"
