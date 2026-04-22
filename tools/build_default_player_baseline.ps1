$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = "D:\SPaceAssetsNoisey\4-17\characters\PixelPrototypePlayer\Pixel Prototype Player\Sprites"
$targetDir = Join-Path $repoRoot "Content\demo\Sprites"
$sourceCopyDir = Join-Path $targetDir "default_player"
$framesPath = Join-Path $targetDir "player_frames.json"
$posesPath = Join-Path $targetDir "player_poses.json"

$frameWidth = 96
$frameHeight = 84
$sheetCols = 1
$centerX = 48
$centerY = 42
$seedVersion = 4

$poseSpecs = @(
    @{ Pose = 0; Name = "forward"; Dir = 1; MvType = 0; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = @("Idle\Idle01.png") },
    @{ Pose = 1; Name = "stand_right"; Dir = 1; MvType = 0; Timing = @(10,10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = @("Idle\Idle01.png","Idle\Idle02.png","Idle\Idle03.png","Idle\Idle04.png","Idle\Idle05.png","Idle\Idle06.png","Idle\Idle07.png") },
    @{ Pose = 2; Name = "stand_left"; Dir = -1; MvType = 0; Timing = @(10,10,10,10,10,10,10); LoopFrom = 0; TransitionTo = -1; Frames = @() },
    @{ Pose = 9; Name = "run_right"; Dir = 1; MvType = 1; Timing = @(6,6,6,6,6,6,6,6); LoopFrom = 0; TransitionTo = -1; Frames = @("Run\Run01.png","Run\Run02.png","Run\Run03.png","Run\Run04.png","Run\Run05.png","Run\Run06.png","Run\Run07.png","Run\Run08.png") },
    @{ Pose = 10; Name = "run_left"; Dir = -1; MvType = 1; Timing = @(6,6,6,6,6,6,6,6); LoopFrom = 0; TransitionTo = -1; Frames = @() },
    @{ Pose = 25; Name = "spin_right"; Dir = 1; MvType = 3; Timing = @(5,5,5,5,5,5,5,5); LoopFrom = 0; TransitionTo = -1; Frames = @("Spin\Spin01.png","Spin\Spin02.png","Spin\Spin03.png","Spin\Spin04.png","Spin\Spin05.png","Spin\Spin06.png","Spin\Spin07.png","Spin\Spin08.png") },
    @{ Pose = 26; Name = "spin_left"; Dir = -1; MvType = 3; Timing = @(5,5,5,5,5,5,5,5); LoopFrom = 0; TransitionTo = -1; Frames = @() },
    @{ Pose = 37; Name = "turn_right"; Dir = 1; MvType = 14; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = @("RunToIdle\RunToIdle01.png","RunToIdle\RunToIdle02.png","RunToIdle\RunToIdle03.png") },
    @{ Pose = 38; Name = "turn_left"; Dir = -1; MvType = 14; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = @() },
    @{ Pose = 41; Name = "fall_right"; Dir = 1; MvType = 6; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = @("JumpFall\JumpFall01.png") },
    @{ Pose = 42; Name = "fall_left"; Dir = -1; MvType = 6; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = @() },
    @{ Pose = 47; Name = "turn_air_right"; Dir = 1; MvType = 23; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 42; Frames = @("Jump\Jump01.png","Jump\Jump02.png","Jump\Jump03.png") },
    @{ Pose = 48; Name = "turn_air_left"; Dir = -1; MvType = 23; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 41; Frames = @() },
    @{ Pose = 53; Name = "crouch_transition_right"; Dir = 1; MvType = 15; Timing = @(5,5,5); LoopFrom = -1; TransitionTo = 67; Frames = @("Crouch\Crouch01.png","Crouch\Crouch02.png","Crouch\Crouch03.png") },
    @{ Pose = 54; Name = "crouch_transition_left"; Dir = -1; MvType = 15; Timing = @(5,5,5); LoopFrom = -1; TransitionTo = 68; Frames = @() },
    @{ Pose = 59; Name = "crouch_aim_up_right"; Dir = 1; MvType = 5; Timing = @(12,12,12); LoopFrom = 0; TransitionTo = -1; Frames = @("LookUp\LookUp01.png","LookUp\LookUp02.png","LookUp\LookUp03.png") },
    @{ Pose = 60; Name = "crouch_aim_up_left"; Dir = -1; MvType = 5; Timing = @(12,12,12); LoopFrom = 0; TransitionTo = -1; Frames = @() },
    @{ Pose = 67; Name = "crouch_right"; Dir = 1; MvType = 5; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = @("Crouch\Crouch06.png") },
    @{ Pose = 68; Name = "crouch_left"; Dir = -1; MvType = 5; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = @() },
    @{ Pose = 75; Name = "jump_rise_right"; Dir = 1; MvType = 2; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = @("JumpRise\JumpRise01.png") },
    @{ Pose = 76; Name = "jump_rise_left"; Dir = -1; MvType = 2; Timing = @(60); LoopFrom = 0; TransitionTo = -1; Frames = @() },
    @{ Pose = 135; Name = "turn_fall_right"; Dir = 1; MvType = 24; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 42; Frames = @("Jump\Jump01.png","Jump\Jump02.png","Jump\Jump03.png") },
    @{ Pose = 136; Name = "turn_fall_left"; Dir = -1; MvType = 24; Timing = @(4,4,4); LoopFrom = -1; TransitionTo = 41; Frames = @() },
    @{ Pose = 164; Name = "land_right"; Dir = 1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 1; Frames = @("Land\Land01.png","Land\Land02.png") },
    @{ Pose = 165; Name = "land_left"; Dir = -1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 2; Frames = @() },
    @{ Pose = 166; Name = "land_spin_right"; Dir = 1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 1; Frames = @("Land\Land01.png","Land\Land02.png") },
    @{ Pose = 167; Name = "land_spin_left"; Dir = -1; MvType = 15; Timing = @(6,6); LoopFrom = -1; TransitionTo = 2; Frames = @() },
    @{ Pose = 201; Name = "melee_1_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = @("Combat\SwordCombo01\SwordCombo0101.png","Combat\SwordCombo01\SwordCombo0102.png","Combat\SwordCombo01\SwordCombo0103.png","Combat\SwordCombo01\SwordCombo0104.png","Combat\SwordCombo01\SwordCombo0105.png","Combat\SwordCombo01\SwordCombo0106.png") },
    @{ Pose = 202; Name = "melee_1_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = @() },
    @{ Pose = 203; Name = "melee_2_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = @("Combat\SwordCombo02\SwordCombo0201.png","Combat\SwordCombo02\SwordCombo0202.png","Combat\SwordCombo02\SwordCombo0203.png","Combat\SwordCombo02\SwordCombo0204.png","Combat\SwordCombo02\SwordCombo0205.png") },
    @{ Pose = 204; Name = "melee_2_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = @() },
    @{ Pose = 205; Name = "melee_3_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = @("Combat\SwordCombo03\SwordCombo0301.png","Combat\SwordCombo03\SwordCombo0302.png","Combat\SwordCombo03\SwordCombo0303.png","Combat\SwordCombo03\SwordCombo0304.png","Combat\SwordCombo03\SwordCombo0305.png") },
    @{ Pose = 206; Name = "melee_3_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = @() },
    @{ Pose = 207; Name = "ranged_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = @("Combat\GunFire\GunFire01.png","Combat\GunFire\GunFire02.png","Combat\GunFire\GunFire03.png","Combat\GunFire\GunFire04.png","Combat\GunFire\GunFire05.png") },
    @{ Pose = 208; Name = "ranged_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = @() },
    @{ Pose = 209; Name = "ranged_charge_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = @("Combat\GunFire2H\GunFire2H01.png","Combat\GunFire2H\GunFire2H02.png","Combat\GunFire2H\GunFire2H03.png","Combat\GunFire2H\GunFire2H04.png","Combat\GunFire2H\GunFire2H05.png") },
    @{ Pose = 210; Name = "ranged_charge_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = @() },
    @{ Pose = 211; Name = "dodge_roll_right"; Dir = 1; MvType = 15; Timing = @(4,4,4,4,4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 1; Frames = @("Roll\Roll01.png","Roll\Roll02.png","Roll\Roll03.png","Roll\Roll04.png","Roll\Roll05.png","Roll\Roll06.png","Roll\Roll07.png","Roll\Roll08.png","Roll\Roll09.png","Roll\Roll10.png") },
    @{ Pose = 212; Name = "dodge_roll_left"; Dir = -1; MvType = 15; Timing = @(4,4,4,4,4,4,4,4,4,4); LoopFrom = -1; TransitionTo = 2; Frames = @() }
)

function New-PoseEntry {
    param($spec)
    return [ordered]@{
        name = $spec.Name
        dir = [int]$spec.Dir
        mvtype = [int]$spec.MvType
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
        timing = @($spec.Timing)
        loop_from = [int]$spec.LoopFrom
        transition_to = [int]$spec.TransitionTo
    }
}

$allFramePaths = New-Object System.Collections.Generic.List[string]
$seenPaths = New-Object 'System.Collections.Generic.HashSet[string]'
$framesOut = New-Object System.Collections.Generic.List[object]
$posesOut = [ordered]@{}

foreach($spec in $poseSpecs){
    $posesOut["$($spec.Pose)"] = New-PoseEntry $spec
    foreach($relativePath in $spec.Frames){
        if($seenPaths.Add($relativePath)){
            $allFramePaths.Add($relativePath)
        }
    }
}

$sheetDefs = New-Object System.Collections.Generic.List[object]
$pathToSheet = @{}
if(!(Test-Path -LiteralPath $targetDir)){
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}
if(Test-Path -LiteralPath $sourceCopyDir){
    Remove-Item -LiteralPath $sourceCopyDir -Recurse -Force
}
foreach($relativePath in $allFramePaths){
    $absolutePath = Join-Path $sourceRoot $relativePath
    $image = [System.Drawing.Image]::FromFile($absolutePath)
    try {
        if($image.Width -ne $frameWidth -or $image.Height -ne $frameHeight){
            throw "Unexpected frame size for $relativePath ($($image.Width)x$($image.Height))"
        }
    }
    finally {
        $image.Dispose()
    }

    $relativeCopyPath = Join-Path "default_player" $relativePath
    $targetPath = Join-Path $targetDir $relativeCopyPath
    $targetParent = Split-Path -Parent $targetPath
    if(!(Test-Path -LiteralPath $targetParent)){
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }
    Copy-Item -LiteralPath $absolutePath -Destination $targetPath -Force

    $sheetId = ("src_" + ($relativePath -replace '[\\\/]+','_' -replace '\.png$','' -replace '[^A-Za-z0-9_]+','_')).ToLower()
    $pathToSheet[$relativePath] = @{
        id = $sheetId
        file = ($relativeCopyPath -replace '\\','/')
    }
    $sheetDefs.Add([ordered]@{
        id = $sheetId
        file = ($relativeCopyPath -replace '\\','/')
        z = 0
    })
}

foreach($spec in $poseSpecs){
    foreach($relativePath in $spec.Frames){
        $sheetInfo = $pathToSheet[$relativePath]
        $framesOut.Add([ordered]@{
            pose = [int]$spec.Pose
            layers = @([ordered]@{
                sheet = $sheetInfo.id
                index = 0
            })
        })
    }
}

$framesJson = @{
    _comment = "Default baseline generated from labeled source folders under Pixel Prototype Player/Sprites. Each frame points at the copied source PNG assigned to that pose instead of a baked combined sheet. Left-facing poses intentionally keep empty strips so editor/runtime mirroring can drive them from the right-facing source poses."
    seed_version = $seedVersion
    frame_width = $frameWidth
    frame_height = $frameHeight
    center_x = $centerX
    center_y = $centerY
    sheet_cols = $sheetCols
    sheets = $sheetDefs.ToArray()
    frames = $framesOut.ToArray()
}

$posesJson = @{
    _comment = "Starter player pose scaffold generated from the labeled Pixel Prototype Player folder sequences. Timing arrays match the imported frame counts from those source folders."
    seed_version = $seedVersion
    poses = $posesOut
}

$framesJson | ConvertTo-Json -Depth 8 | Set-Content -Path $framesPath -Encoding UTF8
$posesJson | ConvertTo-Json -Depth 8 | Set-Content -Path $posesPath -Encoding UTF8

Write-Output "Wrote:"
Write-Output "  $framesPath"
Write-Output "  $posesPath"
