param(
    [string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
$command = Get-Command $Godot -ErrorAction SilentlyContinue
if (-not $command) {
    throw 'Godot was not found. Run .\start_vr.ps1 -Godot "C:\path\to\Godot_v4.6.3-stable_win64_console.exe"'
}
$binary = $command.Source
$version = (& $binary --version | Out-String).Trim()
if ($version -notmatch '^4\.(\d+)\.' -or [int]$Matches[1] -lt 6) {
    throw "Flowstate needs Godot 4.6 or newer in the 4.x series. Found: $version"
}
$logs = Join-Path ([System.IO.Path]::GetTempPath()) ("flowstate-vr-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $logs | Out-Null

function Invoke-Stage([string]$Name, [string[]]$Arguments) {
    $output = Join-Path $logs "$Name.log"
    $errors = Join-Path $logs "$Name.errors.log"
    $quoted = $Arguments | ForEach-Object { '"' + $_ + '"' }
    $process = Start-Process -FilePath $binary -ArgumentList $quoted -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $output -RedirectStandardError $errors
    $text = (Get-Content $output -Raw) + "`n" + (Get-Content $errors -Raw)
    if ($process.ExitCode -ne 0) {
        Write-Host $text
        throw "$Name failed. Logs: $logs"
    }
    return $text
}

Write-Host "Importing project assets with VR disabled..."
$null = Invoke-Stage "import" @("--headless", "--xr-mode", "off", "--path", $project, "--import")
Write-Host "Checking meshes and scenes..."
$validation = Invoke-Stage "validate" @("--headless", "--xr-mode", "off", "--path", $project, "--script", "res://tests/validate_resources.gd")
if ($validation -match '(?m)^(SCRIPT ERROR|ERROR):' -or $validation -notmatch 'PASS resource validation') {
    Write-Host $validation
    throw "The project still has resource or script errors. VR was not started. Logs: $logs"
}
Write-Host "Starting Flowstate in VR. Logs: $logs"
$null = Invoke-Stage "game" @("--path", $project, "--xr-mode", "on")
