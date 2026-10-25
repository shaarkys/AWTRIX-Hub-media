param([switch]$Execute)
$ErrorActionPreference = 'Stop'

# Only remove the two original folders after every original byte is recoverable
# and this checkout's current commit is confirmed on GitHub. Default is dry-run.
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '..'))
$inventoryPath = Join-Path $projectRoot 'archive/pre-consolidation-2026-10-25.json'
$archivePath = Join-Path $projectRoot 'archive/pre-consolidation-2026-10-25.zip'
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $inventory.archive_sha256) {
    throw 'Recovery archive does not match its committed SHA-256.'
}
$localCommit = (& git -C $projectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot read local Git commit.' }
$remoteUrl = & git -C $projectRoot remote get-url origin
if ($LASTEXITCODE -ne 0 -or $remoteUrl -notmatch 'github\.com[:/]shaarkys/AWTRIX-Hub-media(?:\.git)?$') {
    throw 'Cleanup requires the published shaarkys/AWTRIX-Hub-media GitHub remote.'
}
$remoteLine = & git -C $projectRoot ls-remote origin refs/heads/main
if ($LASTEXITCODE -ne 0 -or !$remoteLine) { throw 'Cannot verify GitHub backup.' }
if (($remoteLine -split '\s+')[0] -ne $localCommit) { throw 'Push the current commit before cleanup.' }
if (& git -C $projectRoot status --porcelain --untracked-files=normal) {
    throw 'Commit all active project changes before cleanup.'
}

$folderNames = @('SolarApp-extension', 'com.haassohn.pellets/docs/awtrixng')
$validatedFolders = @()
foreach ($relative in $folderNames) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $relative))
    if (!$candidate.StartsWith($workspaceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target leaves the workspace: $candidate"
    }
    if (!(Test-Path -LiteralPath $candidate)) { continue }
    $ancestor = $candidate
    while ($ancestor.Length -ge $workspaceRoot.Length) {
        if ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing a junction or symlink ancestor: $ancestor"
        }
        if ($ancestor -eq $workspaceRoot) { break }
        $ancestor = Split-Path -Parent $ancestor
    }
    $items = @(Get-Item -LiteralPath $candidate) + @(Get-ChildItem -LiteralPath $candidate -Force -Recurse)
    if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw "Refusing a junction or symlink in $candidate"
    }
    $expected = @{}
    foreach ($entry in $inventory.files) {
        if ($entry.path.StartsWith($relative + '/', [StringComparison]::Ordinal)) {
            $expected[$entry.path.Substring($relative.Length + 1)] = $entry.sha256
        }
    }
    $files = @($items | Where-Object { !$_.PSIsContainer })
    if (!$expected.Count -or $files.Count -ne $expected.Count) { throw "File inventory changed in $candidate" }
    foreach ($file in $files) {
        $key = $file.FullName.Substring($candidate.Length + 1).Replace('\', '/')
        if (!$expected.ContainsKey($key) -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[$key]) {
            throw "Unarchived or modified file: $($file.FullName)"
        }
    }
    $validatedFolders += $candidate
    Write-Output "Verified archived folder: $candidate ($($files.Count) files)"
}
$oldZip = [IO.Path]::GetFullPath((Join-Path $workspaceRoot 'AWTRIX-Hub-media.zip'))
if (Test-Path -LiteralPath $oldZip) {
    $entry = @($inventory.files | Where-Object { $_.path -eq 'AWTRIX-Hub-media.zip' })
    if ($entry.Count -ne 1 -or (Get-FileHash -LiteralPath $oldZip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry[0].sha256) {
        throw 'The old sibling ZIP changed after the recovery snapshot.'
    }
}
if (!$Execute) {
    Write-Output 'DRY RUN: backup and target checks passed. Supply -Execute to remove the verified old copies.'
    exit 0
}
foreach ($folder in $validatedFolders) {
    Remove-Item -LiteralPath $folder -Recurse -Force
    Write-Output "Removed archived old copy: $folder"
}
if (Test-Path -LiteralPath $oldZip) {
    Remove-Item -LiteralPath $oldZip -Force
    Write-Output "Removed archived sibling ZIP: $oldZip"
}
