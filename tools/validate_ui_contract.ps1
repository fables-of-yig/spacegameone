param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$PackId = "demo",
    [switch]$CheckDocs,
    [switch]$SyncDocs,
    [switch]$SmokePack
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = "godot"
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = "res://tools/ui_contract_cli.gd"

if ($SyncDocs) {
    $args = @("--headless", "--path", $projectRoot, "--script", $scriptPath, "sync-docs")
    if ($CheckDocs) {
        $args += "--check"
    }
    & $GodotBin @args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if ($SmokePack) {
    & $GodotBin --headless --path $projectRoot --script $scriptPath validate-smoke-pack
    exit $LASTEXITCODE
}

& $GodotBin --headless --path $projectRoot --script $scriptPath validate-pack $PackId
exit $LASTEXITCODE
