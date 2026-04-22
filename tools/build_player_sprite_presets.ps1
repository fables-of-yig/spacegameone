$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$demoSpritesDir = Join-Path $repoRoot "Content\demo\Sprites"
$presetRoot = Join-Path $demoSpritesDir "presets"

$femaleRoot = "D:\SPaceAssetsNoisey\4-17\characters\PlayerCharacters\Adventurers\The Female Adventurer - Premium"
$maleRoot = "D:\SPaceAssetsNoisey\4-17\characters\PlayerCharacters\Adventurers\The Male adventurer - Premium"

$frameWidth = 64
$frameHeight = 64
$sheetCols = 6
$centerX = 32
$centerY = 32
$seedVersion = 5
$frameCountCache = @{}

function Ensure-Dir {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Data
    )
    $Data | ConvertTo-Json -Depth 16 | Set-Content -Path $Path -Encoding UTF8
}

function New-FrameRef {
    param(
        [string]$Path,
        [int]$Index,
        [double]$Rotation = 0.0
    )
    return [ordered]@{
        path = ($Path -replace '\\', '/')
        index = $Index
        rotation_deg = [double]$Rotation
    }
}

function Expand-Frames {
    param(
        [string]$Path,
        [int[]]$Indices,
        [double[]]$Rotations = @()
    )
    $out = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Indices.Count; $i++) {
        $rot = 0.0
        if ($Rotations.Count -gt $i) {
            $rot = [double]$Rotations[$i]
        } elseif ($Rotations.Count -eq 1) {
            $rot = [double]$Rotations[0]
        }
        $out.Add((New-FrameRef -Path $Path -Index $Indices[$i] -Rotation $rot))
    }
    return $out.ToArray()
}

function New-PoseEntry {
    param($Spec)
    return [ordered]@{
        name = $Spec.Name
        dir = [int]$Spec.Dir
        mvtype = [int]$Spec.MvType
        y_radius = 16
        y_offset = 0
        collision_x = 0
        collision_width = 24
        hurtbox_x = 0
        hurtbox_y = -16
        hurtbox_w = 24
        hurtbox_h = 32
        weapon_anchor_x = 0
        weapon_anchor_y = -24
        timing = @($Spec.Timing)
        loop_from = [int]$Spec.LoopFrom
        transition_to = [int]$Spec.TransitionTo
    }
}

function Sanitize-SheetId {
    param([string]$RelativePath)
    $base = ($RelativePath -replace '\.png$','' -replace '[\\\/]+','_' -replace '[^A-Za-z0-9_]+','_').ToLower()
    if ([string]::IsNullOrWhiteSpace($base)) {
        return "sheet"
    }
    return "src_" + $base
}

function Validate-SourceImage {
    param(
        [string]$AbsolutePath,
        [string]$RelativePath
    )
    $image = [System.Drawing.Image]::FromFile($AbsolutePath)
    try {
        if (($image.Width % $frameWidth) -ne 0 -or ($image.Height % $frameHeight) -ne 0) {
            throw "Unexpected sheet dimensions for $RelativePath ($($image.Width)x$($image.Height)); expected multiples of ${frameWidth}x${frameHeight}."
        }
    }
    finally {
        $image.Dispose()
    }
}

function Get-StripFrameCount {
    param(
        [string]$SourceRoot,
        [string]$RelativePath
    )
    $cacheKey = "$SourceRoot|$RelativePath"
    if ($frameCountCache.ContainsKey($cacheKey)) {
        return [int]$frameCountCache[$cacheKey]
    }
    $absolutePath = Join-Path $SourceRoot ($RelativePath -replace '/', '\')
    Validate-SourceImage -AbsolutePath $absolutePath -RelativePath $RelativePath
    $image = [System.Drawing.Image]::FromFile($absolutePath)
    try {
        if ($image.Height -ne $frameHeight) {
            throw "Expected single-strip height for $RelativePath but got $($image.Width)x$($image.Height)."
        }
        $count = [int]($image.Width / $frameWidth)
        if ($count -lt 1) {
            throw "No frames found in $RelativePath."
        }
        $frameCountCache[$cacheKey] = $count
        return $count
    }
    finally {
        $image.Dispose()
    }
}

function Expand-StripFrames {
    param(
        [string]$SourceRoot,
        [string]$RelativePath,
        [int]$StartIndex = 0,
        [int]$Count = -1,
        [double[]]$Rotations = @()
    )
    $frameCount = Get-StripFrameCount -SourceRoot $SourceRoot -RelativePath $RelativePath
    $endExclusive = $frameCount
    if ($Count -ge 0) {
        $endExclusive = [Math]::Min($frameCount, $StartIndex + $Count)
    }
    $indices = New-Object System.Collections.Generic.List[int]
    for ($i = $StartIndex; $i -lt $endExclusive; $i++) {
        $indices.Add($i)
    }
    return Expand-Frames -Path $RelativePath -Indices $indices.ToArray() -Rotations $Rotations
}

function New-SpinRotations {
    param([int]$FrameCount)
    $out = New-Object System.Collections.Generic.List[double]
    if ($FrameCount -lt 1) {
        return @()
    }
    for ($i = 0; $i -lt $FrameCount; $i++) {
        $out.Add([Math]::Round((360.0 / $FrameCount) * $i, 2))
    }
    return $out.ToArray()
}

function Build-ClassicPreset {
    $presetId = "classic_demo"
    $presetDir = Join-Path $presetRoot $presetId
    Ensure-Dir $presetDir

    Copy-Item -LiteralPath (Join-Path $demoSpritesDir "player_frames.json") -Destination (Join-Path $presetDir "player_frames.json") -Force
    Copy-Item -LiteralPath (Join-Path $demoSpritesDir "player_poses.json") -Destination (Join-Path $presetDir "player_poses.json") -Force

    $manifest = [ordered]@{
        id = $presetId
        name = "Classic Demo"
        description = "Current shipped demo player sprite baseline."
        frames = "player_frames.json"
        poses = "player_poses.json"
    }
    Write-JsonFile -Path (Join-Path $presetDir "preset.json") -Data $manifest
}

function Build-AdventurerPreset {
    param(
        [string]$PresetId,
        [string]$PresetName,
        [string]$SourceRoot,
        [string]$IdleDown,
        [string]$IdleRight,
        [string]$IdleLeft,
        [string]$RunRight,
        [string]$RunLeft,
        [string]$WalkRight,
        [string]$WalkLeft,
        [string]$JumpRightUp,
        [string]$JumpLeftUp,
        [string]$JumpRightDown,
        [string]$JumpLeftDown,
        [string]$IdleGunRightDown,
        [string]$IdleGunLeftDown,
        [string]$IdleGunRightUp,
        [string]$IdleGunLeftUp,
        [string]$ShootRight,
        [string]$ShootLeft,
        [string]$SpearRight,
        [string]$SpearLeft,
        [string]$DashRight,
        [string]$DashLeft
    )
    $spinRightFrames = Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpRightDown -Rotations (New-SpinRotations (Get-StripFrameCount -SourceRoot $SourceRoot -RelativePath $JumpRightDown))
    $spinLeftFrames = Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpLeftDown -Rotations (New-SpinRotations (Get-StripFrameCount -SourceRoot $SourceRoot -RelativePath $JumpLeftDown))

    $poseSpecs = @(
        [ordered]@{ Pose = 0; Name = "forward"; Dir = 1; MvType = 0; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleDown -Count 1) },
        [ordered]@{ Pose = 1; Name = "stand_right"; Dir = 1; MvType = 0; Timing = @(10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleRight) },
        [ordered]@{ Pose = 2; Name = "stand_left"; Dir = -1; MvType = 0; Timing = @(10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleLeft) },
        [ordered]@{ Pose = 9; Name = "run_right"; Dir = 1; MvType = 1; Timing = @(6,6,6,6,6,6); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $RunRight) },
        [ordered]@{ Pose = 10; Name = "run_left"; Dir = -1; MvType = 1; Timing = @(6,6,6,6,6,6); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $RunLeft) },
        [ordered]@{ Pose = 25; Name = "spin_right"; Dir = 1; MvType = 3; Timing = @(5,5,5,5,5,5); LoopFrom = 0; TransitionTo = -1; Frames = $spinRightFrames },
        [ordered]@{ Pose = 26; Name = "spin_left"; Dir = -1; MvType = 3; Timing = @(5,5,5,5,5,5); LoopFrom = 0; TransitionTo = -1; Frames = $spinLeftFrames },
        [ordered]@{ Pose = 37; Name = "turn_right"; Dir = 1; MvType = 14; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $WalkRight -Count 3) },
        [ordered]@{ Pose = 38; Name = "turn_left"; Dir = -1; MvType = 14; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $WalkLeft -Count 3) },
        [ordered]@{ Pose = 41; Name = "fall_right"; Dir = 1; MvType = 6; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpRightDown -StartIndex 5 -Count 1) },
        [ordered]@{ Pose = 42; Name = "fall_left"; Dir = -1; MvType = 6; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpLeftDown -StartIndex 5 -Count 1) },
        [ordered]@{ Pose = 47; Name = "turn_air_right"; Dir = 1; MvType = 23; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 42; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpRightDown -Count 3) },
        [ordered]@{ Pose = 48; Name = "turn_air_left"; Dir = -1; MvType = 23; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 41; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpLeftDown -Count 3) },
        [ordered]@{ Pose = 53; Name = "crouch_transition_right"; Dir = 1; MvType = 15; Timing = @(5,5,5); LoopFrom = -1; TransitionTo = 67; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $WalkRight -Count 3) },
        [ordered]@{ Pose = 54; Name = "crouch_transition_left"; Dir = -1; MvType = 15; Timing = @(5,5,5); LoopFrom = -1; TransitionTo = 68; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $WalkLeft -Count 3) },
        [ordered]@{ Pose = 59; Name = "crouch_aim_up_right"; Dir = 1; MvType = 5; Timing = @(10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleGunRightUp) },
        [ordered]@{ Pose = 60; Name = "crouch_aim_up_left"; Dir = -1; MvType = 5; Timing = @(10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleGunLeftUp) },
        [ordered]@{ Pose = 67; Name = "crouch_right"; Dir = 1; MvType = 5; Timing = @(10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleRight -Count 3) },
        [ordered]@{ Pose = 68; Name = "crouch_left"; Dir = -1; MvType = 5; Timing = @(10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleLeft -Count 3) },
        [ordered]@{ Pose = 75; Name = "jump_rise_right"; Dir = 1; MvType = 2; Timing = @(5,5,5,5); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpRightUp -Count 4) },
        [ordered]@{ Pose = 76; Name = "jump_rise_left"; Dir = -1; MvType = 2; Timing = @(5,5,5,5); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpLeftUp -Count 4) },
        [ordered]@{ Pose = 135; Name = "turn_fall_right"; Dir = 1; MvType = 24; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 42; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpRightDown -Count 3) },
        [ordered]@{ Pose = 136; Name = "turn_fall_left"; Dir = -1; MvType = 24; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 41; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $JumpLeftDown -Count 3) },
        [ordered]@{ Pose = 164; Name = "land_right"; Dir = 1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $RunRight -Count 2) },
        [ordered]@{ Pose = 165; Name = "land_left"; Dir = -1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $RunLeft -Count 2) },
        [ordered]@{ Pose = 166; Name = "land_spin_right"; Dir = 1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $RunRight -Count 2) },
        [ordered]@{ Pose = 167; Name = "land_spin_left"; Dir = -1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $RunLeft -Count 2) },
        [ordered]@{ Pose = 201; Name = "melee_1_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $SpearRight) },
        [ordered]@{ Pose = 202; Name = "melee_1_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $SpearLeft) },
        [ordered]@{ Pose = 203; Name = "melee_2_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $SpearRight) },
        [ordered]@{ Pose = 204; Name = "melee_2_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $SpearLeft) },
        [ordered]@{ Pose = 205; Name = "melee_3_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $SpearRight) },
        [ordered]@{ Pose = 206; Name = "melee_3_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $SpearLeft) },
        [ordered]@{ Pose = 207; Name = "ranged_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $ShootRight) },
        [ordered]@{ Pose = 208; Name = "ranged_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $ShootLeft) },
        [ordered]@{ Pose = 209; Name = "ranged_charge_right"; Dir = 1; MvType = 15; Timing = @(10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleGunRightDown) },
        [ordered]@{ Pose = 210; Name = "ranged_charge_left"; Dir = -1; MvType = 15; Timing = @(10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $IdleGunLeftDown) },
        [ordered]@{ Pose = 211; Name = "dodge_roll_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $DashRight) },
        [ordered]@{ Pose = 212; Name = "dodge_roll_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = (Expand-StripFrames -SourceRoot $SourceRoot -RelativePath $DashLeft) }
    )

    $presetDir = Join-Path $presetRoot $PresetId
    if (Test-Path -LiteralPath $presetDir) {
        Remove-Item -LiteralPath $presetDir -Recurse -Force
    }
    Ensure-Dir $presetDir

    $sheetDefs = New-Object System.Collections.Generic.List[object]
    $posesOut = [ordered]@{}
    $framesOut = New-Object System.Collections.Generic.List[object]
    $copied = @{}

    foreach ($spec in $poseSpecs) {
        $posesOut["$($spec.Pose)"] = New-PoseEntry $spec
        foreach ($frame in @($spec.Frames)) {
            $rel = [string]$frame.path
            if (-not $copied.ContainsKey($rel)) {
                $abs = Join-Path $SourceRoot ($rel -replace '/', '\')
                Validate-SourceImage -AbsolutePath $abs -RelativePath $rel
                $dest = Join-Path $presetDir ($rel -replace '/', '\')
                Ensure-Dir (Split-Path -Parent $dest)
                Copy-Item -LiteralPath $abs -Destination $dest -Force
                $sheetId = Sanitize-SheetId $rel
                $copied[$rel] = $sheetId
                $sheetDefs.Add([ordered]@{
                    id = $sheetId
                    file = $rel
                    z = 0
                })
            }
            $framesOut.Add([ordered]@{
                pose = [int]$spec.Pose
                rotation_deg = [double]$frame.rotation_deg
                layers = @([ordered]@{
                    sheet = $copied[$rel]
                    index = [int]$frame.index
                })
            })
        }
    }

    $framesJson = [ordered]@{
        seed_version = $seedVersion
        frame_width = $frameWidth
        frame_height = $frameHeight
        center_x = $centerX
        center_y = $centerY
        sheet_cols = $sheetCols
        sheets = $sheetDefs.ToArray()
        frames = $framesOut.ToArray()
    }
    $posesJson = [ordered]@{
        seed_version = $seedVersion
        poses = $posesOut
    }
    $manifest = [ordered]@{
        id = $PresetId
        name = $PresetName
        description = "Adventurer preset generated from shipped source strips with authored left and right pose sheets."
        frames = "player_frames.json"
        poses = "player_poses.json"
    }

    Write-JsonFile -Path (Join-Path $presetDir "player_frames.json") -Data $framesJson
    Write-JsonFile -Path (Join-Path $presetDir "player_poses.json") -Data $posesJson
    Write-JsonFile -Path (Join-Path $presetDir "preset.json") -Data $manifest
}

Ensure-Dir $presetRoot
Build-ClassicPreset

Build-AdventurerPreset `
    -PresetId "adventurer_female" `
    -PresetName "Adventurer Female" `
    -SourceRoot $femaleRoot `
    -IdleDown "Idle/Normal/Idle_Down.png" `
    -IdleRight "Idle/Normal/Idle_Right_Down.png" `
    -IdleLeft "Idle/Normal/Idle_Left_Down.png" `
    -RunRight "Run/Normal/Run_Right_Down.png" `
    -RunLeft "Run/Normal/Run_Left_Down.png" `
    -WalkRight "Walk/Normal/walk_Right_Down.png" `
    -WalkLeft "Walk/Normal/walk_Left_Down.png" `
    -JumpRightUp "Jump - NEW/Normal/Jump_Right_Up.png" `
    -JumpLeftUp "Jump - NEW/Normal/Jump_Left_Up.png" `
    -JumpRightDown "Jump - NEW/Normal/Jump_Right_Down.png" `
    -JumpLeftDown "Jump - NEW/Normal/Jump_Left_Down.png" `
    -IdleGunRightDown "Idle/Gun/Idle_Gun_Right_Down.png" `
    -IdleGunLeftDown "Idle/Gun/Idle_Gun_Left_Down.png" `
    -IdleGunRightUp "Idle/Gun/Idle_Gun_Right_Up.png" `
    -IdleGunLeftUp "Idle/Gun/Idle_Gun_Left_Up.png" `
    -ShootRight "Attack/Gun/Shooting_Right.png" `
    -ShootLeft "Attack/Gun/Shooting_Left.png" `
    -SpearRight "Attack/Spear/Attack_Spear_Right.png" `
    -SpearLeft "Attack/Spear/Attack_Spear_Left.png" `
    -DashRight "Dash/Normal/Dash_Right_Down.png" `
    -DashLeft "Dash/Normal/Dash_Left_Down.png"

Build-AdventurerPreset `
    -PresetId "adventurer_male" `
    -PresetName "Adventurer Male" `
    -SourceRoot $maleRoot `
    -IdleDown "Idle/Normal/idle_down.png" `
    -IdleRight "Idle/Normal/idle_right_down.png" `
    -IdleLeft "Idle/Normal/idle_left_down.png" `
    -RunRight "Run/Normal/run_right_down.png" `
    -RunLeft "Run/Normal/run_left_down.png" `
    -WalkRight "Walk/Normal/walk_right_down.png" `
    -WalkLeft "Walk/Normal/walk_left_down.png" `
    -JumpRightUp "Jump/Normal/Jump_Right_Up.png" `
    -JumpLeftUp "Jump/Normal/Jump_Left_Up.png" `
    -JumpRightDown "Jump/Normal/Jump_Right_Down.png" `
    -JumpLeftDown "Jump/Normal/Jump_Left_Down.png" `
    -IdleGunRightDown "Idle/Gun/Idle_Gun_right_down.png" `
    -IdleGunLeftDown "Idle/Gun/Idle_Gun_left_down.png" `
    -IdleGunRightUp "Idle/Gun/Idle_Gun_right_up.png" `
    -IdleGunLeftUp "Idle/Gun/Idle_Gun_left_up.png" `
    -ShootRight "Attack/Gun/Shooting_right.png" `
    -ShootLeft "Attack/Gun/Shooting_left.png" `
    -SpearRight "Attack/Spear/attack_spear_right.png" `
    -SpearLeft "Attack/Spear/attack_spear_left.png" `
    -DashRight "Dash/Normal/Dash_right_Down.png" `
    -DashLeft "Dash/Normal/Dash_left_Down.png"

Write-Output "Built player sprite presets under $presetRoot"
