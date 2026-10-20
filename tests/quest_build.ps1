param([string]$Godot = '')

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'other_scripts/quest_build_sync.ps1')

function Assert-QuestBuild([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL $Message" }
}

function Write-Fixture([string]$Path, [string]$Text) {
    [System.IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text)
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('quest build test ' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $temp 'source project'
$stage = Join-Path $source '.godot/quest-build/project'
try {
    foreach ($file in @('build_quest.ps1', 'other_scripts/quest_build_sync.ps1')) {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $file), [ref]$tokens, [ref]$errors)
        Assert-QuestBuild ($errors.Count -eq 0) "$file parses"
    }
    Write-Fixture (Join-Path $source 'mesh/prop [one].glb') 'original model'
    Write-Fixture (Join-Path $source '.hidden-asset') 'hidden asset'
    foreach ($directory in @('.git', '.godot', '.aws', 'build', 'demo')) {
        Write-Fixture (Join-Path $source "$directory/excluded.txt") 'not copied'
    }
    Write-Fixture (Join-Path $source 'override.cfg') 'desktop override'
    Write-Fixture (Join-Path $source 'old.apk') 'old apk'
    Write-Fixture (Join-Path $stage '.godot/imported/cached.ctex') 'quest cache'
    Write-Fixture (Join-Path $stage 'override.cfg') 'quest override'
    Write-Fixture (Join-Path $stage 'stale/model.glb') 'stale model'
    Sync-QuestProject $source $stage
    Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $stage 'mesh/prop [one].glb') -Raw) -eq 'original model') 'copies literal paths with spaces and brackets'
    Assert-QuestBuild (Test-Path -LiteralPath (Join-Path $stage '.hidden-asset')) 'copies hidden assets'
    Assert-QuestBuild (-not (Test-Path -LiteralPath (Join-Path $stage 'stale'))) 'removes stale directories'
    foreach ($directory in @('.git', '.aws', 'build', 'demo')) {
        Assert-QuestBuild (-not (Test-Path -LiteralPath (Join-Path $stage $directory))) "excludes $directory"
    }
    Assert-QuestBuild (-not (Test-Path -LiteralPath (Join-Path $stage 'old.apk'))) 'excludes exported packages'
    Assert-QuestBuild (-not (Test-Path -LiteralPath (Join-Path $stage '.godot/quest-build'))) 'does not recursively copy staging'
    Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $stage 'override.cfg') -Raw) -eq 'quest override') 'preserves quest override'
    $model = Join-Path $stage 'mesh/prop [one].glb'
    $timestamp = [System.IO.File]::GetLastWriteTimeUtc($model)
    Sync-QuestProject $source $stage
    Assert-QuestBuild ([System.IO.File]::GetLastWriteTimeUtc($model) -eq $timestamp) 'unchanged assets keep their timestamps'
    Write-Fixture (Join-Path $source 'mesh/prop [one].glb') 'updated model content'
    Sync-QuestProject $source $stage
    Assert-QuestBuild ((Get-Content -LiteralPath $model -Raw) -eq 'updated model content') 'updates changed assets'
    Remove-Item -LiteralPath (Join-Path $source 'mesh/prop [one].glb')
    Sync-QuestProject $source $stage
    Assert-QuestBuild (-not (Test-Path -LiteralPath $model)) 'removes deleted assets'
    Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $stage '.godot/imported/cached.ctex') -Raw) -eq 'quest cache') 'keeps quest cache across syncs'
    Assert-QuestBuild (Test-Path -LiteralPath (Join-Path $source '.godot/excluded.txt')) 'source cache is untouched'

    Write-Fixture (Join-Path $stage 'android/build/gradlew') 'staged gradle template'
    Write-Fixture (Join-Path $source 'android/build/gradlew') 'desktop template'
    Write-Fixture (Join-Path $source 'addons/vendor/.bin/android/debug/plugin.aar') 'vendor library'
    Sync-QuestProject $source $stage -PreserveDirectories @('android')
    Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $stage 'android/build/gradlew') -Raw) -eq 'staged gradle template') 'keeps staged gradle template separate from desktop'
    Remove-Item -LiteralPath (Join-Path $source 'android') -Recurse -Force
    Sync-QuestProject $source $stage -PreserveDirectories @('android')
    Assert-QuestBuild (Test-Path -LiteralPath (Join-Path $stage 'android/build/gradlew')) 'keeps generated gradle template across syncs'
    Assert-QuestBuild (Test-Path -LiteralPath (Join-Path $stage 'addons/vendor/.bin/android/debug/plugin.aar')) 'still copies android vendor libraries'

    if ($Godot) {
        $desktopSettings = "config_version=5`n`n[rendering]`ntextures/vram_compression/import_etc2_astc=false`n"
        Write-Fixture (Join-Path $source 'project.godot') $desktopSettings
        Copy-Item -LiteralPath (Join-Path $repo 'quest_import.cfg') -Destination $source
        Sync-QuestProject $source $stage
        & $Godot --headless --xr-mode off --path (Join-Path $repo 'other_scripts/quest_build') --script res://prepare.gd -- $stage
        Assert-QuestBuild ($LASTEXITCODE -eq 0) 'real Godot build preparation succeeds'
        $questSettings = Get-Content -LiteralPath (Join-Path $stage 'project.godot') -Raw
        Assert-QuestBuild ($questSettings -match 'import_etc2_astc=true') 'mobile import setting is applied to staged project itself'
        Assert-QuestBuild ($questSettings -match 'rendering_method.mobile="gl_compatibility"') 'android renderer uses compatibility'
        Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $source 'project.godot') -Raw) -eq $desktopSettings) 'desktop project settings stay unchanged'
    }

    if ([System.IO.Path]::DirectorySeparatorChar -eq '/') {
        # exercise the complete launcher without an android sdk or real export
        Copy-Item -LiteralPath (Join-Path $repo 'build_quest.ps1') -Destination $source
        [System.IO.Directory]::CreateDirectory((Join-Path $source 'other_scripts')) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo 'other_scripts/quest_build_sync.ps1') -Destination (Join-Path $source 'other_scripts')
        Copy-Item -LiteralPath (Join-Path $repo 'quest_import.cfg') -Destination $source
        Write-Fixture (Join-Path $source 'project.godot') 'fixture project'
        $fakeGodot = Join-Path $temp 'fake godot'
        Write-Fixture $fakeGodot @'
#!/bin/sh
if [ "$1" = "--version" ]; then
    printf '4.6.3.stable\n'
    exit 0
fi
for arg in "$@"; do
    if [ "$arg" = "--script" ]; then exit 0; fi
done
printf '%s\n' "$@" > "$0.args"
for arg in "$@"; do output="$arg"; done
printf 'test apk' > "$output"
'@
        & chmod +x $fakeGodot
        & (Join-Path $source 'build_quest.ps1') -Godot $fakeGodot
        Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $source 'build/flowstate-quest.apk') -Raw) -eq 'test apk') 'launcher publishes default output'
        Assert-QuestBuild ((Get-Content -LiteralPath "$fakeGodot.args") -contains '--install-android-build-template') 'first build installs android template'
        Write-Fixture (Join-Path $stage 'android/build/gradlew') 'staged gradle template'
        & (Join-Path $source 'build_quest.ps1') -Godot $fakeGodot -Output 'custom output/game.apk' -Release
        Assert-QuestBuild ((Get-Content -LiteralPath "$fakeGodot.args") -notcontains '--install-android-build-template') 'repeat build reuses android template'
        Assert-QuestBuild (Test-Path -LiteralPath (Join-Path $source 'custom output/game.apk')) 'launcher supports custom output and repeat builds'
        Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $source 'override.cfg') -Raw) -eq 'desktop override') 'launcher never changes desktop overrides'
        Assert-QuestBuild ((Get-Content -LiteralPath (Join-Path $stage 'override.cfg') -Raw) -match 'import_etc2_astc=true') 'launcher enables quest textures in staging only'
    }
    Write-Host 'PASS quest build'
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
