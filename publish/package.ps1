# Builds the ESOUI upload zip: publish\AchievementCategoryFilter-<version>.zip
# The zip holds only the AchievementCategoryFilter folder, with forward-slash paths
# (Compress-Archive in Windows PowerShell 5.1 writes backslashes, which some extractors mishandle).
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$addonName = "AchievementCategoryFilter"
$repoRoot = Split-Path -Parent $PSScriptRoot
$addonDir = Join-Path $repoRoot $addonName
$manifest = Join-Path $addonDir "$addonName.txt"

$version = (Select-String -Path $manifest -Pattern '^## Version:\s*(\S+)').Matches[0].Groups[1].Value
$zipPath = Join-Path $PSScriptRoot "$addonName-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Confirm:$false }

# Only ship the addon's own files, never hidden or editor files (.git, desktop.ini, ...).
$files = Get-ChildItem -Path $addonDir -Recurse -File |
    Where-Object { $_.Name -notmatch '^\.' -and $_.Name -ne 'desktop.ini' -and $_.Name -ne 'Thumbs.db' }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($addonDir.Length + 1).Replace('\', '/')
        $entryName = "$addonName/$relative"
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        Write-Output "  $entryName"
    }
} finally {
    $zip.Dispose()
}
Write-Output "Built $zipPath"
