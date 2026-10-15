# KTO.TY - standalone Cloudflare installer. All project files are embedded below.
# The embedded payload contains the supplied Groq key. Do not publish this file.
[CmdletBinding()]
param(
    [string]$InstallDir = '',
    [string]$Name = 'kto-ty-quiz',
    [string]$DatabaseName = '',
    [string]$DatabaseId = '',
    [string]$AccountId = ''
)
$ErrorActionPreference = 'Stop'
$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    # Resolve paths in the script body, not in parameter default expressions (PS 5.1).
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        $scriptFolder = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($scriptFolder) -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
            $scriptFolder = [IO.Path]::GetDirectoryName($PSCommandPath)
        }
        if ([string]::IsNullOrWhiteSpace($scriptFolder) -and $MyInvocation.MyCommand.Path) {
            $scriptFolder = [IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
        }
        if ([string]::IsNullOrWhiteSpace($scriptFolder)) {
            $scriptFolder = (Get-Location).ProviderPath
        }
        $InstallDir = Join-Path -Path $scriptFolder -ChildPath 'kto-ty-site'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $InstallDir = [IO.Path]::GetFullPath($InstallDir)
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "`nKTO.TY - all-in-one Cloudflare deployment" -ForegroundColor Magenta
    Write-Host "Project folder: $InstallDir"
    Write-Host 'Internet access and a Cloudflare account are required. No Python or admin access needed.'
    Write-Host "`nExtracting embedded site files..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archivePath = Join-Path $InstallDir '.installer-payload.zip'
    [IO.File]::WriteAllBytes($archivePath, [Convert]::FromBase64String($EmbeddedPayload))
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $rootPrefix = $InstallDir.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        foreach ($entry in $archive.Entries) {
            $destination = [IO.Path]::GetFullPath((Join-Path $InstallDir $entry.FullName))
            if (-not $destination.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid archive path.' }
            if ($entry.FullName.EndsWith('/')) {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                continue
            }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
            $source = $entry.Open()
            $target = [IO.File]::Open($destination, [IO.FileMode]::Create, [IO.FileAccess]::Write)
            try { $source.CopyTo($target) } finally { $target.Dispose(); $source.Dispose() }
        }
    } finally { $archive.Dispose(); Remove-Item $archivePath -ErrorAction SilentlyContinue }

    $tools = Join-Path $InstallDir '.tools'
    $nodeHome = Join-Path $tools 'node'
    $nodeExe = Join-Path $nodeHome 'node.exe'
    $npmCli = Join-Path $nodeHome 'node_modules\npm\bin\npx-cli.js'
    if (-not (Test-Path $nodeExe) -or -not (Test-Path $npmCli)) {
        Write-Host "`nDownloading portable Node.js LTS (first run only)..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $tools -Force | Out-Null
        $archSource = $env:PROCESSOR_ARCHITEW6432
        if (-not $archSource) { $archSource = $env:PROCESSOR_ARCHITECTURE }
        if ($archSource -eq 'ARM64') { $arch = 'arm64' }
        elseif ($archSource -eq 'AMD64') { $arch = 'x64' }
        else { throw '64-bit Windows (x64 or ARM64) is required for the bundled Node runtime.' }
        $releases = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
        $chosen = $null
        foreach ($release in $releases) {
            if ($release.lts -is [string] -and $release.lts -and $release.files -contains "win-$arch-zip") {
                $major = [int](([string]$release.version).TrimStart('v').Split('.')[0])
                if ($major -ge 22) { $chosen = $release; break }
            }
        }
        if ($null -eq $chosen) { throw 'Could not find a supported Node.js LTS release for this Windows architecture.' }
        $version = [string]$chosen.version
        $fileName = "node-$version-win-$arch.zip"
        $download = Join-Path $tools 'node-download.zip'
        $baseUrl = "https://nodejs.org/dist/$version"
        Write-Host "Downloading $fileName ..."
        Invoke-WebRequest -Uri "$baseUrl/$fileName" -OutFile $download -UseBasicParsing
        $checksums = [string](Invoke-WebRequest -Uri "$baseUrl/SHASUMS256.txt" -UseBasicParsing).Content
        $expectedHash = ''
        foreach ($line in ($checksums -split "`n")) {
            $parts = $line.Trim() -split '\s+'
            if ($parts.Count -eq 2 -and $parts[1] -eq $fileName) { $expectedHash = $parts[0]; break }
        }
        if (-not $expectedHash) { throw 'Node.js checksum was not found. Download was not installed.' }
        $actualHash = (Get-FileHash $download -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) { Remove-Item $download -ErrorAction SilentlyContinue; throw 'Node.js SHA256 mismatch. Run the installer again.' }
        $unpack = Join-Path $tools 'node-unpack'
        if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
        [IO.Compression.ZipFile]::ExtractToDirectory($download, $unpack)
        if (Test-Path $nodeHome) { Remove-Item $nodeHome -Recurse -Force }
        Move-Item (Join-Path $unpack "node-$version-win-$arch") $nodeHome
        Remove-Item $download -Force
        Remove-Item $unpack -Recurse -Force
    }
    $env:PATH = "$nodeHome;$env:PATH"
    $env:KTO_WORKER_NAME = $Name
    $env:KTO_DATABASE_NAME = $DatabaseName
    $env:KTO_DATABASE_ID = $DatabaseId
    $env:KTO_ACCOUNT_ID = $AccountId
    Write-Host "`nStarting Wrangler deployment..." -ForegroundColor Cyan
    & $nodeExe (Join-Path $InstallDir 'deploy.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Deployment did not finish. See the error above. Run this same installer again after fixing it.' }
    Write-Host "`nSUCCESS. The site URL is in the Wrangler output above." -ForegroundColor Green
    Write-Host 'Keep this installer private: it contains your API key.' -ForegroundColor Yellow
} catch {
    Write-Host "`nINSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'No cloud database was deleted. Existing cloud data is preserved.'
    $ProgressPreference = $oldProgress
    exit 1
} finally {
    $ProgressPreference = $oldProgress
}
