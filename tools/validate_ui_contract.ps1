param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$PackId = "demo",
    [switch]$CheckDocs,
    [switch]$SyncDocs,
    [switch]$SmokePack,
    [switch]$RuntimeSmoke,
    [switch]$AuthoredRouteSmoke,
    [switch]$GoldenPathSmoke,
    [switch]$TriggerRecipeSmoke,
    [switch]$WorldRecipeSmoke,
    [switch]$ReferenceIndexSmoke,
    [switch]$ReferenceRefactorSmoke,
    [switch]$QuestSchemaSmoke
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = "godot"
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = "res://tools/ui_contract_cli.gd"
$runtimeSmokeScriptPath = "res://tools/phase2_runtime_smoke.gd"
$authoredRouteSmokeScriptPath = "res://tools/runtime_smoke_cli.gd"
$goldenPathSmokeScriptPath = "res://tools/golden_pack_cli.gd"
$triggerRecipeSmokeScriptPath = "res://tools/trigger_recipe_smoke.gd"
$worldRecipeSmokeScriptPath = "res://tools/world_recipe_smoke.gd"
$referenceIndexSmokeScriptPath = "res://tools/reference_index_smoke.gd"
$referenceRefactorSmokeScriptPath = "res://tools/reference_refactor_smoke.gd"
$questSchemaSmokeScriptPath = "res://tools/quest_schema_smoke.gd"

if ($SyncDocs) {
    $args = @("--headless", "--path", $projectRoot, "--script", $scriptPath, "--", "sync-docs")
    if ($CheckDocs) {
        $args += "--check"
    }
    & $GodotBin @args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    if (-not $SmokePack -and -not $PSBoundParameters.ContainsKey("PackId")) {
        exit 0
    }
}

if ($SmokePack) {
    & $GodotBin --headless --path $projectRoot --script $scriptPath -- validate-smoke-pack
    if ($LASTEXITCODE -ne 0 -or -not $RuntimeSmoke) {
        exit $LASTEXITCODE
    }
}

if ($RuntimeSmoke) {
    & $GodotBin --headless --path $projectRoot --script $runtimeSmokeScriptPath -- phase2_runtime_smoke
    if ($LASTEXITCODE -ne 0 -or -not $AuthoredRouteSmoke) {
        exit $LASTEXITCODE
    }
}

if ($AuthoredRouteSmoke) {
    & $GodotBin --headless --path $projectRoot --script $authoredRouteSmokeScriptPath -- authored-route --pack phase2_runtime_smoke --slot 5
    if ($LASTEXITCODE -ne 0 -or -not $GoldenPathSmoke) {
        exit $LASTEXITCODE
    }
}

if ($GoldenPathSmoke) {
    & $GodotBin --headless --path $projectRoot --script $goldenPathSmokeScriptPath -- smoke --pack golden_path --clean --slot 6
    if ($LASTEXITCODE -ne 0 -or -not $TriggerRecipeSmoke) {
        exit $LASTEXITCODE
    }
}

if ($TriggerRecipeSmoke) {
    & $GodotBin --headless --path $projectRoot --script $triggerRecipeSmokeScriptPath
    if ($LASTEXITCODE -ne 0 -or -not $WorldRecipeSmoke) {
        exit $LASTEXITCODE
    }
}

if ($WorldRecipeSmoke) {
    & $GodotBin --headless --path $projectRoot --script $worldRecipeSmokeScriptPath
    if ($LASTEXITCODE -ne 0 -or -not $ReferenceIndexSmoke) {
        exit $LASTEXITCODE
    }
}

if ($ReferenceIndexSmoke) {
    & $GodotBin --headless --path $projectRoot --script $referenceIndexSmokeScriptPath
    if ($LASTEXITCODE -ne 0 -or -not $ReferenceRefactorSmoke) {
        exit $LASTEXITCODE
    }
}

if ($ReferenceRefactorSmoke) {
    & $GodotBin --headless --path $projectRoot --script $referenceRefactorSmokeScriptPath
    if ($LASTEXITCODE -ne 0 -or -not $QuestSchemaSmoke) {
        exit $LASTEXITCODE
    }
}

if ($QuestSchemaSmoke) {
    & $GodotBin --headless --path $projectRoot --script $questSchemaSmokeScriptPath
    exit $LASTEXITCODE
}

& $GodotBin --headless --path $projectRoot --script $scriptPath -- validate-pack $PackId
exit $LASTEXITCODE
