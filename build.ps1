# build.ps1 — Starfleet Kodi Plugin Build & Deploy Script
# Usage: .\build.ps1
# Reads version from addon.xml automatically.

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$pluginSrc = "$PSScriptRoot\plugin.video.starfleet"
$repoDir   = "$PSScriptRoot\..\repository.starfleet"
$kodiDir   = "$env:APPDATA\Kodi\addons\plugin.video.starfleet"

# Read version from addon.xml
$addonXml = [xml](Get-Content "$pluginSrc\addon.xml")
$version  = $addonXml.addon.version
$zipName  = "plugin.video.starfleet-$version.zip"
$zipPath  = "$repoDir\plugin.video.starfleet\$zipName"

Write-Host "Building v$version -> $zipName"

# Remove any existing zip for this version
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# Build zip with correct plugin.video.starfleet\ prefix on all entries
$zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
$archive   = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

Get-ChildItem $pluginSrc -Recurse -File | Where-Object {
    # $pluginSrc doubles as the zip/index.html output directory (same folder
    # build.ps1 writes $zipPath into) -- without this filter, every past
    # release's .zip gets recursively bundled INSIDE the next one, and the
    # bloat compounds every single build (confirmed live: produced a 1.6GB
    # zip containing 167 nested historical zips instead of the real ~20MB
    # addon). index.html is repo/download-page content, not addon content.
    $_.Extension -ne '.zip' -and $_.Name -ne 'index.html'
} | ForEach-Object {
    $relative  = $_.FullName.Substring($pluginSrc.Length + 1).Replace('\', '/')
    $entryName = "plugin.video.starfleet/$relative"
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entryName) | Out-Null
}

$archive.Dispose()
$zipStream.Dispose()
Write-Host "Zip built: $zipPath"

# Update addons.xml version
$addonsXmlPath = "$repoDir\addons.xml"
$raw = Get-Content $addonsXmlPath -Raw
# Replace version on the plugin.video.starfleet addon line
$raw = $raw -replace '(<addon id="plugin\.video\.starfleet"[^>]+version=")[^"]+(")', "`${1}$version`${2}"
Set-Content $addonsXmlPath $raw -Encoding UTF8 -NoNewline
Write-Host "addons.xml updated to v$version"

# Update MD5
$md5 = (Get-FileHash $addonsXmlPath -Algorithm MD5).Hash.ToLower()
Set-Content "$repoDir\addons.xml.md5" $md5 -Encoding ascii -NoNewline
Write-Host "addons.xml.md5: $md5"

# Update plugin.video.starfleet/index.html — prepend new zip link at top
$indexPath = "$repoDir\plugin.video.starfleet\index.html"
$indexRaw  = Get-Content $indexPath -Raw
$newLink   = "<a href=`"$zipName`">$zipName</a>"
if ($indexRaw -notmatch [regex]::Escape($zipName)) {
    $indexRaw = $indexRaw -replace '(<hr>\r?\n)', "`$1$newLink`n"
    Set-Content $indexPath $indexRaw -Encoding UTF8 -NoNewline
    Write-Host "plugin.video.starfleet/index.html updated"
}

# Sync to local Kodi install
if (Test-Path $kodiDir) {
    # Same reasoning as the zip-build filter above: $pluginSrc's root also
    # holds every past release .zip and index.html, neither of which belong
    # in the actual installed Kodi addon folder.
    Get-ChildItem $pluginSrc -File | Where-Object {
        $_.Extension -ne '.zip' -and $_.Name -ne 'index.html'
    } | ForEach-Object {
        Copy-Item $_.FullName -Destination $kodiDir -Force
    }
    Get-ChildItem $pluginSrc -Directory | ForEach-Object {
        Copy-Item $_.FullName -Destination $kodiDir -Recurse -Force
    }
    Write-Host "Synced to local Kodi install"
}

# Git commit and push
Push-Location $repoDir
git add "plugin.video.starfleet/$zipName" "plugin.video.starfleet/index.html" addons.xml addons.xml.md5
git commit -m "Release v$version"
git push
Pop-Location

Write-Host ""
Write-Host "Done. v$version is live on the repo."
