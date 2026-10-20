param(
    [string]$Godot = "godot",
    [string]$Output = "build/flowstate-quest.apk",
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
. (Join-Path $project "other_scripts/quest_build_sync.ps1")
$command = Get-Command $Godot -ErrorAction SilentlyContinue | Select-Object -First 1
if ($command -is [System.Management.Automation.AliasInfo]) {
    $command = $command.ResolvedCommand
}
if ($command -isnot [System.Management.Automation.ApplicationInfo]) {
    throw 'Pass the full Godot executable path with -Godot (on macOS use Godot.app/Contents/MacOS/Godot)'
}
$binary = $command.Path
$version = (& $binary --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.(\d+)\.' -or [int]$Matches[1] -lt 6) {
    throw "Flowstate needs Godot 4.6 or newer in the 4.x series. Found: $version"
}
if (-not [System.IO.Path]::IsPathRooted($Output)) {
    $Output = Join-Path $project $Output
}
$Output = [System.IO.Path]::GetFullPath($Output)
if ([System.IO.Path]::GetExtension($Output) -ne ".apk") {
    throw "Output must end in .apk"
}

# keep quest imports separate from the pcvr cache
$staging = Join-Path $project ".godot/quest-build/project"
$logs = Join-Path $project ".godot/quest-build/logs"
New-Item -ItemType Directory -Force -Path $staging, $logs | Out-Null
$lock = $null
try {
    $lock = [System.IO.File]::Open((Join-Path $logs "build.lock"), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    throw "Another Quest build is already running."
}
try {
    Write-Host "Preparing standalone Quest build..."
    Sync-QuestProject -Source $project -Destination $staging -PreserveDirectories @('android')
    Copy-Item -LiteralPath (Join-Path $project "quest_import.cfg") -Destination (Join-Path $staging "override.cfg") -Force
    & $binary --headless --xr-mode off --path (Join-Path $project "other_scripts/quest_build") --script res://prepare.gd -- $staging
    if ($LASTEXITCODE -ne 0) {
        throw "Could not apply Quest settings to the staged project."
    }
    $credentials = Join-Path $project ".godot/export_credentials.cfg"
    if (Test-Path -LiteralPath $credentials -PathType Leaf) {
        $cache = Join-Path $staging ".godot"
        New-Item -ItemType Directory -Force -Path $cache | Out-Null
        Copy-Item -LiteralPath $credentials -Destination (Join-Path $cache "export_credentials.cfg") -Force
    }
    $exportFlag = if ($Release) { "--export-release" } else { "--export-debug" }
    $pending = Join-Path $logs ("flowstate-" + [guid]::NewGuid().ToString("N") + ".apk")
    $log = Join-Path $logs "export.log"
    # install the gradle template only in the quest staging folder
    $templateArgs = @()
    if (-not (Test-Path -LiteralPath (Join-Path $staging 'android/build/gradlew') -PathType Leaf)) {
        $templateArgs += '--install-android-build-template'
    }
    Write-Host "Importing Quest textures and exporting APK. Logs: $log"
    & $binary --headless --xr-mode off --path $staging --log-file $log @templateArgs $exportFlag "Meta Quest" $pending
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pending -PathType Leaf)) {
        throw "Quest export failed. Check $log and the Android SDK, JDK and export templates in Godot."
    }
    New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($Output)) | Out-Null
    Move-Item -LiteralPath $pending -Destination $Output -Force
    Write-Host "Quest APK: $Output"
} finally {
    $lock.Dispose()
}
