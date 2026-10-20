function Test-QuestBuildExcluded([System.IO.FileSystemInfo]$Item) {
    if ($Item.PSIsContainer) {
        return $Item.Name -in @('.git', '.godot', '.claude', '.codex', '.agents', '.aws', 'build', 'demo')
    }
    return $Item.Name -in @('override.cfg', '.DS_Store') -or $Item.Extension -in @('.apk', '.aab', '.log')
}

function Sync-QuestProject([string]$Source, [string]$Destination, [string[]]$PreserveDirectories = @()) {
    # never follow links outside the project or into another cache
    foreach ($directory in @($Source, $Destination)) {
        if (Test-Path -LiteralPath $directory) {
            $item = Get-Item -LiteralPath $directory -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Quest build folders must not be symbolic links: $directory"
            }
        }
    }
    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ((Test-QuestBuildExcluded $item) -or ($item.PSIsContainer -and $item.Name -in $PreserveDirectories)) {
            continue
        }
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "Quest build cannot copy symbolic links: $($item.FullName)"
        }
        $target = Join-Path $Destination $item.Name
        $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($existing -and (($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
                $existing.PSIsContainer -ne $item.PSIsContainer)) {
            Remove-Item -LiteralPath $target -Recurse -Force
            $existing = $null
        }
        if ($item.PSIsContainer) {
            Sync-QuestProject -Source $item.FullName -Destination $target
        } elseif (-not $existing -or $item.Length -ne $existing.Length -or
                $item.LastWriteTimeUtc -ne $existing.LastWriteTimeUtc) {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
    # remove stale staged assets but preserve excluded caches and overrides
    foreach ($item in Get-ChildItem -LiteralPath $Destination -Force) {
        if (-not (Test-QuestBuildExcluded $item) -and
                -not ($item.PSIsContainer -and $item.Name -in $PreserveDirectories) -and
                -not (Test-Path -LiteralPath (Join-Path $Source $item.Name))) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }
    }
}
